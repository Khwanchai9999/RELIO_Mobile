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
      locationWhenInUse: permission.PermissionStatus.denied,
    );
    const android12 = NearbyPermissionSnapshot(
      androidSdk: 31,
      bluetoothScan: permission.PermissionStatus.granted,
      bluetoothConnect: permission.PermissionStatus.granted,
      bluetoothAdvertise: permission.PermissionStatus.granted,
      nearbyWifiDevices: permission.PermissionStatus.denied,
      locationWhenInUse: permission.PermissionStatus.denied,
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
}
