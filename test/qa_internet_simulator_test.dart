import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/cloud/supabase_cloud_data_source.dart';
import 'package:relio_mobile/core/connectivity/qa_internet_simulator.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/connectivity/runtime_connectivity.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';

class _RuntimeSource implements RuntimeConnectivitySource {
  _RuntimeSource(this.snapshot);

  final RuntimeConnectivitySnapshot snapshot;

  @override
  Future<RuntimeConnectivitySnapshot> read() async => snapshot;

  @override
  Stream<RuntimeConnectivitySnapshot> get changes => const Stream.empty();
}

class _Probe implements InternetReachabilityProbe {
  int calls = 0;

  @override
  Future<int> reachableEndpointCount() async {
    calls++;
    return 1;
  }
}

void main() {
  test('non-QA builds cannot enable the simulator and default is online', () {
    final simulator = QaInternetSimulator.forTesting(qaBuild: false);
    addTearDown(simulator.dispose);

    expect(simulator.available, isFalse);
    expect(simulator.simulatedOffline, isFalse);
    expect(simulator.internetAvailable, isTrue);
    simulator.setSimulatedOffline(true);
    expect(simulator.simulatedOffline, isFalse);
  });

  test('QA simulator restores an explicit offline choice across restarts', () {
    final simulator = QaInternetSimulator.forTesting();
    addTearDown(simulator.dispose);

    simulator.restore(true);

    expect(simulator.simulatedOffline, isTrue);
    expect(simulator.internetAvailable, isFalse);

    final production = QaInternetSimulator.forTesting(qaBuild: false);
    addTearDown(production.dispose);
    production.restore(true);
    expect(production.simulatedOffline, isFalse);
    expect(production.internetAvailable, isTrue);
  });

  test('restores offline state before Cloud auth initializes', () async {
    final database = AppDatabase.memory();
    final simulator = QaInternetSimulator.forTesting();
    final cloud = SupabaseCloudDataSource(
      configuration: const SupabaseConfig(
        url: 'https://qa.invalid',
        anonKey: 'qa-public-anon-key',
      ),
      internetSimulator: simulator,
    );
    final dependencies = RelioDependencies(
      database: database,
      cloudDataSource: cloud,
      internetSimulator: simulator,
      useMockTransport: true,
    );
    addTearDown(() async {
      await dependencies.dispose();
    });
    await dependencies.repositories.settings.setBool(
      'qa_simulated_internet_offline',
      true,
    );

    await dependencies.initializeAuth();

    expect(simulator.simulatedOffline, isTrue);
    expect(cloud.cloudState, CloudState.offline);
  });

  test(
    'QA boot-offline override persists a safe first-launch choice',
    () async {
      final database = AppDatabase.memory();
      final simulator = QaInternetSimulator.forTesting(bootOffline: true);
      final cloud = SupabaseCloudDataSource(
        configuration: const SupabaseConfig(
          url: 'https://qa.invalid',
          anonKey: 'qa-public-anon-key',
        ),
        internetSimulator: simulator,
      );
      final dependencies = RelioDependencies(
        database: database,
        cloudDataSource: cloud,
        internetSimulator: simulator,
        useMockTransport: true,
      );
      addTearDown(dependencies.dispose);

      await dependencies.initializeAuth();

      expect(simulator.simulatedOffline, isTrue);
      expect(
        await dependencies.repositories.settings.getBool(
          'qa_simulated_internet_offline',
          defaultValue: false,
        ),
        isTrue,
      );
      expect(cloud.cloudState, CloudState.offline);
    },
  );

  test(
    'QA offline override blocks Internet probes but preserves Nearby',
    () async {
      final simulator = QaInternetSimulator.forTesting();
      final probe = _Probe();
      final runtime = RuntimeConnectivitySnapshot(
        hasInternetRoute: true,
        internetValidated: true,
        wifiEnabled: true,
        bluetoothEnabled: true,
        nearbyPermissionsGranted: true,
        androidSdk: 35,
        permissions: const {
          'android.permission.BLUETOOTH_SCAN': true,
          'android.permission.BLUETOOTH_CONNECT': true,
          'android.permission.BLUETOOTH_ADVERTISE': true,
          'android.permission.NEARBY_WIFI_DEVICES': true,
        },
        bluetoothAvailable: true,
        wifiAvailable: true,
        locationEnabled: true,
        playServicesStatus: 'available',
      );
      final connectivity = ConnectivityStatusService(
        source: _RuntimeSource(runtime),
        probe: probe,
        internetSimulator: simulator,
      );
      addTearDown(() async {
        await connectivity.dispose();
        simulator.dispose();
      });

      await connectivity.initialize();
      expect(connectivity.status.reachability, InternetReachability.online);
      final probesBeforeOffline = probe.calls;

      simulator.setSimulatedOffline(true);
      expect(connectivity.status.reachability, InternetReachability.offline);
      expect(connectivity.status.runtime.wifiEnabled, isTrue);
      expect(connectivity.status.runtime.bluetoothEnabled, isTrue);
      expect(connectivity.status.nearbyReady, isTrue);
      await connectivity.refresh();
      expect(probe.calls, probesBeforeOffline);
    },
  );

  test(
    'Supabase adapter rejects network operations while QA offline is on',
    () async {
      final simulator = QaInternetSimulator.forTesting()
        ..setSimulatedOffline(true);
      final cloud = SupabaseCloudDataSource(
        configuration: const SupabaseConfig(
          url: 'https://qa.invalid',
          anonKey: 'qa-public-anon-key',
        ),
        internetSimulator: simulator,
      );
      addTearDown(() async {
        await cloud.dispose();
        simulator.dispose();
      });

      await expectLater(
        cloud.signIn(
          email: 'qa@example.invalid',
          password: 'not-a-real-password',
        ),
        throwsA(
          isA<CloudException>().having(
            (error) => error.code,
            'code',
            'offline',
          ),
        ),
      );
      expect(cloud.cloudState, CloudState.offline);
    },
  );
}
