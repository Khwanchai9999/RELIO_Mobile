// ตัวช่วยหาหมุดแผนที่ที่ตรงกับตำแหน่งแตะ เพื่อรองรับการเลือกหมุดที่ซ้อนกัน
import 'dart:ui';

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Nearby Map Marker Hit
class NearbyMapMarkerHit {
  const NearbyMapMarkerHit({required this.id, required this.screenPoint});

  final String id;
  final Offset screenPoint;
}

const nearbyMapMarkerHitRadius = 32.0;

List<String> nearbyMapMarkerIdsAtPoint(
  Iterable<NearbyMapMarkerHit> markers,
  String tappedMarkerId, {
  double hitRadius = nearbyMapMarkerHitRadius,
}) {
  final candidates = markers.toList(growable: false);
  final tapped = candidates.where((marker) => marker.id == tappedMarkerId);
  if (tapped.isEmpty) return const [];
  final anchor = tapped.first.screenPoint;
  return candidates
      .where((marker) => (marker.screenPoint - anchor).distance <= hitRadius)
      .map((marker) => marker.id)
      .toList(growable: false);
}
