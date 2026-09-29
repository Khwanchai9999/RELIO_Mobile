import 'dart:io';

import 'package:permission_handler/permission_handler.dart' as ph;

import '../connectivity/runtime_connectivity.dart';

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

  List<ph.PermissionStatus> get requiredStatuses {
    if (!isAndroid) return const [];
    final sdk = androidSdk;
    if (sdk == null) return const [];
    if (sdk >= 33) {
      return [
        bluetoothScan,
        bluetoothConnect,
        bluetoothAdvertise,
        nearbyWifiDevices,
      ];
    }
    if (sdk >= 31) {
      return [bluetoothScan, bluetoothConnect, bluetoothAdvertise];
    }
    return [locationWhenInUse];
  }

  bool get allGranted =>
      !isAndroid ||
      (requiredStatuses.isNotEmpty &&
          requiredStatuses.every(
            (status) => status.isGranted || status.isLimited,
          ));
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
    return NearbyPermissionSnapshot(
      androidSdk: await _androidSdkReader(),
      bluetoothScan: await ph.Permission.bluetoothScan.status,
      bluetoothConnect: await ph.Permission.bluetoothConnect.status,
      bluetoothAdvertise: await ph.Permission.bluetoothAdvertise.status,
      nearbyWifiDevices: await ph.Permission.nearbyWifiDevices.status,
      locationWhenInUse: await ph.Permission.locationWhenInUse.status,
    );
  }

  Future<NearbyPermissionSnapshot> requestNearbyPermissions() async {
    if (!_isAndroid) return readNearbyPermissions();
    final sdk = await _androidSdkReader();
    final required = sdk != null && sdk >= 33
        ? [
            ph.Permission.bluetoothScan,
            ph.Permission.bluetoothConnect,
            ph.Permission.bluetoothAdvertise,
            ph.Permission.nearbyWifiDevices,
          ]
        : sdk != null && sdk >= 31
        ? [
            ph.Permission.bluetoothScan,
            ph.Permission.bluetoothConnect,
            ph.Permission.bluetoothAdvertise,
          ]
        : [ph.Permission.locationWhenInUse];
    await required.request();
    return readNearbyPermissions();
  }

  Future<bool> openAppSettings() => ph.openAppSettings();
}
