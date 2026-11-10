import '../domain/relio_entities.dart';

// ใช้นโยบายเดียวตรวจความสด ความแม่นยำ และช่วงเวลาของพิกัด Nearby
// ค่าที่แสดงบนแผนที่อาจยอมรับได้ แต่ไม่จำเป็นต้องผ่านเกณฑ์สำหรับส่งต่อให้ peer
enum LocationConfidence { high, limited, low }

/// One policy keeps GPS freshness and reported uncertainty consistent across
/// Nearby acquisition, packet receive, and map labels.
class NearbyLocationQuality {
  const NearbyLocationQuality._();

  static const maxShareAge = Duration(minutes: 2);
  static const maxLocalDisplayAge = Duration(minutes: 5);
  static const maxFutureSkew = Duration(seconds: 10);
  static const highConfidenceMeters = 50.0;
  static const limitedConfidenceMeters = 100.0;

  static bool isValidCoordinates(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  static LocationConfidence confidence(double? accuracyMeters) {
    if (accuracyMeters == null ||
        !accuracyMeters.isFinite ||
        accuracyMeters < 0) {
      return LocationConfidence.low;
    }
    if (accuracyMeters <= highConfidenceMeters) {
      return LocationConfidence.high;
    }
    if (accuracyMeters <= limitedConfidenceMeters) {
      return LocationConfidence.limited;
    }
    return LocationConfidence.low;
  }

  static bool hasValidCaptureTime(
    DateTime capturedAt,
    DateTime now, {
    Duration maxAge = maxShareAge,
    Duration maxFutureSkew = maxFutureSkew,
  }) {
    final age = effectiveAge(capturedAt, now, maxFutureSkew: maxFutureSkew);
    return age != null && age <= maxAge;
  }

  /// ชดเชยเฉพาะ clock skew ที่กำหนด โดยคง capture time ต้นฉบับไว้
  static Duration? effectiveAge(
    DateTime capturedAt,
    DateTime now, {
    Duration maxFutureSkew = maxFutureSkew,
  }) {
    final age = now.toUtc().difference(capturedAt.toUtc());
    if (age < -maxFutureSkew) return null;
    return age.isNegative ? Duration.zero : age;
  }

  static bool isEligibleForCurrentSharing(
    LocationData location, {
    required DateTime now,
  }) =>
      isValidCoordinates(location.latitude, location.longitude) &&
      location.accuracyMeters != null &&
      location.accuracyMeters!.isFinite &&
      location.accuracyMeters! >= 0 &&
      hasValidCaptureTime(location.capturedAt, now);

  /// อนุญาต last-known fix ที่ยังพอแสดงบนแผนที่ได้ แต่ยังไม่อนุญาตให้ส่งให้ peer
  static bool isEligibleForLocalDisplay(
    LocationData location, {
    required DateTime now,
    Duration maxAge = maxLocalDisplayAge,
  }) =>
      isValidCoordinates(location.latitude, location.longitude) &&
      (location.accuracyMeters == null ||
          (location.accuracyMeters!.isFinite &&
              location.accuracyMeters! >= 0)) &&
      hasValidCaptureTime(location.capturedAt, now, maxAge: maxAge);

  static String accuracyLabel(double? accuracyMeters) {
    if (accuracyMeters == null ||
        !accuracyMeters.isFinite ||
        accuracyMeters < 0) {
      return 'ไม่ทราบความแม่นยำ';
    }
    final meters = accuracyMeters.round();
    return switch (confidence(accuracyMeters)) {
      LocationConfidence.high => 'ความแม่นยำประมาณ ±$meters ม.',
      LocationConfidence.limited => 'ตำแหน่งโดยประมาณ ±$meters ม.',
      LocationConfidence.low => 'ตำแหน่งคลาดเคลื่อนสูง ±$meters ม.',
    };
  }
}
