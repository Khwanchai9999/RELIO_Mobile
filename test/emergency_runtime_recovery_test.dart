import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/connectivity/qa_internet_simulator.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/emergency/emergency_runtime_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';

void main() {
  RelioDependencies createDependencies(FakeEmergencyRuntimeService runtime) =>
      RelioDependencies(
        database: AppDatabase.memory(),
        cloudDataSource: FakeCloudDataSource(),
        internetSimulator: QaInternetSimulator.forTesting()
          ..setSimulatedOffline(true),
        emergencyRuntimeService: runtime,
        useMockTransport: true,
        androidPlatformOverride: true,
      );

  test(
    'startup restores SOS ahead of Rescue without creating a new SOS',
    () async {
      final runtime = FakeEmergencyRuntimeService();
      final dependencies = createDependencies(runtime);
      final deviceId = await dependencies.identity.getDeviceId();
      final event = await dependencies.repositories.sos.createAndActivate(
        ownerDeviceId: deviceId,
        ownerUserId: '',
        message: 'local test fixture',
      );
      await dependencies.repositories.settings.setBool('rescue_mode', true);

      await dependencies.initialize();

      expect(runtime.running, isTrue);
      expect(runtime.mode, EmergencyMode.sos);
      expect(
        (await dependencies.repositories.sos.readActive(
          ownerDeviceId: deviceId,
        ))?.id,
        event.id,
      );
      await dependencies.dispose();
    },
  );

  test(
    'startup restores Rescue and stops a stale runtime when inactive',
    () async {
      final rescueRuntime = FakeEmergencyRuntimeService();
      final rescueDependencies = createDependencies(rescueRuntime);
      await rescueDependencies.repositories.settings.setBool(
        'rescue_mode',
        true,
      );
      await rescueDependencies.initialize();
      expect(rescueRuntime.mode, EmergencyMode.rescue);
      await rescueDependencies.dispose();

      final staleRuntime = FakeEmergencyRuntimeService()..running = true;
      final inactiveDependencies = createDependencies(staleRuntime);
      await inactiveDependencies.initialize();
      expect(staleRuntime.running, isFalse);
      await inactiveDependencies.dispose();
    },
  );

  test(
    'background relay preference restores a dedicated runtime mode',
    () async {
      final runtime = FakeEmergencyRuntimeService();
      final dependencies = createDependencies(runtime);
      await dependencies.repositories.settings.setBool(
        'background_relay_enabled',
        true,
      );

      await dependencies.initialize();

      expect(dependencies.backgroundRelayEnabled, isTrue);
      expect(runtime.mode, EmergencyMode.nearbyRelay);
      expect(await runtime.isRunning(mode: EmergencyMode.sos), isFalse);
      expect(await runtime.isRunning(mode: EmergencyMode.nearbyRelay), isTrue);
      await dependencies.dispose();
    },
  );

  test(
    'emergency runtime returns to opted-in background relay when stopped',
    () async {
      final runtime = FakeEmergencyRuntimeService();
      final dependencies = createDependencies(runtime);
      await dependencies.repositories.settings.setBool(
        'background_relay_enabled',
        true,
      );
      await dependencies.repositories.settings.setBool('rescue_mode', true);

      await dependencies.initialize();
      expect(runtime.mode, EmergencyMode.rescue);
      await dependencies.repositories.settings.setBool('rescue_mode', false);

      await dependencies.stopEmergencyRuntime();

      expect(runtime.mode, EmergencyMode.nearbyRelay);
      expect(dependencies.backgroundRelayEnabled, isTrue);
      await dependencies.dispose();
    },
  );

  test('background relay toggle persists and stops its own runtime', () async {
    final runtime = FakeEmergencyRuntimeService();
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(),
      cloudDataSource: FakeCloudDataSource(),
      internetSimulator: QaInternetSimulator.forTesting()
        ..setSimulatedOffline(true),
      emergencyRuntimeService: runtime,
      useMockTransport: false,
      androidPlatformOverride: true,
    );

    expect(await dependencies.setBackgroundRelayEnabled(true), isTrue);
    expect(
      await dependencies.repositories.settings.getBool(
        'background_relay_enabled',
        defaultValue: false,
      ),
      isTrue,
    );
    expect(runtime.mode, EmergencyMode.nearbyRelay);

    expect(await dependencies.setBackgroundRelayEnabled(false), isTrue);
    expect(runtime.running, isFalse);
    expect(
      await dependencies.repositories.settings.getBool(
        'background_relay_enabled',
        defaultValue: true,
      ),
      isFalse,
    );
    await dependencies.dispose();
  });
}
