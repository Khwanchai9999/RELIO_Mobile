import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/device/battery_info_service.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/location/nearby_map_calculations.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/nearby/nearby_screen.dart';

import 'support/nearby_pair.dart';

void main() {
  group('Nearby battery freshness', () {
    final now = DateTime.utc(2026, 11, 3, 12);

    RelioNearbyDevice device(DateTime? updatedAt, {int? level = 72}) =>
        RelioNearbyDevice(
          deviceId: 'peer',
          displayName: 'Peer',
          status: DeviceStatus.normal,
          lastSeenAt: now,
          batteryLevel: level,
          batteryUpdatedAt: updatedAt,
        );

    test('uses bounded clock skew and the ten-minute report cadence', () {
      for (final secondsAhead in [0, 1, 5, 10]) {
        expect(
          isFreshNearbyBattery(
            device(now.add(Duration(seconds: secondsAhead))),
            connected: true,
            now: now,
          ),
          isTrue,
          reason: '$secondsAhead seconds of skew is within policy',
        );
      }
      expect(
        isFreshNearbyBattery(
          device(now.add(const Duration(seconds: 11))),
          connected: true,
          now: now,
        ),
        isFalse,
      );
      expect(
        isFreshNearbyBattery(
          device(now.subtract(const Duration(minutes: 11, seconds: 59))),
          connected: true,
          now: now,
        ),
        isTrue,
      );
      expect(
        isFreshNearbyBattery(
          device(now.subtract(const Duration(minutes: 12, seconds: 1))),
          connected: true,
          now: now,
        ),
        isFalse,
      );
    });

    test(
      'keeps unavailable, invalid, or disconnected readings unavailable',
      () {
        expect(
          isFreshNearbyBattery(device(null), connected: true, now: now),
          isFalse,
        );
        expect(
          isFreshNearbyBattery(
            device(now, level: -1),
            connected: true,
            now: now,
          ),
          isFalse,
        );
        expect(
          isFreshNearbyBattery(
            device(now, level: 101),
            connected: true,
            now: now,
          ),
          isFalse,
        );
        expect(
          isFreshNearbyBattery(device(now), connected: false, now: now),
          isFalse,
        );
      },
    );
  });

  group('BatteryPublishPolicy', () {
    const policy = BatteryPublishPolicy();
    final now = DateTime.utc(2026, 10, 12, 10);

    test('publishes first snapshot and meaningful five percent changes', () {
      const previous = BatterySnapshot(level: 70, isCharging: false);
      expect(
        policy.shouldPublish(previous: null, current: previous, now: now),
        isTrue,
      );
      expect(
        policy.shouldPublish(
          previous: previous,
          current: const BatterySnapshot(level: 74, isCharging: false),
          now: now,
        ),
        isFalse,
      );
      expect(
        policy.shouldPublish(
          previous: previous,
          current: const BatterySnapshot(level: 75, isCharging: false),
          now: now,
        ),
        isTrue,
      );
    });

    test(
      'charging changes and stale refresh publish; invalid levels do not',
      () {
        const previous = BatterySnapshot(level: 70, isCharging: false);
        expect(
          policy.shouldPublish(
            previous: previous,
            current: const BatterySnapshot(level: 70, isCharging: true),
            now: now,
          ),
          isTrue,
        );
        expect(
          policy.shouldPublish(
            previous: BatterySnapshot(
              level: 70,
              isCharging: false,
              updatedAt: now.subtract(const Duration(minutes: 10)),
            ),
            current: BatterySnapshot(
              level: 70,
              isCharging: false,
              updatedAt: now,
            ),
            now: now,
          ),
          isTrue,
        );
        expect(
          policy.shouldPublish(
            previous: null,
            current: const BatterySnapshot(level: 101, isCharging: false),
            now: now,
          ),
          isFalse,
        );
      },
    );
  });

  group('peer metadata packets', () {
    test('hello without optional metadata remains backward compatible', () {
      final packet = RelioPacket.hello(
        senderDeviceId: 'peer',
        senderUserId: 'peer',
        displayName: 'Peer',
      );
      final decoded = RelioPacket.fromBytes(packet.toBytes());
      expect(decoded.payload.containsKey('batteryLevel'), isFalse);
      expect(decoded.payload.containsKey('latitude'), isFalse);
    });

    test('metadata serializes and rejects invalid battery/location values', () {
      final packet = RelioPacket.deviceStatus(
        senderDeviceId: 'peer',
        senderUserId: 'peer',
        displayName: 'Peer',
        status: DeviceStatus.normal,
        batteryLevel: 63,
        isCharging: true,
        latitude: 10.25,
        longitude: 101.5,
        locationCapturedAt: DateTime.now().toUtc(),
      );
      final decoded = RelioPacket.fromBytes(packet.toBytes());
      expect(decoded.payload['batteryLevel'], 63);
      expect(decoded.payload['isCharging'], isTrue);
      expect(decoded.payload['latitude'], 10.25);

      final invalidBattery = RelioPacket.deviceStatus(
        senderDeviceId: 'peer',
        senderUserId: 'peer',
        displayName: 'Peer',
        status: DeviceStatus.normal,
        batteryLevel: 120,
      );
      expect(
        () => RelioPacket.fromBytes(invalidBattery.toBytes()),
        throwsA(isA<RelioPacketException>()),
      );
      final invalidPoint = RelioPacket.deviceStatus(
        senderDeviceId: 'peer',
        senderUserId: 'peer',
        displayName: 'Peer',
        status: DeviceStatus.normal,
        latitude: 91,
        longitude: 0,
      );
      expect(
        () => RelioPacket.fromBytes(invalidPoint.toBytes()),
        throwsA(isA<RelioPacketException>()),
      );
    });
  });

  group('NearbyMapCalculations', () {
    final now = DateTime.utc(2026, 10, 12, 10);

    test('handles absent and malformed positions without fake markers', () {
      expect(NearbyMapCalculations.isValidPoint(null, null), isFalse);
      expect(NearbyMapCalculations.isValidPoint(91, 0), isFalse);
      expect(
        NearbyMapCalculations.distanceMeters(
          fromLatitude: null,
          fromLongitude: null,
          toLatitude: 10,
          toLongitude: 20,
        ),
        isNull,
      );
    });

    test('formats distance, direction, and stale location warnings', () {
      final distance = NearbyMapCalculations.distanceMeters(
        fromLatitude: 0,
        fromLongitude: 0,
        toLatitude: 0,
        toLongitude: 0.01,
      );
      expect(NearbyMapCalculations.distanceLabel(distance), '1.1 กม.');
      expect(
        NearbyMapCalculations.bearingLabel(
          NearbyMapCalculations.bearingDegrees(
            fromLatitude: 0,
            fromLongitude: 0,
            toLatitude: 1,
            toLongitude: 0,
          ),
        ),
        'ประมาณ เหนือ',
      );
      expect(
        NearbyMapCalculations.freshnessLabel(
          now.subtract(const Duration(minutes: 8)),
          now,
        ),
        startsWith('⚠'),
      );
      expect(
        NearbyMapCalculations.freshnessLabel(
          now.subtract(const Duration(minutes: 11)),
          now,
        ),
        '⚠ ตำแหน่งอาจไม่ใช่ตำแหน่งปัจจุบัน',
      );
      expect(
        NearbyMapCalculations.staleMarkerLabel(
          now.subtract(const Duration(minutes: 1)),
          now,
        ),
        isNull,
      );
      expect(
        NearbyMapCalculations.staleMarkerLabel(
          now.subtract(const Duration(minutes: 8)),
          now,
        ),
        startsWith('⚠ อัปเดต'),
      );
      expect(
        NearbyMapCalculations.staleMarkerLabel(null, now),
        '⚠ ยังไม่มีตำแหน่ง',
      );
    });

    test('map freshness clamps only the accepted future skew', () {
      for (final secondsAhead in [0, 1, 5, 10]) {
        expect(
          NearbyMapCalculations.freshness(
            now.add(Duration(seconds: secondsAhead)),
            now,
          ),
          LocationFreshness.fresh,
        );
      }
      expect(
        NearbyMapCalculations.freshness(
          now.add(const Duration(seconds: 11)),
          now,
        ),
        LocationFreshness.invalid,
      );
      expect(
        NearbyMapCalculations.freshness(
          now.subtract(const Duration(minutes: 11)),
          now,
        ),
        LocationFreshness.veryStale,
      );
    });
  });

  test(
    'verified status metadata persists while peer emergency state stays intact',
    () async {
      final battery = FakeBatteryInfoService(
        const BatterySnapshot(level: 80, isCharging: false),
      );
      final pair = await HandshakePair.create(batteryInfoA: battery);
      addTearDown(() async {
        await pair.close();
        await battery.dispose();
      });
      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () =>
            pair.serviceA.peerStates['endpoint-b'] ==
                NearbyConnectionState.connected &&
            pair.serviceB.peerStates['endpoint-a'] ==
                NearbyConnectionState.connected,
      );
      await waitFor(
        () async =>
            (await pair.repositoriesB.nearbyDevices.getDevice(
              'device-a',
            ))?.batteryLevel ==
            80,
      );
      expect(
        (await pair.repositoriesB.nearbyDevices.getDevice('device-a'))?.status,
        DeviceStatus.normal,
      );

      pair.serviceA.startBatteryMetadataUpdates();
      final publishedBeforeSmallDelta = pair.transportA.packets
          .where((packet) => packet.payload.containsKey('batteryLevel'))
          .length;
      battery.emit(const BatterySnapshot(level: 82, isCharging: false));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        pair.transportA.packets
            .where((packet) => packet.payload.containsKey('batteryLevel'))
            .length,
        publishedBeforeSmallDelta,
      );

      battery.emit(const BatterySnapshot(level: 85, isCharging: false));
      await waitFor(
        () async =>
            (await pair.repositoriesB.nearbyDevices.getDevice(
              'device-a',
            ))?.batteryLevel ==
            85,
      );
      battery.emit(const BatterySnapshot(level: 86, isCharging: true));
      await waitFor(() async {
        final peer = await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        );
        return peer?.batteryLevel == 86 && peer?.isCharging == true;
      });

      final location = LocationData(
        latitude: 10.25,
        longitude: 101.5,
        accuracyMeters: 12,
        capturedAt: DateTime.now().toUtc(),
        source: 'test',
      );
      await pair.serviceA.publishMapLocation(location);
      await waitFor(() async {
        final capturedAt = (await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        ))?.peerLocationCapturedAt;
        return capturedAt != null;
      });
      final peer = await pair.repositoriesB.nearbyDevices.getDevice('device-a');
      expect(peer?.status, DeviceStatus.normal);
      expect(peer?.peerDeviceModel, isNull);
      expect(
        peer?.peerLocationCapturedAt?.difference(location.capturedAt).abs(),
        lessThan(const Duration(seconds: 1)),
      );
      expect(peer?.peerLocationAccuracy, 12);
    },
  );

  test(
    'stale verified deviceStatus cannot regress peer display name or location',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);
      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () => pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
      );

      Future<void> deliver(RelioPacket packet) async {
        final handled = Completer<void>();
        void listener() {
          if (pair.serviceB.lastReceivedPacket?.contains(packet.packetId) ==
                  true &&
              !handled.isCompleted) {
            pair.serviceB.removeListener(listener);
            handled.complete();
          }
        }

        pair.serviceB.addListener(listener);
        pair.transportB.receivePacket(await pair.packetFromA(packet));
        await handled.future.timeout(const Duration(seconds: 2));
      }

      final t0 = DateTime.now().toUtc();
      final t1 = t0.subtract(const Duration(minutes: 1));
      final t2 = t0.add(const Duration(seconds: 1));
      final t3 = t0.add(const Duration(seconds: 2));

      final fresh = RelioPacket.deviceStatus(
        senderDeviceId: 'device-a',
        senderUserId: 'user-a',
        displayName: 'New Bob',
        status: DeviceStatus.normal,
        updatedAt: t2,
        batteryLevel: 80,
        isCharging: false,
        batteryUpdatedAt: t2,
        latitude: 10.25,
        longitude: 101.5,
        locationAccuracy: 12,
        locationCapturedAt: t2,
      );
      await deliver(fresh);
      var peer = await pair.repositoriesB.nearbyDevices.getDevice('device-a');
      expect(peer?.displayName, 'New Bob');
      expect(peer?.peerLatitude, 10.25);
      expect(peer?.peerLongitude, 101.5);

      await deliver(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-a',
          senderUserId: 'user-a',
          displayName: 'Old Bob',
          status: DeviceStatus.normal,
          updatedAt: t1,
          batteryLevel: 20,
          isCharging: true,
          batteryUpdatedAt: t1,
          latitude: 1,
          longitude: 2,
          locationAccuracy: 50,
          locationCapturedAt: t1,
        ),
      );
      peer = await pair.repositoriesB.nearbyDevices.getDevice('device-a');
      expect(peer?.displayName, 'New Bob');
      expect(peer?.peerLatitude, 10.25);
      expect(peer?.peerLongitude, 101.5);
      expect(peer?.batteryLevel, 80);
      expect(peer?.isCharging, isFalse);
      expect(
        peer?.peerLocationCapturedAt?.difference(t2).abs(),
        lessThan(const Duration(seconds: 1)),
      );
      expect(
        peer?.batteryUpdatedAt?.difference(t2).abs(),
        lessThan(const Duration(seconds: 1)),
      );

      await deliver(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-a',
          senderUserId: 'user-a',
          displayName: 'Newest Bob',
          status: DeviceStatus.normal,
          updatedAt: t3,
          batteryLevel: 90,
          isCharging: true,
          batteryUpdatedAt: t3,
          latitude: 30,
          longitude: 120,
          locationAccuracy: 5,
          locationCapturedAt: t3,
        ),
      );
      peer = await pair.repositoriesB.nearbyDevices.getDevice('device-a');
      expect(peer?.displayName, 'Newest Bob');
      expect(peer?.peerLatitude, 30);
      expect(peer?.peerLongitude, 120);
      expect(peer?.batteryLevel, 90);
      expect(peer?.isCharging, isTrue);

      await deliver(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-a',
          senderUserId: 'user-a',
          displayName: 'Newest Bob',
          status: DeviceStatus.normal,
          updatedAt: t3.add(const Duration(seconds: 1)),
        ),
      );
      peer = await pair.repositoriesB.nearbyDevices.getDevice('device-a');
      expect(peer?.batteryLevel, 90);
      expect(peer?.isCharging, isTrue);
      expect(
        peer?.batteryUpdatedAt?.difference(t3).abs(),
        lessThan(const Duration(seconds: 1)),
      );
      expect(peer?.peerLatitude, 30);
      expect(peer?.peerLongitude, 120);
      expect(
        peer?.peerLocationCapturedAt?.difference(t3).abs(),
        lessThan(const Duration(seconds: 1)),
      );
    },
  );
}
