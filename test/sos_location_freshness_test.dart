import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/sos/sos_location_freshness.dart';

void main() {
  final now = DateTime(2026, 10, 30, 12);

  RelioSosEvent event({
    double? latitude = 13.75,
    double? longitude = 100.5,
    DateTime? locationCapturedAt,
    DateTime? updatedAt,
  }) => RelioSosEvent(
    id: 'sos-test',
    ownerDeviceId: 'device-test',
    ownerUserId: '',
    message: 'QA test',
    latitude: latitude,
    longitude: longitude,
    locationAccuracy: 10,
    locationCapturedAt: locationCapturedAt,
    createdAt: now.subtract(const Duration(minutes: 12)),
    updatedAt: updatedAt ?? now,
    isActive: true,
    deliveryStatus: DeliveryStatus.delivered,
  );

  test('uses capture time instead of the newer SOS receive/update time', () {
    final received = event(
      locationCapturedAt: now.subtract(const Duration(minutes: 11)),
      updatedAt: now,
    );

    expect(
      sosLocationFreshnessLabel(received, now),
      '⚠ ตำแหน่งอาจไม่ใช่ตำแหน่งปัจจุบัน',
    );
  });

  test('missing or invalid coordinates are never labeled fresh', () {
    final missingTimestamp = event(locationCapturedAt: null);
    final missingCoordinates = event(
      latitude: null,
      longitude: null,
      locationCapturedAt: now,
    );

    expect(sosLocationFreshnessLabel(missingTimestamp, now), 'ยังไม่มีตำแหน่ง');
    expect(
      sosLocationFreshnessLabel(missingCoordinates, now),
      'ยังไม่มีตำแหน่ง',
    );
    expect(sosLocationFreshnessLabel(null, now), 'ยังไม่มีตำแหน่ง');
  });
}
