import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../app/environment.dart';

enum AppUpdateStatus {
  notApplicable,
  unavailable,
  checking,
  noUpdate,
  checked,
  updateAvailable,
  updateStarted,
  error,
}

class AppUpdateSnapshot {
  const AppUpdateSnapshot({
    required this.status,
    required this.currentBuild,
    required this.environment,
    this.latestBuild,
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
  final String? code;
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
      final raw = await _channel.invokeMethod<Object?>('checkForUpdate');
      final values = raw is Map ? raw : const <Object?, Object?>{};
      final status = switch (values['status']) {
        'updateAvailable' => AppUpdateStatus.updateAvailable,
        'updateStarted' => AppUpdateStatus.updateStarted,
        'noUpdate' => AppUpdateStatus.noUpdate,
        'checked' => AppUpdateStatus.checked,
        'notApplicable' => AppUpdateStatus.notApplicable,
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

class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    AppUpdateGateway? gateway,
    AppUpdateClock? clock,
    RelioEnvironment? environment,
    String? currentBuild,
    this.cooldown = const Duration(minutes: 30),
    bool? enabled,
  }) : _gateway = gateway ?? MethodChannelAppUpdateGateway(),
       _clock = clock ?? const SystemAppUpdateClock(),
       _enabled =
           enabled ?? (RelioBuildInfo.environment == RelioEnvironment.test),
       _snapshot = AppUpdateSnapshot.initial(
         currentBuild: currentBuild ?? RelioBuildInfo.buildLabel,
         environment: (environment ?? RelioBuildInfo.environment).name,
       );

  final AppUpdateGateway _gateway;
  final AppUpdateClock _clock;
  final bool _enabled;
  final Duration cooldown;
  final _changes = StreamController<AppUpdateSnapshot>.broadcast();
  AppUpdateSnapshot _snapshot;
  DateTime? _lastAttemptAt;
  Future<AppUpdateSnapshot>? _operation;

  AppUpdateSnapshot get snapshot => _snapshot;

  String get currentBuild => _snapshot.currentBuild;

  String get environment => _snapshot.environment;

  bool get isAvailable => _enabled && _gateway.isAvailable;

  Stream<AppUpdateSnapshot> watchState() => _changes.stream;

  Future<AppUpdateSnapshot> checkForUpdate({bool manual = false}) {
    if (!isAvailable) {
      _setSnapshot(
        AppUpdateSnapshot(
          status: AppUpdateStatus.notApplicable,
          currentBuild: _snapshot.currentBuild,
          environment: _snapshot.environment,
          code: _enabled ? 'sdkUnavailable' : 'environmentNotEligible',
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
    final operation = _checkGateway();
    _operation = operation;
    return operation.whenComplete(() => _operation = null);
  }

  Future<AppUpdateSnapshot> _checkGateway() async {
    try {
      final result = await _gateway.checkForUpdate();
      final next = AppUpdateSnapshot(
        status: result.status,
        currentBuild: _snapshot.currentBuild,
        environment: _snapshot.environment,
        latestBuild: result.latestBuild,
        code: result.code,
      );
      _setSnapshot(next);
      return next;
    } on Object {
      const result = AppUpdateSnapshot(
        status: AppUpdateStatus.error,
        currentBuild: '',
        environment: '',
        code: 'gatewayError',
      );
      final next = AppUpdateSnapshot(
        status: result.status,
        currentBuild: _snapshot.currentBuild,
        environment: _snapshot.environment,
        code: result.code,
      );
      _setSnapshot(next);
      return next;
    }
  }

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
