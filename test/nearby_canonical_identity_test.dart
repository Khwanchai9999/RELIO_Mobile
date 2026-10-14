import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';

import 'support/nearby_pair.dart';

Future<void> firstPair(HandshakePair pair) async {
  await waitFor(
    () =>
        pair.serviceA.isEndpointCurrent('endpoint-b') &&
        pair.serviceB.isEndpointCurrent('endpoint-a'),
  );
  await pair.serviceA.connect('endpoint-b');
  await waitFor(
    () =>
        pair.serviceA.pendingConnectionRequests.isNotEmpty &&
        pair.serviceB.pendingConnectionRequests.isNotEmpty,
  );
  await pair.serviceA.acceptConnectionRequest('endpoint-b');
  await pair.serviceB.acceptConnectionRequest('endpoint-a');
  await waitFor(
    () =>
        pair.serviceA.deviceToEndpointId['device-b'] == 'endpoint-b' &&
        pair.serviceB.deviceToEndpointId['device-a'] == 'endpoint-a',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local disconnect clears canonical mapping without a native local callback',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await firstPair(pair);
      pair.transportA.omitLocalDisconnectCallback = true;
      await pair.serviceA.disconnect('endpoint-b');
      expect(pair.serviceA.deviceToEndpointId['device-b'], isNull);
      expect(pair.serviceA.endpointToDeviceId['endpoint-b'], isNull);
      expect(pair.serviceA.currentPeers.single.connected, isFalse);
      await waitFor(
        () =>
            pair.serviceB.peerStates['endpoint-a'] ==
            NearbyConnectionState.disconnected,
      );
      await pair.serviceA.connectPeer(pair.serviceA.currentPeers.single);
      await waitFor(
        () => pair.serviceA.deviceToEndpointId['device-b'] == 'endpoint-b',
      );
    },
  );

  test('identity and native callbacks preserve the discovery epoch', () async {
    final pair = await HandshakePair.create(requireBothNativeAccepts: true);
    addTearDown(pair.close);
    await pair.serviceA.startDiscovery();
    await pair.serviceB.startDiscovery();
    pair.transportA.discoverPeer();
    pair.transportB.discoverPeer();
    await firstPair(pair);
    await pair.serviceA.disconnect('endpoint-b');
    await waitFor(
      () =>
          pair.serviceB.peerStates['endpoint-a'] ==
          NearbyConnectionState.disconnected,
    );
    expect(pair.serviceA.isEndpointCurrent('endpoint-b'), isTrue);
    expect(pair.serviceB.isEndpointCurrent('endpoint-a'), isTrue);
    expect(pair.serviceA.currentPeers.single.connected, isFalse);
    await pair.serviceA.connectPeer(pair.serviceA.currentPeers.single);
    await waitFor(
      () => pair.serviceA.deviceToEndpointId['device-b'] == 'endpoint-b',
    );
  });

  test(
    'ten endpoint rotations keep one canonical peer beside another identity',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await firstPair(pair);
      final original = pair.serviceA.currentPeers.single;
      pair.serviceA.discoveredPeers.add(
        NearbyPeer(
          id: 'other-device-endpoint',
          name: original.name,
          identityFingerprintHint: 'c' * 64,
          discoveryEpoch: pair.transportA.discoveryEpoch,
          lastSeenAt: DateTime.now().toUtc(),
        ),
      );
      for (var cycle = 1; cycle <= 10; cycle++) {
        final oldA = pair.transportA.localEndpointId;
        pair.transportA.discoverAlias(
          NearbyPeer(
            id: 'overlapping-alias-$cycle',
            name: 'temporary alias',
            identityFingerprintHint: original.identityFingerprintHint,
            discoveryEpoch: pair.transportA.discoveryEpoch,
            lastSeenAt: DateTime.now().toUtc(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          pair.serviceA.currentPeers
              .where(
                (peer) =>
                    peer.identityFingerprintHint ==
                    original.identityFingerprintHint,
              )
              .single
              .endpointId,
          oldA,
        );
        await pair.serviceA.disconnect(oldA);
        await waitFor(
          () =>
              pair.serviceB.peerStates[pair.transportB.localEndpointId] ==
              NearbyConnectionState.disconnected,
        );
        final endpointB = 'endpoint-b-$cycle';
        final endpointA = 'endpoint-a-$cycle';
        await pair.identityB.setDisplayName('Verified Realme $cycle');
        pair.transportA.changeEndpointIds(local: endpointB, remote: endpointA);
        pair.transportB.changeEndpointIds(local: endpointA, remote: endpointB);
        pair.transportA.refreshPeerName('temporary alias $cycle');
        pair.transportB.discoverPeer();
        await waitFor(
          () =>
              pair.serviceA.deviceToEndpointId['device-b'] == endpointB &&
              pair.serviceB.deviceToEndpointId['device-a'] == endpointA,
        );
        final peer = pair.serviceA.currentPeers
            .where(
              (peer) =>
                  peer.identityFingerprintHint ==
                  original.identityFingerprintHint,
            )
            .single;
        expect(peer.deviceId, 'device-b');
        expect(peer.endpointId, endpointB);
        expect(peer.name, 'Verified Realme $cycle');
        expect(pair.serviceA.currentPeers, hasLength(2));
        expect(
          pair.serviceA.endpointToDeviceId.entries.where(
            (entry) => entry.value == 'device-b',
          ),
          hasLength(1),
        );
        expect(
          await pair.repositoriesA.nearbyDevices.listDevices(),
          hasLength(1),
        );
        expect(
          pair.serviceA.endpointToDeviceId['other-device-endpoint'],
          isNull,
        );
        expect(pair.serviceA.pendingConnectionRequests, isEmpty);
        expect(pair.serviceB.pendingConnectionRequests, isEmpty);
      }
    },
  );

  test(
    'provisional aliases select the freshest endpoint and preserve other identities',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);
      final old = pair.serviceA.currentPeers.single;
      final now = DateTime.now().toUtc();
      pair.serviceA.discoveredPeers.addAll([
        NearbyPeer(
          id: 'fresh',
          name: 'same label',
          identityFingerprintHint: old.identityFingerprintHint,
          discoveryEpoch: pair.transportA.discoveryEpoch,
          lastSeenAt: now.add(const Duration(seconds: 1)),
        ),
        NearbyPeer(
          id: 'different',
          name: 'same label',
          identityFingerprintHint: 'd' * 64,
          discoveryEpoch: pair.transportA.discoveryEpoch,
          lastSeenAt: now,
        ),
      ]);
      expect(pair.serviceA.currentPeers, hasLength(2));
      expect(
        pair.serviceA.currentPeers
            .where(
              (peer) =>
                  peer.identityFingerprintHint == old.identityFingerprintHint,
            )
            .single
            .endpointId,
        'fresh',
      );
      // Native test adapter still knows the original endpoint: stale row selection must choose the new canonical candidate.
      await pair.serviceA.connectPeer(old);
      expect(pair.serviceA.peerStates['fresh'], NearbyConnectionState.failed);
      expect(
        pair.serviceA.peerStates[old.endpointId],
        isNot(NearbyConnectionState.connecting),
      );
      expect(pair.serviceA.peerStates['different'], isNull);
    },
  );

  test(
    'a selected canonical peer cannot connect an endpoint belonging to another peer',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);
      final peer = pair.serviceA.currentPeers.single;
      pair.serviceA.discoveredPeers[0] = peer.withIdentity(
        deviceId: 'device-b',
      );
      await pair.serviceA.connectPeer(peer.withIdentity(deviceId: 'device-x'));
      expect(
        pair.serviceA.peerStates[peer.endpointId],
        NearbyConnectionState.disconnected,
      );
      expect(pair.transportA.acceptCalls, isEmpty);
    },
  );

  test('discovery alias cannot overwrite a verified profile name', () async {
    final pair = await HandshakePair.create(requireBothNativeAccepts: true);
    addTearDown(pair.close);
    await firstPair(pair);
    final verified = pair.serviceA.currentPeers.single;
    pair.transportA.refreshPeerName('stale discovery name');
    await Future<void>.delayed(Duration.zero);
    expect(pair.serviceA.currentPeers.single.name, verified.name);
    expect(pair.serviceA.currentPeers.single.deviceId, 'device-b');
  });

  test(
    'older battery metadata cannot overwrite fresh SQLite telemetry',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);
      final now = DateTime.now().toUtc();
      await pair.repositoriesA.nearbyDevices.upsert(
        deviceId: 'peer',
        displayName: 'Peer',
        status: DeviceStatus.normal,
        batteryLevel: 80,
        batteryUpdatedAt: now,
      );
      await pair.repositoriesA.nearbyDevices.upsert(
        deviceId: 'peer',
        displayName: 'Peer',
        status: DeviceStatus.normal,
        batteryLevel: 2,
        batteryUpdatedAt: now.subtract(const Duration(minutes: 3)),
      );
      expect(
        (await pair.repositoriesA.nearbyDevices.getDevice(
          'peer',
        ))?.batteryLevel,
        80,
      );
    },
  );

  test(
    'application packets from a retired endpoint cannot update canonical metadata',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await firstPair(pair);
      pair.serviceA.deviceToEndpointId['device-b'] = 'new-canonical-endpoint';
      await pair.transportB.sendBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-b',
          senderUserId: 'device-b',
          displayName: 'stale alias',
          status: DeviceStatus.normal,
          batteryLevel: 2,
        ).toBytes(),
        peerId: 'endpoint-a',
      );
      await waitFor(() => pair.serviceA.protocolErrorCount > 0);
      expect(
        (await pair.repositoriesA.nearbyDevices.getDevice(
          'device-b',
        ))?.displayName,
        isNot('stale alias'),
      );
    },
  );
}
