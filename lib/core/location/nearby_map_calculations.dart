import 'dart:math' as math;

enum LocationFreshness { fresh, stale, veryStale }

class NearbyMapCalculations {
  const NearbyMapCalculations._();

  static const freshFor = Duration(minutes: 2);
  static const staleFor = Duration(minutes: 10);

  static bool isValidPoint(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  static LocationFreshness freshness(DateTime capturedAt, DateTime now) {
    final age = now.difference(capturedAt.toLocal());
    if (age <= freshFor) return LocationFreshness.fresh;
    if (age <= staleFor) return LocationFreshness.stale;
    return LocationFreshness.veryStale;
  }

  static String freshnessLabel(DateTime? capturedAt, DateTime now) {
    if (capturedAt == null) return 'ยังไม่มีตำแหน่ง';
    final age = now.difference(capturedAt.toLocal());
    if (age.isNegative || age <= const Duration(seconds: 30)) {
      return 'อัปเดตเมื่อครู่';
    }
    final label = age.inMinutes < 1
        ? '${age.inSeconds} วินาทีที่แล้ว'
        : age.inHours < 1
        ? '${age.inMinutes} นาทีที่แล้ว'
        : '${age.inHours} ชั่วโมงที่แล้ว';
    return switch (freshness(capturedAt, now)) {
      LocationFreshness.fresh => 'อัปเดต $label',
      LocationFreshness.stale => '⚠ อัปเดต $label',
      LocationFreshness.veryStale => '⚠ ตำแหน่งอาจไม่ใช่ตำแหน่งปัจจุบัน',
    };
  }

  static double? distanceMeters({
    required double? fromLatitude,
    required double? fromLongitude,
    required double? toLatitude,
    required double? toLongitude,
  }) {
    if (!isValidPoint(fromLatitude, fromLongitude) ||
        !isValidPoint(toLatitude, toLongitude)) {
      return null;
    }
    const earthRadius = 6371000.0;
    final lat1 = _radians(fromLatitude!);
    final lat2 = _radians(toLatitude!);
    final deltaLat = _radians(toLatitude - fromLatitude);
    final deltaLon = _radians(toLongitude! - fromLongitude!);
    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static String distanceLabel(double? meters) {
    if (meters == null || !meters.isFinite || meters < 0) return 'ไม่ทราบระยะ';
    if (meters < 1000) return '${meters.round()} เมตร';
    return '${(meters / 1000).toStringAsFixed(1)} กม.';
  }

  static double? bearingDegrees({
    required double? fromLatitude,
    required double? fromLongitude,
    required double? toLatitude,
    required double? toLongitude,
  }) {
    if (!isValidPoint(fromLatitude, fromLongitude) ||
        !isValidPoint(toLatitude, toLongitude)) {
      return null;
    }
    final lat1 = _radians(fromLatitude!);
    final lat2 = _radians(toLatitude!);
    final deltaLon = _radians(toLongitude! - fromLongitude!);
    final y = math.sin(deltaLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  static String bearingLabel(double? degrees) {
    if (degrees == null || !degrees.isFinite) return 'ไม่ทราบทิศทาง';
    const directions = [
      'เหนือ',
      'ตะวันออกเฉียงเหนือ',
      'ตะวันออก',
      'ตะวันออกเฉียงใต้',
      'ใต้',
      'ตะวันตกเฉียงใต้',
      'ตะวันตก',
      'ตะวันตกเฉียงเหนือ',
    ];
    final index = ((degrees % 360) / 45).round() % directions.length;
    return 'ประมาณ ${directions[index]}';
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
