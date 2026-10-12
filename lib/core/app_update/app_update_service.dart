import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/environment.dart';
import 'app_update_installer.dart';
import 'public_update_errors.dart';
import 'public_update_manifest.dart';
import 'public_update_provider.dart';

enum AppUpdateStatus {
  notApplicable,
  unavailable,
  checking,
  noUpdate,
  checked,
  updateAvailable,
  updateStarted,
  downloading,
  installPermissionRequired,
  installing,
  error,
}

class AppUpdateSnapshot {
  const AppUpdateSnapshot({
    required this.status,
    required this.currentBuild,
    required this.environment,
    this.latestBuild,
    this.manifest,
    this.downloadedPath,
    this.downloadedBytes = 0,
    this.downloadTotalBytes = 0,
    this.code,
  });

  factory AppUpdateSnapshot.initial({
    required String currentBuild,
    required String environment,
  }) => AppUpdateSnapshot(
    status: AppUpdateStatus.notApplicable,
    currentBuild: currentBuild,
    environment: environment,
  );

  final AppUpdateStatus status;
  final String currentBuild;
  final String environment;
  final String? latestBuild;
  final PublicQaUpdateManifest? manifest;
  final String? downloadedPath;
  final int downloadedBytes;
  final int downloadTotalBytes;
  final String? code;
}

class AppUpdateProviderResult {
  const AppUpdateProviderResult({
    required this.status,
    this.manifest,
    this.code,
  });

  final AppUpdateStatus status;
  final PublicQaUpdateManifest? manifest;
  final String? code;
}

abstract interface class AppUpdateProvider {
  bool get isAvailable;

  Future<AppUpdateProviderResult> checkForUpdate({required int currentBuild});

  Future<AppUpdateDownloadResult> download(
    PublicQaUpdateManifest manifest, {
    required Directory directory,
    required bool Function() isCancelled,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  });
}

class PublicQaAppUpdateProvider implements AppUpdateProvider {
  PublicQaAppUpdateProvider({
    required Uri manifestUri,
    required PublicUpdateUrlPolicy urlPolicy,
    bool diagnosticLogging = false,
  }) : _provider = PublicQaUpdateProvider(
         manifestUri: manifestUri,
         urlPolicy: urlPolicy,
         diagnosticLogging: diagnosticLogging,
       );

  final PublicQaUpdateProvider _provider;

  @override
  bool get isAvailable => _provider.isAvailable;

  @override
  Future<AppUpdateProviderResult> checkForUpdate({
    required int currentBuild,
  }) async {
    final manifest = await _provider.fetchLatest(currentBuild: currentBuild);
    return AppUpdateProviderResult(
      status: manifest == null
          ? AppUpdateStatus.noUpdate
          : AppUpdateStatus.updateAvailable,
      manifest: manifest,
    );
  }

  @override
  Future<AppUpdateDownloadResult> download(
    PublicQaUpdateManifest manifest, {
    required Directory directory,
    required bool Function() isCancelled,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) => _provider.download(
    manifest,
    directory: directory,
    isCancelled: isCancelled,
    onProgress: onProgress,
  );
}

/// The Firebase provider is retained as an internal fallback, never as the
/// ordinary public QA provider. Public QA users do not need Firebase login.
class FirebaseAppDistributionUpdateProvider implements AppUpdateProvider {
  FirebaseAppDistributionUpdateProvider({AppUpdateGateway? gateway})
    : _gateway = gateway ?? MethodChannelAppUpdateGateway();

  final AppUpdateGateway _gateway;

  @override
  bool get isAvailable => _gateway.isAvailable;

  @override
  Future<AppUpdateProviderResult> checkForUpdate({
    required int currentBuild,
  }) async {
    final result = await _gateway.checkForUpdate();
    return AppUpdateProviderResult(status: result.status, code: result.code);
  }

  @override
  Future<AppUpdateDownloadResult> download(
    PublicQaUpdateManifest manifest, {
    required Directory directory,
    required bool Function() isCancelled,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) {
    throw const PublicUpdateProviderException('firebaseDownloadUnsupported');
  }
}

class AppUpdateGatewayResult {
  const AppUpdateGatewayResult({
    required this.status,
    this.latestBuild,
    this.code,
  });

  final AppUpdateStatus status;
  final String? latestBuild;
  final String? code;
}

abstract interface class AppUpdateGateway {
  bool get isAvailable;

  Future<AppUpdateGatewayResult> checkForUpdate();
}

class MethodChannelAppUpdateGateway implements AppUpdateGateway {
  MethodChannelAppUpdateGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('relio/app_update');

  final MethodChannel _channel;

  @override
  bool get isAvailable => true;

  @override
  Future<AppUpdateGatewayResult> checkForUpdate() async {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'checkForFirebaseUpdate',
      );
      final values = raw is Map ? raw : const <Object?, Object?>{};
      final status = switch (values['status']) {
        'updateAvailable' => AppUpdateStatus.updateAvailable,
        'noUpdate' => AppUpdateStatus.noUpdate,
        'checked' => AppUpdateStatus.checked,
        'unavailable' => AppUpdateStatus.unavailable,
        _ => AppUpdateStatus.error,
      };
      return AppUpdateGatewayResult(
        status: status,
        latestBuild: values['latestBuild'] as String?,
        code: values['code'] as String?,
      );
    } on MissingPluginException {
      return const AppUpdateGatewayResult(
        status: AppUpdateStatus.unavailable,
        code: 'nativeBridgeUnavailable',
      );
    } on PlatformException {
      return const AppUpdateGatewayResult(
        status: AppUpdateStatus.unavailable,
        code: 'nativeBridgeError',
      );
    } on Object {
      return const AppUpdateGatewayResult(
        status: AppUpdateStatus.error,
        code: 'unexpectedError',
      );
    }
  }
}

abstract interface class AppUpdateClock {
  DateTime now();
}

class SystemAppUpdateClock implements AppUpdateClock {
  const SystemAppUpdateClock();

  @override
  DateTime now() => DateTime.now();
}

abstract interface class AppUpdateTemporaryDirectory {
  Future<Directory> get();
}

class PathProviderAppUpdateTemporaryDirectory
    implements AppUpdateTemporaryDirectory {
  const PathProviderAppUpdateTemporaryDirectory();

  @override
  Future<Directory> get() => getTemporaryDirectory();
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    AppUpdateProvider? provider,
    AppUpdateGateway? gateway,
    AppUpdateInstaller? installer,
    AppUpdateClock? clock,
    AppUpdateTemporaryDirectory? temporaryDirectory,
    RelioEnvironment? environment,
    String? currentBuild,
    this.cooldown = const Duration(minutes: 30),
    bool? enabled,
    bool Function()? internetAvailable,
  }) : _provider =
           provider ??
           (gateway == null
               ? PublicQaAppUpdateProvider(
                   manifestUri: RelioBuildInfo.publicUpdateManifestUri,
                   urlPolicy: RelioBuildInfo.publicUpdateUrlPolicy,
                   diagnosticLogging:
                       RelioBuildInfo.environment == RelioEnvironment.test,
                 )
               : FirebaseAppDistributionUpdateProvider(gateway: gateway)),
       _installer = installer ?? MethodChannelAppUpdateInstaller(),
       _clock = clock ?? const SystemAppUpdateClock(),
       _temporaryDirectory =
           temporaryDirectory ??
           const PathProviderAppUpdateTemporaryDirectory(),
       _enabled =
           enabled ?? (RelioBuildInfo.environment == RelioEnvironment.test),
       _internetAvailable = internetAvailable ?? _alwaysOnline,
       _diagnosticLogging = RelioBuildInfo.environment == RelioEnvironment.test,
       _snapshot = AppUpdateSnapshot.initial(
         currentBuild: currentBuild ?? RelioBuildInfo.buildLabel,
         environment: (environment ?? RelioBuildInfo.environment).name,
       );

  final AppUpdateProvider _provider;
  final AppUpdateInstaller _installer;
  final AppUpdateClock _clock;
  final AppUpdateTemporaryDirectory _temporaryDirectory;
  final bool _enabled;
  final bool Function() _internetAvailable;
  final bool _diagnosticLogging;
  final Duration cooldown;
  final _changes = StreamController<AppUpdateSnapshot>.broadcast();
  AppUpdateSnapshot _snapshot;
  DateTime? _lastAttemptAt;
  Future<AppUpdateSnapshot>? _operation;
  bool _cancelDownload = false;

  AppUpdateSnapshot get snapshot => _snapshot;

  String get currentBuild => _snapshot.currentBuild;

  String get environment => _snapshot.environment;

  bool get isAvailable => _enabled && _provider.isAvailable;

  static bool _alwaysOnline() => true;

  Stream<AppUpdateSnapshot> watchState() => _changes.stream;

  Future<AppUpdateSnapshot> checkForUpdate({bool manual = false}) {
    if (!_internetAvailable()) {
      return Future.value(_setUnavailable('simulatedOffline'));
    }
    if (!isAvailable) {
      _setSnapshot(
        AppUpdateSnapshot(
          status: AppUpdateStatus.notApplicable,
          currentBuild: _snapshot.currentBuild,
          environment: _snapshot.environment,
          code: _enabled ? 'providerUnavailable' : 'environmentNotEligible',
        ),
      );
      return Future.value(_snapshot);
    }

    final now = _clock.now();
    final lastAttemptAt = _lastAttemptAt;
    if (!manual &&
        lastAttemptAt != null &&
        now.difference(lastAttemptAt) < cooldown) {
      return Future.value(_snapshot);
    }
    final currentOperation = _operation;
    if (currentOperation != null) return currentOperation;

    _lastAttemptAt = now;
    _setSnapshot(
      AppUpdateSnapshot(
        status: AppUpdateStatus.checking,
        currentBuild: _snapshot.currentBuild,
        environment: _snapshot.environment,
      ),
    );
    _log(
      'update check start provider=${_provider.runtimeType} '
      'installedVersionCode=$_currentBuildCode',
    );
    final operation = _checkProvider();
    _operation = operation;
    return operation.whenComplete(() => _operation = null);
  }

  Future<AppUpdateSnapshot> _checkProvider() async {
    try {
      final result = await _provider.checkForUpdate(
        currentBuild: _currentBuildCode,
      );
      final manifest = result.manifest;
      final isNewBuild =
          manifest != null && manifest.versionCode > _currentBuildCode;
      final status = manifest == null
          ? result.status
          : (isNewBuild
                ? AppUpdateStatus.updateAvailable
                : AppUpdateStatus.noUpdate);
      final next = AppUpdateSnapshot(
        status: status,
        currentBuild: _snapshot.currentBuild,
        environment: _snapshot.environment,
        latestBuild: manifest == null
            ? null
            : '${manifest.versionName}+${manifest.versionCode}',
        manifest: manifest,
        code: result.code,
      );
      _log(
        'final status=${next.status} '
        'remoteVersionCode=${manifest?.versionCode ?? 'none'} '
        'code=${next.code ?? 'none'}',
      );
      _setSnapshot(next);
      return next;
    } on PublicUpdateValidationException catch (error, stackTrace) {
      _logError(error.classification, error, stackTrace);
      return _setError(error.classification);
    } on PublicUpdateProviderException catch (error, stackTrace) {
      _logError(
        error.code,
        error.cause ?? error,
        error.stackTrace ?? stackTrace,
      );
      return _setError(error.code);
    } on Object catch (error, stackTrace) {
      final code = _provider is FirebaseAppDistributionUpdateProvider
          ? 'gatewayError'
          : classifyPublicUpdateError(error);
      _logError(code, error, stackTrace);
      return _setError(code);
    }
  }

  void _log(String message) {
    if (_diagnosticLogging) debugPrint('[RELIO][QA_UPDATE] $message');
  }

  void _logError(String code, Object error, StackTrace stackTrace) {
    if (!_diagnosticLogging) return;
    debugPrint(
      '[RELIO][QA_UPDATE] error code=$code '
      'type=${error.runtimeType} message=$error',
    );
    if (code == PublicUpdateErrorCode.unexpectedError) {
      debugPrint('[RELIO][QA_UPDATE] stackTrace=$stackTrace');
    }
  }

  Future<AppUpdateSnapshot> downloadAndInstall() {
    if (!_internetAvailable()) {
      return Future.value(_setUnavailable('simulatedOffline'));
    }
    final currentOperation = _operation;
    if (currentOperation != null) return currentOperation;
    final manifest = _snapshot.manifest;
    if (_snapshot.status != AppUpdateStatus.updateAvailable ||
        manifest == null) {
      return Future.value(_snapshot);
    }

    _cancelDownload = false;
    final operation = _downloadAndInstall(manifest);
    _operation = operation;
    return operation.whenComplete(() => _operation = null);
  }

  AppUpdateSnapshot _setUnavailable(String code) {
    final snapshot = AppUpdateSnapshot(
      status: AppUpdateStatus.unavailable,
      currentBuild: _snapshot.currentBuild,
      environment: _snapshot.environment,
      code: code,
    );
    _setSnapshot(snapshot);
    return snapshot;
  }

  void cancelDownload() {
    if (_snapshot.status == AppUpdateStatus.downloading) {
      _cancelDownload = true;
    }
  }

  Future<AppUpdateSnapshot> _downloadAndInstall(
    PublicQaUpdateManifest manifest,
  ) async {
    _setSnapshot(
      AppUpdateSnapshot(
        status: AppUpdateStatus.downloading,
        currentBuild: _snapshot.currentBuild,
        environment: _snapshot.environment,
        latestBuild: '${manifest.versionName}+${manifest.versionCode}',
        manifest: manifest,
        downloadTotalBytes: manifest.sizeBytes,
      ),
    );
    try {
      final temporaryDirectory = await _temporaryDirectory.get();
      final directory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}relio-updates',
      );
      final download = await _provider.download(
        manifest,
        directory: directory,
        isCancelled: () => _cancelDownload,
        onProgress: (received, total) {
          _setSnapshot(
            AppUpdateSnapshot(
              status: AppUpdateStatus.downloading,
              currentBuild: _snapshot.currentBuild,
              environment: _snapshot.environment,
              latestBuild: '${manifest.versionName}+${manifest.versionCode}',
              manifest: manifest,
              downloadedBytes: received,
              downloadTotalBytes: total,
            ),
          );
        },
      );
      final info = await _installer.inspectApk(download.path);
      final installedFingerprint = await _installer
          .getInstalledSigningFingerprint();
      if (info.packageName != manifest.packageName ||
          info.versionCode != manifest.versionCode ||
          info.versionCode <= _currentBuildCode ||
          _normaliseFingerprint(info.signingCertSha256) !=
              manifest.signingCertSha256 ||
          _normaliseFingerprint(installedFingerprint) !=
              manifest.signingCertSha256) {
        await _deleteDownloadedApk(download.path);
        return _setError('apkVerificationFailed');
      }
      final canInstall = await _installer.canRequestPackageInstalls();
      if (!canInstall) {
        _setSnapshot(
          AppUpdateSnapshot(
            status: AppUpdateStatus.installPermissionRequired,
            currentBuild: _snapshot.currentBuild,
            environment: _snapshot.environment,
            latestBuild: '${manifest.versionName}+${manifest.versionCode}',
            manifest: manifest,
            downloadedPath: download.path,
            downloadedBytes: download.sizeBytes,
            downloadTotalBytes: manifest.sizeBytes,
            code: 'installPermissionRequired',
          ),
        );
        await _installer.openInstallPermissionSettings();
        return _snapshot;
      }
      await _installer.launchInstaller(download.path);
      _setSnapshot(
        AppUpdateSnapshot(
          status: AppUpdateStatus.installing,
          currentBuild: _snapshot.currentBuild,
          environment: _snapshot.environment,
          latestBuild: '${manifest.versionName}+${manifest.versionCode}',
          manifest: manifest,
          downloadedPath: download.path,
          downloadedBytes: download.sizeBytes,
          downloadTotalBytes: manifest.sizeBytes,
        ),
      );
      return _snapshot;
    } on PublicUpdateProviderException catch (error) {
      return _setError(error.code);
    } on Object {
      return _setError('apkVerificationFailed');
    }
  }

  Future<void> _deleteDownloadedApk(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<AppUpdateSnapshot> _setError(String code) async {
    final next = AppUpdateSnapshot(
      status: AppUpdateStatus.error,
      currentBuild: _snapshot.currentBuild,
      environment: _snapshot.environment,
      latestBuild: _snapshot.latestBuild,
      manifest: _snapshot.manifest,
      code: code,
    );
    _setSnapshot(next);
    return next;
  }

  int get _currentBuildCode =>
      int.tryParse(_snapshot.currentBuild.split('+').last) ?? 0;

  static String _normaliseFingerprint(String value) =>
      value.replaceAll(':', '').toLowerCase();

  void _setSnapshot(AppUpdateSnapshot next) {
    _snapshot = next;
    if (!_changes.isClosed) _changes.add(next);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_changes.close());
    super.dispose();
  }
}
