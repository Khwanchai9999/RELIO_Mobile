import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/core/location/nearby_map_calculations.dart';
import 'package:relio_mobile/app/theme/relio_colors.dart';
import 'package:relio_mobile/features/nearby/nearby_map_canvas.dart';
import 'package:relio_mobile/features/nearby/nearby_marker_reconciliation.dart';
import 'package:relio_mobile/features/nearby/nearby_marker_hit_test.dart';

void main() {
  test('self marker keeps a compact native diameter', () {
    expect(nearbySelfMarkerDiameter, 36);
  });
  test('map modes retain SOS then Rescue then Normal colors', () {
    expect(nearbyMapStatusColor(DeviceStatus.normal), RelioColors.mapNormal);
    expect(nearbyMapStatusColor(DeviceStatus.rescue), RelioColors.mapRescue);
    expect(nearbyMapStatusColor(DeviceStatus.sos), RelioColors.mapSos);
  });
  test('shared Chat coordinates use a non-emergency map marker', () {
    expect(
      nearbyTargetLocationLabel(shared: true, historical: false),
      'ตำแหน่งที่แชร์',
    );
    expect(nearbyTargetLocationColor(shared: true), RelioColors.primary);
    expect(
      nearbyTargetLocationLabel(shared: false, historical: true),
      'SOS • ตำแหน่งที่บันทึกไว้',
    );
    expect(nearbyTargetLocationColor(shared: false), RelioColors.sos);
  });
  test(
    'orange peer outline identifies stale location, selection is distinct',
    () {
      expect(
        nearbyPeerMarkerStrokeColor(selected: false, fresh: true),
        Colors.white,
      );
      expect(
        nearbyPeerMarkerStrokeColor(selected: false, fresh: false),
        RelioColors.warning,
      );
      expect(
        nearbyPeerMarkerStrokeColor(selected: true, fresh: false),
        RelioColors.primaryDark,
      );
    },
  );
  test(
    'heading smooths jitter, tolerates brief accuracy loss, then expires',
    () {
      final filter = NearbyHeadingFilter();
      final now = DateTime.utc(2026, 11, 2, 10);
      expect(
        filter.update(359, accuracyDegrees: 5, now: now),
        closeTo(359, 0.01),
      );
      final smoothed = filter.update(
        1,
        accuracyDegrees: 5,
        now: now.add(const Duration(milliseconds: 200)),
      );
      expect(smoothed, closeTo(359.5, 0.01));
      expect(
        filter.update(
          double.nan,
          accuracyDegrees: 5,
          now: now.add(const Duration(milliseconds: 300)),
        ),
        closeTo(359.5, 0.01),
      );
      expect(
        filter.update(
          3,
          accuracyDegrees: null,
          now: now.add(const Duration(milliseconds: 400)),
        ),
        closeTo(0.375, 0.02),
      );
      expect(filter.confidence, NearbyHeadingConfidence.provisional);
      expect(
        NearbyMapCalculations.validCompassHeading(90, accuracyDegrees: null),
        90,
      );
      expect(filter.expire(now.add(const Duration(seconds: 4))), isNull);
      expect(RelioColors.mapSelfHeading, isNot(RelioColors.mapSelf));
      expect(
        filter.update(
          40,
          accuracyDegrees: 50,
          now: now.add(const Duration(seconds: 5)),
        ),
        isNull,
      );
    },
  );
  test('map uses z15 vector detail with camera overzoom capped at z18', () {
    expect(nearbyMapTileMaxZoom, 15);
    expect(nearbyMapCameraMaxZoom, 18);
    final saved = nearbyInitialCameraPosition(
      savedViewport: const CameraPosition(
        target: LatLng(13.75, 100.5),
        zoom: 17,
      ),
    );
    expect(saved.zoom, 17);
    final capped = nearbyInitialCameraPosition(
      savedViewport: const CameraPosition(
        target: LatLng(13.75, 100.5),
        zoom: 21,
      ),
    );
    expect(capped.zoom, 18);
  });
  test('MapLibre attribution stays in its compact native corner control', () {
    expect(nearbyMapAttributionPosition, AttributionButtonPosition.bottomLeft);
    expect(nearbyMapAttributionMargins.x, 10);
    expect(nearbyMapAttributionMargins.y, 28);
  });
  test('equivalent peer updates preserve rendered identities', () {
    final state = NearbyMarkerReconciliation();
    state.begin();
    expect(state.needsUpdate('peer-circle:a', 'green@point'), isTrue);
    state.applied('peer-circle:a', 'green@point');
    state.begin();
    expect(state.needsUpdate('peer-circle:a', 'green@point'), isFalse);
    expect(state.missingIds, isEmpty);
  });
  test('heading changes update self only and retain peer markers', () {
    final state = NearbyMarkerReconciliation();
    state.begin();
    state.needsUpdate('self-heading', '0');
    state.applied('self-heading', '0');
    state.needsUpdate('peer-circle:a', 'green');
    state.applied('peer-circle:a', 'green');
    state.begin();
    expect(state.needsUpdate('self-heading', '15'), isTrue);
    expect(state.needsUpdate('peer-circle:a', 'green'), isFalse);
    expect(state.missingIds, isEmpty);
  });
  test(
    'only absent identities are removed and failed changes remain retryable',
    () {
      final state = NearbyMarkerReconciliation();
      state.begin();
      state.needsUpdate('a', 'green');
      state.applied('a', 'green');
      state.needsUpdate('b', 'green');
      state.applied('b', 'green');
      state.begin();
      expect(state.needsUpdate('a', 'red'), isTrue);
      expect(state.missingIds, ['b']);
      state.forget('b');
      state.begin();
      expect(state.needsUpdate('a', 'red'), isTrue);
      state.applied('a', 'red');
      expect(state.missingIds, isEmpty);
      state.begin();
      expect(state.needsUpdate('a', 'red'), isFalse);
    },
  );
  test('a style reload restores each marker once', () {
    final state = NearbyMarkerReconciliation();
    state.begin();
    state.needsUpdate('a', 'green');
    state.applied('a', 'green');
    state.reset();
    state.begin();
    expect(state.needsUpdate('a', 'green'), isTrue);
    state.applied('a', 'green');
    state.begin();
    expect(state.needsUpdate('a', 'green'), isFalse);
  });
  test('overlapping and nearby markers stay individually selectable', () {
    const markers = [
      NearbyMapMarkerHit(id: 'self', screenPoint: Offset(100, 100)),
      NearbyMapMarkerHit(id: 'peer-a', screenPoint: Offset(100, 100)),
      NearbyMapMarkerHit(id: 'peer-b', screenPoint: Offset(124, 100)),
      NearbyMapMarkerHit(id: 'peer-far', screenPoint: Offset(160, 100)),
    ];
    expect(nearbyMapMarkerIdsAtPoint(markers, 'self'), [
      'self',
      'peer-a',
      'peer-b',
    ]);
    expect(nearbyMapMarkerIdsAtPoint(markers, 'peer-b'), [
      'self',
      'peer-a',
      'peer-b',
    ]);
    expect(nearbyMapMarkerIdsAtPoint(markers, 'peer-far'), ['peer-far']);
  });
  final now = DateTime.utc(2026, 11, 1, 12);
  test('intentional viewport wins over a fresh self position', () {
    final result = nearbyInitialCameraPosition(
      savedViewport: const CameraPosition(
        target: LatLng(18.79, 98.98),
        zoom: 8,
      ),
      selfLocation: LocationData(
        latitude: 13.75,
        longitude: 100.5,
        capturedAt: now,
      ),
      now: now,
    );
    expect(result.target.latitude, 18.79);
    expect(result.zoom, 8);
  });
  test('fresh self location opens at the supported useful local zoom', () {
    final result = nearbyInitialCameraPosition(
      selfLocation: LocationData(
        latitude: 13.75,
        longitude: 100.5,
        capturedAt: now,
      ),
      now: now,
    );
    expect(result.target.latitude, 13.75);
    expect(result.zoom, 12);
  });
  test(
    'invalid viewport and stale self position use the neutral Thailand fallback',
    () {
      final result = nearbyInitialCameraPosition(
        savedViewport: const CameraPosition(target: LatLng(18, 100), zoom: -1),
        selfLocation: LocationData(
          latitude: 13.75,
          longitude: 100.5,
          capturedAt: now.subtract(const Duration(days: 2)),
        ),
        now: now,
      );
      expect(result.target.latitude, 15);
      expect(result.target.longitude, 101);
      expect(result.zoom, 5);
    },
  );
}
