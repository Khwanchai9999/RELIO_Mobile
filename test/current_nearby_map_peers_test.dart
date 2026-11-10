import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/features/nearby/current_nearby_map_peers.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  final now = DateTime.utc(2026, 11, 3, 12);

  RelioNearbyDevice saved(
    String id, {
    double? latitude = 14,
    double? longitude = 100,
    DateTime? capturedAt,
    bool noTimestamp = false,
  }) => RelioNearbyDevice(
    deviceId: id,
    displayName: id,
    status: DeviceStatus.normal,
    lastSeenAt: now,
    peerLatitude: latitude,
    peerLongitude: longitude,
    peerLocationCapturedAt: noTimestamp ? null : capturedAt ?? now,
  );

  NearbyPeer peer(String id, {String endpoint = 'ep'}) =>
      NearbyPeer(id: endpoint, name: id, deviceId: id, connected: true);

  test('current map excludes saved-only and disconnected identities', () {
    final result = currentNearbyMapPeerIds(
      savedDevices: [saved('online'), saved('offline')],
      authenticatedPeers: [peer('online')],
      now: now,
    );
    expect(result, {'online'});
  });

  test('current map deduplicates endpoints by canonical device identity', () {
    final result = currentNearbyMapPeerIds(
      savedDevices: [saved('same')],
      authenticatedPeers: [
        peer('same', endpoint: 'endpoint-a'),
        peer('same', endpoint: 'endpoint-b'),
      ],
      now: now,
    );
    expect(result, {'same'});
  });

  test('current map allows only the shared bounded future clock skew', () {
    final result = currentNearbyMapPeerIds(
      savedDevices: [
        saved('fresh'),
        saved('old', capturedAt: now.subtract(const Duration(minutes: 11))),
        saved('missing', latitude: null, longitude: null),
        saved('untimed', noTimestamp: true),
        saved('future-1', capturedAt: now.add(const Duration(seconds: 1))),
        saved('future-5', capturedAt: now.add(const Duration(seconds: 5))),
        saved('future-10', capturedAt: now.add(const Duration(seconds: 10))),
        saved('future-11', capturedAt: now.add(const Duration(seconds: 11))),
      ],
      authenticatedPeers: [
        peer('fresh'),
        peer('old'),
        peer('missing'),
        peer('untimed'),
        peer('future-1'),
        peer('future-5'),
        peer('future-10'),
        peer('future-11'),
      ],
      now: now,
    );
    expect(result, {'fresh', 'future-1', 'future-5', 'future-10'});
  });
}
