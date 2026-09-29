import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/core/app_update/app_update_installer.dart';
import 'package:relio_mobile/core/app_update/app_update_service.dart';
import 'package:relio_mobile/core/app_update/public_update_manifest.dart';
import 'package:relio_mobile/core/app_update/public_update_provider.dart';

const _signer =
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

PublicQaUpdateManifest _manifest({int versionCode = 12}) =>
    PublicQaUpdateManifest(
      schemaVersion: 1,
      channel: 'qa-public',
      packageName: 'com.relio.relio_mobile.test',
      versionName: '0.8.6',
      versionCode: versionCode,
      apkUrl: Uri.parse(
        'https://relio-17dc0.web.app/qa/relio-test-0.8.6+$versionCode.apk',
      ),
      sha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      sizeBytes: 10,
      signingCertSha256: _signer,
      publishedAt: DateTime.utc(2026, 9, 29),
      releaseNotes: const ['Test release'],
    );

class _FakeClock implements AppUpdateClock {
  DateTime value;

  _FakeClock(this.value);

  @override
  DateTime now() => value;
}

class _FakeProvider implements AppUpdateProvider {
  _FakeProvider(this.result);

  AppUpdateProviderResult result;
  AppUpdateDownloadResult? downloadResult;
  Object? downloadError;
  int checks = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<AppUpdateProviderResult> checkForUpdate({
    required int currentBuild,
  }) async {
    checks++;
    return result;
  }

  @override
  Future<AppUpdateDownloadResult> download(
    PublicQaUpdateManifest manifest, {
    required Directory directory,
    required bool Function() isCancelled,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    if (downloadError != null) throw downloadError!;
    return downloadResult ??
        const AppUpdateDownloadResult(
          path: 'does-not-exist.apk',
          sizeBytes: 10,
          sha256:
              '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        );
  }
}

class _FakeInstaller implements AppUpdateInstaller {
  _FakeInstaller({this.canInstall = true});

  bool canInstall;
  bool openedPermissionSettings = false;
  bool launched = false;
  AppUpdateApkInfo inspection = const AppUpdateApkInfo(
    packageName: 'com.relio.relio_mobile.test',
    versionCode: 12,
    signingCertSha256: _signer,
  );
  String installedSigner = _signer;

  @override
  Future<bool> canRequestPackageInstalls() async => canInstall;

  @override
  Future<String> getInstalledSigningFingerprint() async => installedSigner;

  @override
  Future<AppUpdateApkInfo> inspectApk(String path) async => inspection;

  @override
  Future<void> launchInstaller(String path) async => launched = true;

  @override
  Future<void> openInstallPermissionSettings() async =>
      openedPermissionSettings = true;
}

class _FakeDirectory implements AppUpdateTemporaryDirectory {
  @override
  Future<Directory> get() async => Directory.systemTemp;
}

void main() {
  test(
    'QA provider reports an update and same/downgrade builds are ignored',
    () async {
      final provider = _FakeProvider(
        AppUpdateProviderResult(
          status: AppUpdateStatus.updateAvailable,
          manifest: _manifest(),
        ),
      );
      final service = AppUpdateService(
        provider: provider,
        enabled: true,
        environment: RelioEnvironment.test,
        currentBuild: '0.8.5+11',
      );

      expect(
        (await service.checkForUpdate(manual: true)).status,
        AppUpdateStatus.updateAvailable,
      );
      provider.result = AppUpdateProviderResult(
        status: AppUpdateStatus.updateAvailable,
        manifest: _manifest(versionCode: 11),
      );
      expect(
        (await service.checkForUpdate(manual: true)).status,
        AppUpdateStatus.noUpdate,
      );
      service.dispose();
    },
  );

  test(
    'automatic checks use the cooldown while manual checks bypass it',
    () async {
      final provider = _FakeProvider(
        const AppUpdateProviderResult(status: AppUpdateStatus.noUpdate),
      );
      final clock = _FakeClock(DateTime(2026, 9, 29, 10));
      final service = AppUpdateService(
        provider: provider,
        clock: clock,
        enabled: true,
        environment: RelioEnvironment.test,
      );

      await service.checkForUpdate();
      await service.checkForUpdate();
      expect(provider.checks, 1);
      await service.checkForUpdate(manual: true);
      expect(provider.checks, 2);
      service.dispose();
    },
  );

  test('offline/provider failure is non-blocking and safe', () async {
    final provider =
        _FakeProvider(
            const AppUpdateProviderResult(status: AppUpdateStatus.noUpdate),
          )
          ..downloadError = const PublicUpdateProviderException(
            'downloadUnavailable',
          );
    final service = AppUpdateService(
      provider: provider,
      temporaryDirectory: _FakeDirectory(),
      enabled: true,
      environment: RelioEnvironment.test,
    );
    expect(
      (await service.checkForUpdate(manual: true)).status,
      AppUpdateStatus.noUpdate,
    );
    provider.result = AppUpdateProviderResult(
      status: AppUpdateStatus.updateAvailable,
      manifest: _manifest(),
    );
    await service.checkForUpdate(manual: true);
    expect((await service.downloadAndInstall()).status, AppUpdateStatus.error);
    expect(service.snapshot.code, 'downloadUnavailable');
    service.dispose();
  });

  test(
    'hash/package/signer verification failure blocks installer launch',
    () async {
      final provider =
          _FakeProvider(
              AppUpdateProviderResult(
                status: AppUpdateStatus.updateAvailable,
                manifest: _manifest(),
              ),
            )
            ..downloadResult = const AppUpdateDownloadResult(
              path: 'invalid.apk',
              sizeBytes: 10,
              sha256: 'wrong',
            );
      final installer = _FakeInstaller()
        ..inspection = const AppUpdateApkInfo(
          packageName: 'com.relio.relio_mobile.test',
          versionCode: 12,
          signingCertSha256: 'wrong',
        );
      final service = AppUpdateService(
        provider: provider,
        installer: installer,
        temporaryDirectory: _FakeDirectory(),
        enabled: true,
        environment: RelioEnvironment.test,
      );
      await service.checkForUpdate(manual: true);
      expect(
        (await service.downloadAndInstall()).status,
        AppUpdateStatus.error,
      );
      expect(installer.launched, isFalse);
      service.dispose();
    },
  );

  test(
    'install permission is user-controlled and granted state launches installer',
    () async {
      final provider =
          _FakeProvider(
              AppUpdateProviderResult(
                status: AppUpdateStatus.updateAvailable,
                manifest: _manifest(),
              ),
            )
            ..downloadResult = const AppUpdateDownloadResult(
              path: 'valid.apk',
              sizeBytes: 10,
              sha256:
                  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
            );
      final installer = _FakeInstaller(canInstall: false);
      final service = AppUpdateService(
        provider: provider,
        installer: installer,
        temporaryDirectory: _FakeDirectory(),
        enabled: true,
        environment: RelioEnvironment.test,
      );
      await service.checkForUpdate(manual: true);
      expect(
        (await service.downloadAndInstall()).status,
        AppUpdateStatus.installPermissionRequired,
      );
      expect(installer.openedPermissionSettings, isTrue);
      expect(installer.launched, isFalse);
      service.dispose();

      final grantedInstaller = _FakeInstaller();
      final grantedService = AppUpdateService(
        provider: provider,
        installer: grantedInstaller,
        temporaryDirectory: _FakeDirectory(),
        enabled: true,
        environment: RelioEnvironment.test,
      );
      await grantedService.checkForUpdate(manual: true);
      expect(
        (await grantedService.downloadAndInstall()).status,
        AppUpdateStatus.installing,
      );
      expect(grantedInstaller.launched, isTrue);
      grantedService.dispose();
    },
  );

  test(
    'DEV and PROD updater are disabled even when a provider is available',
    () async {
      for (final environment in [
        RelioEnvironment.development,
        RelioEnvironment.production,
      ]) {
        final provider = _FakeProvider(
          const AppUpdateProviderResult(
            status: AppUpdateStatus.updateAvailable,
          ),
        );
        final service = AppUpdateService(
          provider: provider,
          enabled: false,
          environment: environment,
        );
        expect(
          (await service.checkForUpdate()).status,
          AppUpdateStatus.notApplicable,
        );
        expect(provider.checks, 0);
        service.dispose();
      }
    },
  );
}
