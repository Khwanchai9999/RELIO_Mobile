import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/device/battery_info_service.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/location/nearby_map_calculations.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

import 'support/nearby_pair.dart';

void main() {
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
        locationCapturedAt: DateTime.utc(2026, 10, 12),
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
        capturedAt: DateTime.utc(2026, 10, 12, 10),
        source: 'test',
      );
      await pair.serviceA.publishMapLocation(location);
      await waitFor(() async {
        final capturedAt = (await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        ))?.peerLocationCapturedAt;
        return capturedAt?.isAtSameMomentAs(location.capturedAt) ?? false;
      });
      final peer = await pair.repositoriesB.nearbyDevices.getDevice('device-a');
      expect(peer?.status, DeviceStatus.normal);
      expect(peer?.peerDeviceModel, isNull);
      expect(peer?.peerLocationAccuracy, 12);
    },
  );
}
