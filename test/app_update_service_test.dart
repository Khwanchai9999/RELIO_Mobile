import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/core/app_update/public_update_errors.dart';
import 'package:relio_mobile/core/app_update/app_update_service.dart';
import 'package:relio_mobile/core/app_update/public_update_manifest.dart';
import 'package:relio_mobile/core/app_update/public_update_provider.dart';

class _FakeGateway implements AppUpdateGateway {
  _FakeGateway(this.nextResult);

  AppUpdateGatewayResult nextResult;
  int calls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<AppUpdateGatewayResult> checkForUpdate() async {
    calls++;
    return nextResult;
  }
}

class _FakeClock implements AppUpdateClock {
  DateTime value;

  _FakeClock(this.value);

  @override
  DateTime now() => value;
}

void main() {
  group('AppUpdateService', () {
    test('QA can run the official update check through its gateway', () async {
      final gateway = _FakeGateway(
        const AppUpdateGatewayResult(status: AppUpdateStatus.checked),
      );
      final service = AppUpdateService(
        gateway: gateway,
        enabled: true,
        environment: RelioEnvironment.test,
        currentBuild: '0.8.5+11',
      );

      final result = await service.checkForUpdate(manual: true);

      expect(service.isAvailable, isTrue);
      expect(result.status, AppUpdateStatus.checked);
      expect(result.currentBuild, '0.8.5+11');
      expect(gateway.calls, 1);
      service.dispose();
    });

    test('DEV and PROD are unavailable without calling the gateway', () async {
      for (final environment in [
        RelioEnvironment.development,
        RelioEnvironment.production,
      ]) {
        final gateway = _FakeGateway(
          const AppUpdateGatewayResult(status: AppUpdateStatus.checked),
        );
        final service = AppUpdateService(
          gateway: gateway,
          enabled: false,
          environment: environment,
        );

        final result = await service.checkForUpdate();

        expect(service.isAvailable, isFalse);
        expect(result.status, AppUpdateStatus.notApplicable);
        expect(gateway.calls, 0);
        service.dispose();
      }
    });

    test('manual check bypasses the automatic cooldown', () async {
      final clock = _FakeClock(DateTime(2026, 9, 25, 10));
      final gateway = _FakeGateway(
        const AppUpdateGatewayResult(status: AppUpdateStatus.noUpdate),
      );
      final service = AppUpdateService(
        gateway: gateway,
        clock: clock,
        enabled: true,
        environment: RelioEnvironment.test,
      );

      await service.checkForUpdate();
      await service.checkForUpdate();
      expect(gateway.calls, 1);

      await service.checkForUpdate(manual: true);
      expect(gateway.calls, 2);
      expect(service.snapshot.status, AppUpdateStatus.noUpdate);
      service.dispose();
    });

    test('maps no-update and update-available gateway results', () async {
      final gateway = _FakeGateway(
        const AppUpdateGatewayResult(status: AppUpdateStatus.updateAvailable),
      );
      final service = AppUpdateService(
        gateway: gateway,
        enabled: true,
        environment: RelioEnvironment.test,
      );

      final available = await service.checkForUpdate(manual: true);
      expect(available.status, AppUpdateStatus.updateAvailable);

      gateway.nextResult = const AppUpdateGatewayResult(
        status: AppUpdateStatus.noUpdate,
      );
      final noUpdate = await service.checkForUpdate(manual: true);
      expect(noUpdate.status, AppUpdateStatus.noUpdate);
      service.dispose();
    });

    test(
      'preserves safe error mapping without exposing exception text',
      () async {
        final gateway = _FakeGateway(
          const AppUpdateGatewayResult(
            status: AppUpdateStatus.unavailable,
            code: 'sdkUnavailable',
          ),
        );
        final service = AppUpdateService(
          gateway: gateway,
          enabled: true,
          environment: RelioEnvironment.test,
        );

        final result = await service.checkForUpdate(manual: true);

        expect(result.status, AppUpdateStatus.unavailable);
        expect(result.code, 'sdkUnavailable');
        service.dispose();
      },
    );

    test('a thrown gateway error becomes a safe error state', () async {
      final gateway = _ThrowingGateway();
      final service = AppUpdateService(
        gateway: gateway,
        enabled: true,
        environment: RelioEnvironment.test,
      );

      final result = await service.checkForUpdate(manual: true);

      expect(result.status, AppUpdateStatus.error);
      expect(result.code, 'gatewayError');
      service.dispose();
    });

    test(
      'classifies QA runtime failures without exposing exception text',
      () async {
        final cases = <Object, String>{
          SocketException('dns', osError: OSError('dns', 7)):
              PublicUpdateErrorCode.dnsError,
          SocketException('socket', osError: OSError('socket', 111)):
              PublicUpdateErrorCode.socketError,
          TimeoutException('timeout'): PublicUpdateErrorCode.timeoutError,
          HandshakeException('tls'): PublicUpdateErrorCode.tlsError,
          const PublicUpdateProviderException(PublicUpdateErrorCode.httpError):
              PublicUpdateErrorCode.httpError,
          FormatException('json'): PublicUpdateErrorCode.jsonError,
          const PublicUpdateValidationException('wrongPackage'):
              PublicUpdateErrorCode.manifestValidationError,
          const PublicUpdateValidationException('unapprovedApkUrl'):
              PublicUpdateErrorCode.urlValidationError,
          StateError('unexpected'): PublicUpdateErrorCode.unexpectedError,
        };

        for (final entry in cases.entries) {
          final service = AppUpdateService(
            provider: _ThrowingProvider(entry.key),
            enabled: true,
            environment: RelioEnvironment.test,
            currentBuild: '0.8.6+12',
          );

          final result = await service.checkForUpdate(manual: true);

          expect(result.status, AppUpdateStatus.error);
          expect(result.code, entry.value);
          service.dispose();
        }
      },
    );
  });
}

class _ThrowingGateway implements AppUpdateGateway {
  @override
  bool get isAvailable => true;

  @override
  Future<AppUpdateGatewayResult> checkForUpdate() {
    throw StateError('test-only failure');
  }
}

class _ThrowingProvider implements AppUpdateProvider {
  _ThrowingProvider(this.error);

  final Object error;

  @override
  bool get isAvailable => true;

  @override
  Future<AppUpdateProviderResult> checkForUpdate({
    required int currentBuild,
  }) async {
    throw error;
  }

  @override
  Future<AppUpdateDownloadResult> download(
    PublicQaUpdateManifest manifest, {
    required Directory directory,
    required bool Function() isCancelled,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    throw error;
  }
}
