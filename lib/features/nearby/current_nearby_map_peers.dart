// ตัวช่วยคัด peer ปัจจุบันที่ควรแสดงบนแผนที่ โดยอิงสถานะ Nearby ที่ใช้งานอยู่
import '../../core/domain/relio_entities.dart';
import '../../core/location/nearby_map_calculations.dart';
import '../../core/nearby/nearby_transport.dart';

/// เลือกเฉพาะอุปกรณ์ที่ยืนยัน Nearby แล้วและยังมีตำแหน่งที่ใช้วาง marker ได้
/// โดยไม่ลบตำแหน่งเก่าจาก Repository เพื่อให้ History และ Chat ใช้ต่อได้
Set<String> currentNearbyMapPeerIds({
  required Iterable<RelioNearbyDevice> savedDevices,
  required Iterable<NearbyPeer> authenticatedPeers,
  required DateTime now,
}) {
  final authenticatedIds = authenticatedPeers
      .map((peer) => peer.deviceId)
      .whereType<String>()
      .toSet();
  return savedDevices
      .where((device) => authenticatedIds.contains(device.deviceId))
      .where(
        (device) =>
            NearbyMapCalculations.isValidPoint(
              device.peerLatitude,
              device.peerLongitude,
            ) &&
            device.peerLocationCapturedAt != null &&
            NearbyMapCalculations.freshness(
                  device.peerLocationCapturedAt!,
                  now,
                ) !=
                LocationFreshness.invalid &&
            NearbyMapCalculations.freshness(
                  device.peerLocationCapturedAt!,
                  now,
                ) !=
                LocationFreshness.veryStale,
      )
      .map((device) => device.deviceId)
      .toSet();
}
