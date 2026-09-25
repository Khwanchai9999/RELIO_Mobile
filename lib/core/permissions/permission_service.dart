import 'package:permission_handler/permission_handler.dart' as ph;

class NearbyPermissionSnapshot {
  const NearbyPermissionSnapshot({
    required this.bluetoothScan,
    required this.bluetoothConnect,
    required this.bluetoothAdvertise,
    required this.nearbyWifiDevices,
    required this.locationWhenInUse,
  });

  final ph.PermissionStatus bluetoothScan;
  final ph.PermissionStatus bluetoothConnect;
  final ph.PermissionStatus bluetoothAdvertise;
  final ph.PermissionStatus nearbyWifiDevices;
  final ph.PermissionStatus locationWhenInUse;

  bool get allGranted => [
    bluetoothScan,
    bluetoothConnect,
    bluetoothAdvertise,
    nearbyWifiDevices,
    locationWhenInUse,
  ].every((status) => status.isGranted || status.isLimited);
}

class PermissionService {
  Future<NearbyPermissionSnapshot> readNearbyPermissions() async =>
      NearbyPermissionSnapshot(
        bluetoothScan: await ph.Permission.bluetoothScan.status,
        bluetoothConnect: await ph.Permission.bluetoothConnect.status,
        bluetoothAdvertise: await ph.Permission.bluetoothAdvertise.status,
        nearbyWifiDevices: await ph.Permission.nearbyWifiDevices.status,
        locationWhenInUse: await ph.Permission.locationWhenInUse.status,
      );

  Future<NearbyPermissionSnapshot> requestNearbyPermissions() async {
    await [
      ph.Permission.bluetoothScan,
      ph.Permission.bluetoothConnect,
      ph.Permission.bluetoothAdvertise,
      ph.Permission.nearbyWifiDevices,
      ph.Permission.locationWhenInUse,
    ].request();
    return readNearbyPermissions();
  }

  Future<bool> openAppSettings() => ph.openAppSettings();
}
