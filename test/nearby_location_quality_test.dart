import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/location/location_service.dart';
import 'package:relio_mobile/core/location/nearby_location_quality.dart';

void main() {
  group('NearbyLocationQuality', () {
    final now = DateTime.now().toUtc();

    test('classifies accuracy and keeps poor accuracy visibly low', () {
      expect(NearbyLocationQuality.confidence(10), LocationConfidence.high);
      expect(NearbyLocationQuality.confidence(75), LocationConfidence.limited);
      expect(NearbyLocationQuality.confidence(250), LocationConfidence.low);
      expect(
        NearbyLocationQuality.accuracyLabel(250),
        'ตำแหน่งคลาดเคลื่อนสูง ±250 ม.',
      );
    });

    test(
      'rejects stale, excessive future, invalid, or unknown-accuracy fixes',
      () {
        expect(
          NearbyLocationQuality.hasValidCaptureTime(
            now.subtract(const Duration(minutes: 2)),
            now,
          ),
          isTrue,
        );
        expect(
          NearbyLocationQuality.hasValidCaptureTime(
            now.subtract(const Duration(minutes: 2, milliseconds: 1)),
            now,
          ),
          isFalse,
        );
        expect(
          NearbyLocationQuality.hasValidCaptureTime(
            now.add(const Duration(seconds: 1)),
            now,
          ),
          isTrue,
        );
        expect(
          NearbyLocationQuality.hasValidCaptureTime(
            now.add(const Duration(seconds: 5)),
            now,
          ),
          isTrue,
        );
        expect(
          NearbyLocationQuality.hasValidCaptureTime(
            now.add(const Duration(seconds: 10)),
            now,
          ),
          isTrue,
        );
        expect(
          NearbyLocationQuality.hasValidCaptureTime(
            now.add(const Duration(seconds: 11)),
            now,
          ),
          isFalse,
        );
        expect(
          NearbyLocationQuality.effectiveAge(
            now.add(const Duration(seconds: 5)),
            now,
          ),
          Duration.zero,
        );
        expect(
          NearbyLocationQuality.isEligibleForCurrentSharing(
            LocationData(
              latitude: 13,
              longitude: 100,
              accuracyMeters: null,
              capturedAt: now,
              source: 'test',
            ),
            now: now,
          ),
          isFalse,
        );
        expect(NearbyLocationQuality.isValidCoordinates(91, 100), isFalse);
      },
    );

    test(
      'a current 250m fix remains eligible but explicitly low confidence',
      () {
        final fix = LocationData(
          latitude: 13,
          longitude: 100,
          accuracyMeters: 250,
          capturedAt: now,
          source: 'gps',
        );
        expect(
          NearbyLocationQuality.isEligibleForCurrentSharing(fix, now: now),
          isTrue,
        );
        expect(
          NearbyLocationQuality.confidence(fix.accuracyMeters),
          LocationConfidence.low,
        );
      },
    );

    test('recent last-known fix is display-only and has a shorter bound', () {
      final cached = LocationData(
        latitude: 13,
        longitude: 100,
        accuracyMeters: 250,
        capturedAt: now.subtract(const Duration(minutes: 4)),
        source: 'lastKnown',
      );
      expect(
        NearbyLocationQuality.isEligibleForLocalDisplay(cached, now: now),
        isTrue,
      );
      expect(
        NearbyLocationQuality.isEligibleForCurrentSharing(cached, now: now),
        isFalse,
      );
      expect(
        NearbyLocationQuality.isEligibleForLocalDisplay(
          cached,
          now: now,
          maxAge: const Duration(minutes: 2),
        ),
        isFalse,
      );
    });
  });

  group('GeolocatorLocationService fresh fix', () {
    late TestLocationPlatform platform;
    late GeolocatorLocationService service;

    setUp(() {
      platform = TestLocationPlatform()
        ..fix = LocationData(
          latitude: 13,
          longitude: 100,
          accuracyMeters: 10,
          capturedAt: DateTime.now().toUtc(),
          source: 'gps',
        );
      service = GeolocatorLocationService(platform: platform);
    });

    test(
      'uses one fresh precise fix and never falls back to stale cache',
      () async {
        platform.lastKnown = LocationData(
          latitude: 14,
          longitude: 101,
          accuracyMeters: 1,
          capturedAt: DateTime.now().subtract(const Duration(days: 2)),
          source: 'lastKnown',
        );
        final result = await service.getFreshLocation();
        expect(result.isSuccess, isTrue);
        expect(result.location?.source, 'gps');
        expect(platform.requests, 1);
      },
    );

    test(
      'fails closed on approximate permission before requesting a fix',
      () async {
        platform.precision = LocationPrecisionState.approximate;
        final result = await service.getFreshLocation();
        expect(result.failure, LocationFailure.approximatePermission);
        expect(platform.requests, 0);
      },
    );

    test('allows a fresh offline fix with low reported accuracy', () async {
      platform.fix = LocationData(
        latitude: 13,
        longitude: 100,
        accuracyMeters: 250,
        capturedAt: DateTime.now().toUtc(),
        source: 'gps',
      );
      final result = await service.getFreshLocation();
      expect(result.isSuccess, isTrue);
      expect(
        NearbyLocationQuality.confidence(result.location?.accuracyMeters),
        LocationConfidence.low,
      );
    });

    test(
      'live stream uses requested cadence without prompting for permission',
      () async {
        final stream = await service.watchPositions(
          interval: const Duration(seconds: 10),
        );
        expect(platform.requestedPositionInterval, const Duration(seconds: 10));
        expect(platform.permissionRequests, 0);
        expect(platform.requests, 0);
        expect(stream, isA<Stream<LocationData>>());
      },
    );

    test(
      'live stream rejects approximate permission without prompting',
      () async {
        platform.precision = LocationPrecisionState.approximate;

        await expectLater(
          service.watchPositions(interval: const Duration(seconds: 5)),
          throwsA(
            isA<LocationStreamException>().having(
              (error) => error.failure,
              'failure',
              LocationFailure.approximatePermission,
            ),
          ),
        );
        expect(platform.permissionRequests, 0);
        expect(platform.requestedPositionInterval, isNull);
      },
    );

    test('recent last-known lookup never requests a new fix', () async {
      platform.lastKnown = LocationData(
        latitude: 13,
        longitude: 100,
        accuracyMeters: 35,
        capturedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        source: 'lastKnown',
      );

      final cached = await service.getRecentLastKnownForDisplay();

      expect(cached?.source, 'lastKnown');
      expect(platform.requests, 0);
      expect(platform.permissionRequests, 0);
    });
  });
}
