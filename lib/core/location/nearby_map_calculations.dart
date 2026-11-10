import 'dart:math' as math;

import 'nearby_location_quality.dart';

// ฟังก์ชันคำนวณสำหรับแผนที่ เช่น ความสด ระยะทาง และ heading โดยไม่แตะ GPS หรือ transport
enum LocationFreshness { fresh, stale, veryStale, invalid }

enum NearbyHeadingConfidence { reliable, provisional }

class NearbyMapCalculations {
  const NearbyMapCalculations._();

  static const freshFor = Duration(minutes: 2);
  static const staleFor = Duration(minutes: 10);

  static bool isValidPoint(double? latitude, double? longitude) =>
      NearbyLocationQuality.isValidCoordinates(latitude, longitude);

  static double? validCompassHeading(
    double? degrees, {
    required double? accuracyDegrees,
  }) {
    if (degrees == null ||
        !degrees.isFinite ||
        degrees < 0 ||
        degrees > 360 ||
        (accuracyDegrees != null &&
            (!accuracyDegrees.isFinite ||
                accuracyDegrees < 0 ||
                accuracyDegrees > 45))) {
      return null;
    }
    return degrees == 360 ? 0 : degrees;
  }

  static bool isFreshLocation(DateTime? capturedAt, DateTime now) =>
      capturedAt != null &&
      freshness(capturedAt, now) == LocationFreshness.fresh;

  static LocationFreshness freshness(DateTime capturedAt, DateTime now) {
    final age = NearbyLocationQuality.effectiveAge(capturedAt, now);
    if (age == null) return LocationFreshness.invalid;
    if (age <= freshFor) return LocationFreshness.fresh;
    if (age <= staleFor) return LocationFreshness.stale;
    return LocationFreshness.veryStale;
  }

  static String freshnessLabel(DateTime? capturedAt, DateTime now) {
    if (capturedAt == null) return 'ยังไม่มีตำแหน่ง';
    final age = NearbyLocationQuality.effectiveAge(capturedAt, now);
    if (age == null) return 'เวลา GPS ไม่ถูกต้อง';
    if (age <= const Duration(seconds: 30)) {
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
      LocationFreshness.invalid => 'เวลา GPS ไม่ถูกต้อง',
    };
  }

  static String sharedLocationLabel(DateTime? capturedAt, DateTime now) {
    if (capturedAt == null) return 'ยังไม่มีตำแหน่งที่แชร์';
    final age = now.difference(capturedAt.toLocal());
    if (age.isNegative) return 'เวลาแชร์ไม่ถูกต้อง';
    if (age.inMinutes < 1) return 'แชร์ล่าสุดเมื่อครู่';
    if (age.inHours < 1) return 'แชร์ล่าสุด ${age.inMinutes} นาทีที่แล้ว';
    if (age.inDays < 1) return 'แชร์ล่าสุด ${age.inHours} ชั่วโมงที่แล้ว';
    return 'แชร์ล่าสุด ${age.inDays} วันที่แล้ว';
  }

  static String? staleMarkerLabel(
    DateTime? capturedAt,
    DateTime now, {
    double? accuracyMeters,
  }) {
    if (capturedAt == null) return '⚠ ยังไม่มีตำแหน่ง';
    if (freshness(capturedAt, now) == LocationFreshness.fresh) {
      return null;
    }
    if (accuracyMeters != null &&
        NearbyLocationQuality.confidence(accuracyMeters) ==
            LocationConfidence.low) {
      return '${NearbyLocationQuality.accuracyLabel(accuracyMeters)} • ${freshnessLabel(capturedAt, now)}';
    }
    return freshnessLabel(capturedAt, now);
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

/// ลดการแกว่งของเข็มทิศและคง heading ล่าสุดไว้เพียงช่วงสั้น ๆ/// Smooths compass jitter and holds the last good heading only briefly.
class NearbyHeadingFilter {
  static const staleAfter = Duration(seconds: 3);
  static const _smoothing = 0.25;

  double? _heading;
  DateTime? _lastReliableAt;
  NearbyHeadingConfidence _confidence = NearbyHeadingConfidence.provisional;

  NearbyHeadingConfidence get confidence => _confidence;

  double? update(
    double? degrees, {
    required double? accuracyDegrees,
    required DateTime now,
  }) {
    expire(now);
    final valid = NearbyMapCalculations.validCompassHeading(
      degrees,
      accuracyDegrees: accuracyDegrees,
    );
    if (valid == null) return expire(now);

    _confidence = accuracyDegrees == null
        ? NearbyHeadingConfidence.provisional
        : NearbyHeadingConfidence.reliable;

    final previous = _heading;
    if (previous == null || _lastReliableAt == null) {
      _heading = valid;
    } else {
      final delta = ((valid - previous + 540) % 360) - 180;
      _heading = (previous + delta * _smoothing + 360) % 360;
    }
    _lastReliableAt = now;
    return _heading;
  }

  double? expire(DateTime now) {
    final last = _lastReliableAt;
    if (last == null || now.difference(last) >= staleAfter) {
      _heading = null;
      _confidence = NearbyHeadingConfidence.provisional;
    }
    return _heading;
  }

  void clear() {
    _heading = null;
    _lastReliableAt = null;
    _confidence = NearbyHeadingConfidence.provisional;
  }
}
