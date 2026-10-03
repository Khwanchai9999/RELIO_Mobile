import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart' as permission;
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/connectivity/runtime_connectivity.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/permissions/permission_service.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';

class _FakeRuntimeSource implements RuntimeConnectivitySource {
  _FakeRuntimeSource(this.current);

  RuntimeConnectivitySnapshot current;
  final _controller = StreamController<RuntimeConnectivitySnapshot>.broadcast();

  @override
  Future<RuntimeConnectivitySnapshot> read() async => current;

  @override
  Stream<RuntimeConnectivitySnapshot> get changes => _controller.stream;

  void emit(RuntimeConnectivitySnapshot value) {
    current = value;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();
}

class _FakeProbe implements InternetReachabilityProbe {
  _FakeProbe(this.reachableCount);

  int reachableCount;
  int calls = 0;

  @override
  Future<int> reachableEndpointCount() async {
    calls++;
    return reachableCount;
  }
}

void main() {
  test('platform snapshot keeps Wi-Fi radio distinct from Internet route', () {
    final snapshot = RuntimeConnectivitySnapshot.fromPlatform({
      'hasInternetRoute': false,
      'internetValidated': false,
      'wifiEnabled': true,
      'bluetoothEnabled': true,
      'nearbyPermissionsGranted': true,
      'androidSdk': 35,
      'permissions': {
        'android.permission.BLUETOOTH_SCAN': true,
        'android.permission.BLUETOOTH_CONNECT': true,
        'android.permission.BLUETOOTH_ADVERTISE': true,
        'android.permission.NEARBY_WIFI_DEVICES': true,
      },
    });

    expect(snapshot.hasInternetRoute, isFalse);
    expect(snapshot.wifiEnabled, isTrue);
    expect(snapshot.internetValidated, isFalse);
    expect(snapshot.nearbyPermissionsGranted, isTrue);
  });

  test('no Internet route is offline even when Wi-Fi radio is on', () async {
    final source = _FakeRuntimeSource(
      const RuntimeConnectivitySnapshot(
        hasInternetRoute: false,
        wifiEnabled: true,
        bluetoothEnabled: true,
        nearbyPermissionsGranted: true,
        androidSdk: 35,
        permissions: {
          'android.permission.BLUETOOTH_SCAN': true,
          'android.permission.BLUETOOTH_CONNECT': true,
          'android.permission.BLUETOOTH_ADVERTISE': true,
          'android.permission.NEARBY_WIFI_DEVICES': true,
        },
      ),
    );
    final probe = _FakeProbe(0);
    final service = ConnectivityStatusService(source: source, probe: probe);
    addTearDown(() async {
      await service.dispose();
      await source.close();
    });

    final status = await service.initialize();
    expect(status.reachability, InternetReachability.offline);
    expect(status.runtime.wifiEnabled, isTrue);
    expect(status.nearbyReady, isTrue);
    expect(probe.calls, 0);
  });

  test('one reachable HTTPS probe prevents a false offline result', () async {
    final source = _FakeRuntimeSource(
      const RuntimeConnectivitySnapshot(
        hasInternetRoute: true,
        internetValidated: true,
        bluetoothEnabled: false,
        nearbyPermissionsGranted: true,
      ),
    );
    final probe = _FakeProbe(1);
    final service = ConnectivityStatusService(source: source, probe: probe);
    addTearDown(() async {
      await service.dispose();
      await source.close();
    });

    final status = await service.initialize();
    expect(status.reachability, InternetReachability.online);
    expect(status.nearbyReady, isFalse);
  });

  test('Internet route without reachable HTTPS probes is limited', () async {
    final source = _FakeRuntimeSource(
      const RuntimeConnectivitySnapshot(hasInternetRoute: true),
    );
    final service = ConnectivityStatusService(
      source: source,
      probe: _FakeProbe(0),
    );
    addTearDown(() async {
      await service.dispose();
      await source.close();
    });

    expect(
      (await service.initialize()).reachability,
      InternetReachability.limited,
    );
  });

  test(
    'reachability probes respect cooldown and radio changes remain live',
    () async {
      var now = DateTime.utc(2026, 9, 30);
      final source = _FakeRuntimeSource(
        const RuntimeConnectivitySnapshot(
          hasInternetRoute: true,
          internetValidated: true,
          wifiEnabled: true,
          bluetoothEnabled: true,
          nearbyPermissionsGranted: true,
          androidSdk: 35,
          permissions: {
            'android.permission.BLUETOOTH_SCAN': true,
            'android.permission.BLUETOOTH_CONNECT': true,
            'android.permission.BLUETOOTH_ADVERTISE': true,
            'android.permission.NEARBY_WIFI_DEVICES': true,
          },
        ),
      );
      final probe = _FakeProbe(2);
      final service = ConnectivityStatusService(
        source: source,
        probe: probe,
        clock: () => now,
        probeCooldown: const Duration(seconds: 20),
      );
      addTearDown(() async {
        await service.dispose();
        await source.close();
      });

      await service.initialize();
      expect(probe.calls, 1);
      await service.refresh();
      expect(probe.calls, 1);

      source.emit(
        const RuntimeConnectivitySnapshot(
          hasInternetRoute: true,
          wifiEnabled: false,
          bluetoothEnabled: true,
          nearbyPermissionsGranted: true,
          androidSdk: 35,
          permissions: {
            'android.permission.BLUETOOTH_SCAN': true,
            'android.permission.BLUETOOTH_CONNECT': true,
            'android.permission.BLUETOOTH_ADVERTISE': true,
            'android.permission.NEARBY_WIFI_DEVICES': true,
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(service.status.runtime.wifiEnabled, isFalse);
      expect(service.status.nearbyReady, isTrue);

      now = now.add(const Duration(seconds: 21));
      await service.refresh();
      expect(probe.calls, 2);
    },
  );

  test('Nearby permissions are version-aware', () {
    const android13 = NearbyPermissionSnapshot(
      androidSdk: 33,
      bluetoothScan: permission.PermissionStatus.granted,
      bluetoothConnect: permission.PermissionStatus.granted,
      bluetoothAdvertise: permission.PermissionStatus.granted,
      nearbyWifiDevices: permission.PermissionStatus.granted,
      locationWhenInUse: permission.PermissionStatus.granted,
    );
    const android12 = NearbyPermissionSnapshot(
      androidSdk: 31,
      bluetoothScan: permission.PermissionStatus.granted,
      bluetoothConnect: permission.PermissionStatus.granted,
      bluetoothAdvertise: permission.PermissionStatus.granted,
      nearbyWifiDevices: permission.PermissionStatus.denied,
      locationWhenInUse: permission.PermissionStatus.granted,
    );
    const android11 = NearbyPermissionSnapshot(
      androidSdk: 30,
      bluetoothScan: permission.PermissionStatus.denied,
      bluetoothConnect: permission.PermissionStatus.denied,
      bluetoothAdvertise: permission.PermissionStatus.denied,
      nearbyWifiDevices: permission.PermissionStatus.denied,
      locationWhenInUse: permission.PermissionStatus.granted,
    );

    expect(android13.allGranted, isTrue);
    expect(android12.allGranted, isTrue);
    expect(android11.allGranted, isTrue);
  });

  test('API 29 Nearby readiness requires the system Location toggle', () {
    const base = RuntimeConnectivitySnapshot(
      bluetoothEnabled: true,
      nearbyPermissionsGranted: true,
      androidSdk: 29,
    );
    expect(InternetStatus(runtime: base).nearbyReady, isFalse);
    expect(
      InternetStatus(
        runtime: const RuntimeConnectivitySnapshot(
          bluetoothEnabled: true,
          nearbyPermissionsGranted: true,
          locationEnabled: true,
          androidSdk: 29,
        ),
      ).nearbyReady,
      isTrue,
    );
  });

  test(
    'API 29 Location toggle starts and stops real Nearby automatically',
    () async {
      const locationOff = RuntimeConnectivitySnapshot(
        hasInternetRoute: false,
        bluetoothEnabled: true,
        nearbyPermissionsGranted: true,
        locationEnabled: false,
        androidSdk: 29,
      );
      final source = _FakeRuntimeSource(locationOff);
      final transport = MockNearbyTransport();
      final connectivity = ConnectivityStatusService(
        source: source,
        probe: _FakeProbe(0),
      );
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: transport,
        useMockTransport: false,
        androidPlatformOverride: true,
        permissionService: PermissionService(isAndroid: false),
        connectivityStatusService: connectivity,
      );
      addTearDown(() async {
        await dependencies.dispose();
        await source.close();
      });

      await dependencies.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(transport.isAdvertising, isFalse);
      expect(transport.isDiscovering, isFalse);

      source.emit(
        const RuntimeConnectivitySnapshot(
          hasInternetRoute: false,
          bluetoothEnabled: true,
          nearbyPermissionsGranted: true,
          locationEnabled: true,
          androidSdk: 29,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(transport.isAdvertising, isTrue);
      expect(transport.isDiscovering, isTrue);

      source.emit(locationOff);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(transport.isAdvertising, isFalse);
      expect(transport.isDiscovering, isFalse);
    },
  );

  test(
    'API 35 starts with GPS off and serializes foreground recovery',
    () async {
      const ready = RuntimeConnectivitySnapshot(
        hasInternetRoute: false,
        androidSdk: 35,
        bluetoothAvailable: true,
        bluetoothEnabled: true,
        wifiAvailable: true,
        wifiEnabled: true,
        locationEnabled: false,
        playServicesStatus: 'available',
        permissions: {
          'android.permission.BLUETOOTH_SCAN': true,
          'android.permission.BLUETOOTH_CONNECT': true,
          'android.permission.BLUETOOTH_ADVERTISE': true,
          'android.permission.NEARBY_WIFI_DEVICES': true,
        },
      );
      final source = _FakeRuntimeSource(ready);
      final transport = MockNearbyTransport();
      final connectivity = ConnectivityStatusService(
        source: source,
        probe: _FakeProbe(0),
      );
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: transport,
        useMockTransport: false,
        androidPlatformOverride: true,
        permissionService: PermissionService(isAndroid: false),
        connectivityStatusService: connectivity,
      );
      addTearDown(() async {
        await dependencies.dispose();
        await source.close();
      });

      await dependencies.initialize();
      expect(transport.isAdvertising, isTrue);
      expect(transport.isDiscovering, isTrue);
      expect(dependencies.connectivityStatus.status.nearbyReady, isTrue);

      await dependencies.setNearbyForeground(false);
      expect(transport.isAdvertising, isFalse);
      expect(transport.isDiscovering, isFalse);
      await dependencies.setNearbyForeground(true);
      expect(transport.isAdvertising, isTrue);
      expect(transport.isDiscovering, isTrue);

      source.emit(
        const RuntimeConnectivitySnapshot(
          hasInternetRoute: false,
          androidSdk: 35,
          bluetoothAvailable: true,
          bluetoothEnabled: false,
          wifiAvailable: true,
          wifiEnabled: true,
          locationEnabled: false,
          playServicesStatus: 'available',
          permissions: {
            'android.permission.BLUETOOTH_SCAN': true,
            'android.permission.BLUETOOTH_CONNECT': true,
            'android.permission.BLUETOOTH_ADVERTISE': true,
            'android.permission.NEARBY_WIFI_DEVICES': true,
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(transport.isAdvertising, isFalse);
      expect(transport.isDiscovering, isFalse);
    },
  );

  test(
    'concurrent Nearby screen and resume triggers share one start',
    () async {
      const ready = RuntimeConnectivitySnapshot(
        hasInternetRoute: false,
        androidSdk: 35,
        bluetoothAvailable: true,
        bluetoothEnabled: true,
        wifiAvailable: true,
        wifiEnabled: true,
        locationEnabled: false,
        playServicesStatus: 'available',
        permissions: {
          'android.permission.BLUETOOTH_SCAN': true,
          'android.permission.BLUETOOTH_CONNECT': true,
          'android.permission.BLUETOOTH_ADVERTISE': true,
          'android.permission.NEARBY_WIFI_DEVICES': true,
          'android.permission.ACCESS_WIFI_STATE': true,
          'android.permission.CHANGE_WIFI_STATE': true,
        },
      );
      final source = _FakeRuntimeSource(ready);
      final transport = MockNearbyTransport()
        ..startDelay = const Duration(milliseconds: 40);
      final connectivity = ConnectivityStatusService(
        source: source,
        probe: _FakeProbe(0),
      );
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: transport,
        useMockTransport: false,
        androidPlatformOverride: true,
        permissionService: PermissionService(isAndroid: false),
        connectivityStatusService: connectivity,
      );
      addTearDown(() async {
        await dependencies.dispose();
        await source.close();
      });

      final initializing = dependencies.initialize();
      while (transport.advertisingStartCount == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await Future.wait([
        dependencies.startNearbySessionIfPermitted(),
        dependencies.startNearbySessionIfPermitted(force: true),
        dependencies.setNearbyForeground(true),
      ]);
      await initializing;

      expect(transport.advertisingStartCount, 1);
      expect(transport.discoveryStartCount, 1);
    },
  );

  test(
    'brief inactive/resume keeps an in-flight native attempt alive',
    () async {
      const ready = RuntimeConnectivitySnapshot(
        hasInternetRoute: false,
        androidSdk: 35,
        bluetoothAvailable: true,
        bluetoothEnabled: true,
        wifiAvailable: true,
        wifiEnabled: true,
        playServicesStatus: 'available',
        permissions: {
          'android.permission.BLUETOOTH_SCAN': true,
          'android.permission.BLUETOOTH_CONNECT': true,
          'android.permission.BLUETOOTH_ADVERTISE': true,
          'android.permission.NEARBY_WIFI_DEVICES': true,
          'android.permission.ACCESS_WIFI_STATE': true,
          'android.permission.CHANGE_WIFI_STATE': true,
        },
      );
      final source = _FakeRuntimeSource(ready);
      final transport = MockNearbyTransport()..holdConnectionRequests = true;
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: transport,
        useMockTransport: false,
        androidPlatformOverride: true,
        permissionService: PermissionService(isAndroid: false),
        connectivityStatusService: ConnectivityStatusService(
          source: source,
          probe: _FakeProbe(0),
        ),
        connectionAttemptTimeout: const Duration(milliseconds: 400),
      );
      addTearDown(() async {
        await dependencies.dispose();
        await source.close();
      });

      await dependencies.initialize();
      transport.simulatePeer(id: 'active-negotiation', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      await dependencies.nearbyService.connect('active-negotiation');
      expect(dependencies.nearbyService.hasActiveConnectionAttempts, isTrue);

      await dependencies.setNearbyForeground(false);
      expect(transport.isAdvertising, isTrue);
      expect(transport.isDiscovering, isTrue);
      await dependencies.setNearbyForeground(true);
      await dependencies.startNearbySessionIfPermitted(force: true);
      expect(transport.isAdvertising, isTrue);
      expect(transport.isDiscovering, isTrue);
      expect(transport.resetSessionOperationsCount, 0);
      expect(transport.advertisingStartCount, 1);
      expect(transport.discoveryStartCount, 1);

      transport.resolveConnectionRequest('active-negotiation', connected: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        dependencies.nearbyService.peerStates['active-negotiation'],
        NearbyConnectionState.connected,
      );
    },
  );

  test(
    'readiness refresh defers radio restart during native negotiation',
    () async {
      const ready = RuntimeConnectivitySnapshot(
        hasInternetRoute: false,
        androidSdk: 35,
        bluetoothAvailable: true,
        bluetoothEnabled: true,
        wifiAvailable: true,
        wifiEnabled: true,
        playServicesStatus: 'available',
        permissions: {
          'android.permission.BLUETOOTH_SCAN': true,
          'android.permission.BLUETOOTH_CONNECT': true,
          'android.permission.BLUETOOTH_ADVERTISE': true,
          'android.permission.NEARBY_WIFI_DEVICES': true,
          'android.permission.ACCESS_WIFI_STATE': true,
          'android.permission.CHANGE_WIFI_STATE': true,
        },
      );
      final source = _FakeRuntimeSource(ready);
      final transport = MockNearbyTransport()..holdConnectionRequests = true;
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: transport,
        useMockTransport: false,
        androidPlatformOverride: true,
        permissionService: PermissionService(isAndroid: false),
        connectivityStatusService: ConnectivityStatusService(
          source: source,
          probe: _FakeProbe(0),
        ),
        connectionAttemptTimeout: const Duration(milliseconds: 400),
      );
      addTearDown(() async {
        await dependencies.dispose();
        await source.close();
      });

      await dependencies.initialize();
      transport.simulatePeer(id: 'readiness-refresh-active', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      await dependencies.nearbyService.connect('readiness-refresh-active');

      source.emit(
        const RuntimeConnectivitySnapshot(
          hasInternetRoute: false,
          androidSdk: 35,
          bluetoothAvailable: true,
          bluetoothEnabled: false,
          wifiAvailable: true,
          wifiEnabled: true,
          playServicesStatus: 'available',
          permissions: {
            'android.permission.BLUETOOTH_SCAN': true,
            'android.permission.BLUETOOTH_CONNECT': true,
            'android.permission.BLUETOOTH_ADVERTISE': true,
            'android.permission.NEARBY_WIFI_DEVICES': true,
            'android.permission.ACCESS_WIFI_STATE': true,
            'android.permission.CHANGE_WIFI_STATE': true,
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(dependencies.nearbyService.hasActiveConnectionAttempts, isTrue);
      expect(transport.isAdvertising, isTrue);
      expect(transport.isDiscovering, isTrue);
      expect(transport.resetSessionOperationsCount, 0);
      expect(transport.advertisingStartCount, 1);
      expect(transport.discoveryStartCount, 1);

      transport.resolveConnectionRequest(
        'readiness-refresh-active',
        connected: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        dependencies.nearbyService.peerStates['readiness-refresh-active'],
        NearbyConnectionState.connected,
      );
    },
  );

  test(
    'long pause expires an unresolved attempt and stops the session',
    () async {
      const ready = RuntimeConnectivitySnapshot(
        hasInternetRoute: false,
        androidSdk: 29,
        bluetoothAvailable: true,
        bluetoothEnabled: true,
        wifiAvailable: true,
        wifiEnabled: true,
        locationEnabled: true,
        playServicesStatus: 'available',
        permissions: {
          'android.permission.ACCESS_COARSE_LOCATION': true,
          'android.permission.ACCESS_FINE_LOCATION': true,
        },
      );
      final source = _FakeRuntimeSource(ready);
      final transport = MockNearbyTransport()..holdConnectionRequests = true;
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: transport,
        useMockTransport: false,
        androidPlatformOverride: true,
        permissionService: PermissionService(isAndroid: false),
        connectivityStatusService: ConnectivityStatusService(
          source: source,
          probe: _FakeProbe(0),
        ),
        connectionAttemptTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(() async {
        await dependencies.dispose();
        await source.close();
      });

      await dependencies.initialize();
      transport.simulatePeer(id: 'paused-negotiation', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      await dependencies.nearbyService.connect('paused-negotiation');
      await dependencies.setNearbyForeground(false);
      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(
        dependencies.nearbyService.peerStates['paused-negotiation'],
        NearbyConnectionState.failed,
      );
      expect(transport.isAdvertising, isFalse);
      expect(transport.isDiscovering, isFalse);
      expect(transport.resetSessionOperationsCount, 0);
    },
  );

  test(
    'automatic readiness events respect retry backoff after native failure',
    () async {
      const ready = RuntimeConnectivitySnapshot(
        hasInternetRoute: false,
        androidSdk: 35,
        bluetoothAvailable: true,
        bluetoothEnabled: true,
        wifiAvailable: true,
        wifiEnabled: true,
        locationEnabled: false,
        playServicesStatus: 'available',
        permissions: {
          'android.permission.BLUETOOTH_SCAN': true,
          'android.permission.BLUETOOTH_CONNECT': true,
          'android.permission.BLUETOOTH_ADVERTISE': true,
          'android.permission.NEARBY_WIFI_DEVICES': true,
          'android.permission.ACCESS_WIFI_STATE': true,
          'android.permission.CHANGE_WIFI_STATE': true,
        },
      );
      final source = _FakeRuntimeSource(ready);
      final transport = MockNearbyTransport()
        ..advertisingStartFailure = const NearbyTransportException(
          'Nearby radio failure',
          code: 'STATUS_RADIO_ERROR',
          apiStatusCode: 8007,
          apiStatusName: 'STATUS_RADIO_ERROR',
        );
      final connectivity = ConnectivityStatusService(
        source: source,
        probe: _FakeProbe(0),
      );
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: transport,
        useMockTransport: false,
        androidPlatformOverride: true,
        permissionService: PermissionService(isAndroid: false),
        connectivityStatusService: connectivity,
      );
      addTearDown(() async {
        await dependencies.dispose();
        await source.close();
      });

      await dependencies.initialize();
      source.emit(ready);
      source.emit(ready);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(transport.advertisingStartCount, 1);
      expect(dependencies.nearbyRetryAttempt, 1);
    },
  );
}
