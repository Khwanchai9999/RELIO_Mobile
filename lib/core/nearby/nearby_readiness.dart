// รวมเงื่อนไข permission และความพร้อมก่อนเริ่ม Nearby radio
// การตรวจ readiness ไม่ได้เริ่ม discovery หรือเปิด permission เอง
enum NearbyBlocker {
  platformUnsupported,
  permissionMissing,
  bluetoothUnavailable,
  bluetoothOff,
  locationRequiredButOff,
  playServicesUnavailable,
  transportUnavailable,
  localNetworkUpgradeRequired,
  transportPermissionMissing,
}

/// นโยบายเดียวสำหรับ Nearby; สิทธิ์พิกัด SOS อยู่ใน LocationService แยกต่างหาก
class NearbyPermissionPolicy {
  const NearbyPermissionPolicy(this.sdkInt, {this.targetSdk = 36});

  final int? sdkInt;
  final int targetSdk;
  static const coarse = 'android.permission.ACCESS_COARSE_LOCATION';
  static const fine = 'android.permission.ACCESS_FINE_LOCATION';
  static const scan = 'android.permission.BLUETOOTH_SCAN';
  static const connect = 'android.permission.BLUETOOTH_CONNECT';
  static const advertise = 'android.permission.BLUETOOTH_ADVERTISE';
  static const wifi = 'android.permission.NEARBY_WIFI_DEVICES';
  static const localNetwork = 'android.permission.ACCESS_LOCAL_NETWORK';
  static const accessWifiState = 'android.permission.ACCESS_WIFI_STATE';
  static const changeWifiState = 'android.permission.CHANGE_WIFI_STATE';

  bool get supported => sdkInt != null && sdkInt! >= 24;
  bool get locationRequired => supported && sdkInt! <= 31;
  bool get localNetworkRequired => (sdkInt ?? 0) >= 37 && targetSdk >= 37;

  String get tier => switch (sdkInt) {
    null => 'unknown',
    < 24 => 'unsupported',
    <= 28 => 'legacy-coarse',
    <= 30 => 'legacy-fine',
    31 => 'android12-bluetooth-location',
    32 => 'android12L-nearby-wifi',
    <= 36 => 'modern-nearby',
    _ => 'future-local-network',
  };

  List<String> get requiredPermissions {
    if (!supported) return const [];
    return [
      if (sdkInt! <= 28) coarse,
      if (sdkInt! >= 29 && sdkInt! <= 31) fine,
      if (sdkInt! >= 31) ...[scan, connect, advertise],
      if (sdkInt! >= 33) wifi,
      if (localNetworkRequired) localNetwork,
    ];
  }

  List<String> get requestPermissions => [
    // Android 12 ต้องส่ง COARSE คู่กับ FINE จึงขอ precise location ได้
    if (sdkInt == 31) coarse,
    ...requiredPermissions.where((name) => name != localNetwork),
  ];
}

class NearbyReadiness {
  const NearbyReadiness({
    required this.policy,
    this.permissions = const {},
    this.legacyPermissionsGranted,
    this.bluetoothAvailable,
    this.bluetoothEnabled,
    this.wifiAvailable,
    this.wifiEnabled,
    this.locationEnabled,
    this.playServicesStatus = 'unknown',
    this.transportAvailable = true,
  });

  final NearbyPermissionPolicy policy;
  final Map<String, bool> permissions;
  // รองรับ snapshot เก่าใน tests; native รุ่นใหม่ส่งแต่สิทธิ์จริง ไม่คำนวณ readiness ซ้ำ
  final bool? legacyPermissionsGranted;
  final bool? bluetoothAvailable;
  final bool? bluetoothEnabled;
  final bool? wifiAvailable;
  final bool? wifiEnabled;
  final bool? locationEnabled;
  final String playServicesStatus;
  final bool transportAvailable;

  List<String> get missingPermissions => policy.requiredPermissions
      .where(
        (name) =>
            permissions[name] != true &&
            !(permissions.isEmpty && legacyPermissionsGranted == true),
      )
      .toList(growable: false);

  // สิทธิ์ Wi-Fi เป็น normal permission จาก manifest ไม่ใช่ runtime prompt
  List<String> get missingManifestPermissions => [
    for (final name in const [
      NearbyPermissionPolicy.accessWifiState,
      NearbyPermissionPolicy.changeWifiState,
    ])
      if (policy.supported &&
          permissions.containsKey(name) &&
          permissions[name] != true)
        name,
  ];

  List<NearbyBlocker> get blockers => [
    if (!policy.supported) NearbyBlocker.platformUnsupported,
    if (!transportAvailable) NearbyBlocker.transportUnavailable,
    if (playServicesStatus != 'available' && playServicesStatus != 'unknown')
      NearbyBlocker.playServicesUnavailable,
    if (policy.localNetworkRequired) NearbyBlocker.localNetworkUpgradeRequired,
    if (missingManifestPermissions.isNotEmpty)
      NearbyBlocker.transportPermissionMissing,
    if (missingPermissions.isNotEmpty) NearbyBlocker.permissionMissing,
    if (bluetoothAvailable == false) NearbyBlocker.bluetoothUnavailable,
    if (bluetoothEnabled == false) NearbyBlocker.bluetoothOff,
    if (policy.locationRequired && locationEnabled != true)
      NearbyBlocker.locationRequiredButOff,
  ];

  bool get ready => blockers.isEmpty;
  bool get advertisingAllowed => ready;
  bool get discoveryAllowed => ready;
  // P2P_CLUSTER ใช้ Bluetooth ได้เมื่อ Wi-Fi ปิด จึงแสดงข้อจำกัดแทนการปิด Chat
  bool get wifiDegraded => wifiAvailable == false || wifiEnabled == false;

  String get summary => blockers.isEmpty
      ? 'พร้อมค้นหาอุปกรณ์ใกล้เคียง'
      : switch (blockers.first) {
          NearbyBlocker.platformUnsupported =>
            'ไม่สามารถตรวจสอบ Android ที่รองรับ Nearby ได้',
          NearbyBlocker.permissionMissing =>
            'กรุณาอนุญาตสิทธิ์เพื่อค้นหาอุปกรณ์ใกล้เคียง',
          NearbyBlocker.bluetoothUnavailable =>
            'อุปกรณ์นี้ไม่มี Bluetooth ที่รองรับ',
          NearbyBlocker.bluetoothOff =>
            'เปิด Bluetooth เพื่อค้นหาอุปกรณ์ใกล้เคียง',
          NearbyBlocker.locationRequiredButOff =>
            'เปิดตำแหน่งเพื่อค้นหาอุปกรณ์ใกล้เคียง',
          NearbyBlocker.playServicesUnavailable =>
            'อุปกรณ์นี้ยังไม่พร้อมใช้งาน Nearby Connections: ตรวจสอบ Google Play Services',
          NearbyBlocker.transportUnavailable =>
            'ไม่สามารถเริ่มระบบ Nearby ได้ กรุณาลองอีกครั้ง',
          NearbyBlocker.localNetworkUpgradeRequired =>
            'ต้องอัปเดต RELIO เพื่อรองรับสิทธิ์เครือข่ายของ Android รุ่นนี้',
          NearbyBlocker.transportPermissionMissing =>
            'RELIO ขาดสิทธิ์ระบบสำหรับ Nearby; โปรดติดตั้งแอปเวอร์ชันล่าสุด',
        };
}
