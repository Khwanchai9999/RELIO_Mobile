import 'dart:io';

import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:flutter/services.dart';

import '../connectivity/runtime_connectivity.dart';
import '../nearby/nearby_readiness.dart';

class NearbyPermissionSnapshot {
  const NearbyPermissionSnapshot({
    required this.androidSdk,
    required this.bluetoothScan,
    required this.bluetoothConnect,
    required this.bluetoothAdvertise,
    required this.nearbyWifiDevices,
    required this.locationWhenInUse,
    this.isAndroid = true,
  });

  final int? androidSdk;
  final ph.PermissionStatus bluetoothScan;
  final ph.PermissionStatus bluetoothConnect;
  final ph.PermissionStatus bluetoothAdvertise;
  final ph.PermissionStatus nearbyWifiDevices;
  final ph.PermissionStatus locationWhenInUse;
  final bool isAndroid;

  bool get isKnown => !isAndroid || androidSdk != null;

  List<ph.PermissionStatus> get requiredStatuses {
    if (!isAndroid) return const [];
    final sdk = androidSdk;
    if (sdk == null) return const [];
    return [
      if (NearbyPermissionPolicy(sdk).locationRequired) locationWhenInUse,
      if (sdk >= 31) ...[bluetoothScan, bluetoothConnect, bluetoothAdvertise],
      if (sdk >= 33) nearbyWifiDevices,
    ];
  }

  bool get allGranted =>
      !isAndroid ||
      (requiredStatuses.isNotEmpty &&
          requiredStatuses.every((status) => status.isGranted));
}

class PermissionService {
  PermissionService({
    Future<int?> Function()? androidSdkReader,
    bool? isAndroid,
  }) : _androidSdkReader =
           androidSdkReader ??
           (() async => (await MethodChannelRuntimeConnectivitySource().read())
               .androidSdk),
       _isAndroid = isAndroid ?? Platform.isAndroid;

  final Future<int?> Function() _androidSdkReader;
  final bool _isAndroid;
  static const _channel = MethodChannel('relio/runtime_connectivity');

  Future<NearbyPermissionSnapshot> readNearbyPermissions() async {
    if (!_isAndroid) {
      return const NearbyPermissionSnapshot(
        androidSdk: null,
        bluetoothScan: ph.PermissionStatus.granted,
        bluetoothConnect: ph.PermissionStatus.granted,
        bluetoothAdvertise: ph.PermissionStatus.granted,
        nearbyWifiDevices: ph.PermissionStatus.granted,
        locationWhenInUse: ph.PermissionStatus.granted,
        isAndroid: false,
      );
    }
    final runtime = await MethodChannelRuntimeConnectivitySource().read();
    final sdk = runtime.androidSdk ?? await _androidSdkReader();
    ph.PermissionStatus status(String name) => runtime.permissions[name] == true
        ? ph.PermissionStatus.granted
        : ph.PermissionStatus.denied;
    return NearbyPermissionSnapshot(
      androidSdk: sdk,
      bluetoothScan: status(NearbyPermissionPolicy.scan),
      bluetoothConnect: status(NearbyPermissionPolicy.connect),
      bluetoothAdvertise: status(NearbyPermissionPolicy.advertise),
      nearbyWifiDevices: status(NearbyPermissionPolicy.wifi),
      locationWhenInUse: status(
        (sdk ?? 0) <= 28
            ? NearbyPermissionPolicy.coarse
            : NearbyPermissionPolicy.fine,
      ),
    );
  }

  Future<NearbyPermissionSnapshot> requestNearbyPermissions() async {
    if (!_isAndroid) return readNearbyPermissions();
    final sdk = await _androidSdkReader();
    final required = NearbyPermissionPolicy(sdk).requestPermissions;
    if (required.isNotEmpty) {
      // ส่งชื่อสิทธิ์ตรงไปยัง Android เพื่อไม่ให้ location group ขอ FINE บน API 24–28
      await _channel.invokeMethod<void>('requestPermissions', required);
    }
    return readNearbyPermissions();
  }

  /// Requests foreground Location only after the user approves live sharing.
  Future<bool> requestLiveLocationPermission() async {
    if (!_isAndroid) return true;
    return (await ph.Permission.locationWhenInUse.request()).isGranted;
  }

  Future<void> openNearbySettings(String action) =>
      _channel.invokeMethod<void>('openNearbySettings', action);

  Future<bool> openAppSettings() => ph.openAppSettings();
}
