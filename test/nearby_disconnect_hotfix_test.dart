import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';

import 'support/nearby_pair.dart';

Future<void> pending(HandshakePair pair) => waitFor(
  () =>
      pair.transportA.acceptCalls.contains('endpoint-b') &&
      pair.transportB.acceptCalls.contains('endpoint-a'),
);

Future<void> connected(HandshakePair pair) => waitFor(
  () =>
      pair.serviceA.deviceToEndpointId['device-b'] ==
          pair.transportA.localEndpointId &&
      pair.serviceB.deviceToEndpointId['device-a'] ==
          pair.transportB.localEndpointId &&
      pair.serviceA.transientConnectionCounts['completedHandshakes'] == 1 &&
      pair.serviceB.transientConnectionCounts['completedHandshakes'] == 1 &&
      pair.serviceA.peerErrors.isEmpty &&
      pair.serviceB.peerErrors.isEmpty,
);

Future<void> establish(HandshakePair pair, {bool approve = true}) async {
  await pair.serviceA.connect(pair.transportA.localEndpointId);
  if (approve) {
    await pending(pair);
    await pair.serviceA.acceptConnectionRequest(
      pair.transportA.localEndpointId,
    );
    await pair.serviceB.acceptConnectionRequest(
      pair.transportB.localEndpointId,
    );
  }
  await connected(pair);
}

void expectClean(NearbyService service) {
  for (final entry in service.transientConnectionCounts.entries) {
    expect(entry.value, 0, reason: '${entry.key} must not survive teardown');
  }
  expect(service.connectedPeers, isEmpty);
  expect(service.discoveredPeers.every((peer) => !peer.connected), isTrue);
}

Future<void> cleanBoth(HandshakePair pair) async {
  await waitFor(
    () =>
        pair.serviceB.peerStates[pair.transportB.localEndpointId] ==
        NearbyConnectionState.disconnected,
  );
  await Future<void>.delayed(const Duration(milliseconds: 20));
  expectClean(pair.serviceA);
  expectClean(pair.serviceB);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'incoming-only peer recovers fresh discovery on both sides after disconnect',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await pair.serviceA.startSession();
      await pair.serviceB.startSession();
      pair.transportA.discoverPeer();
      await Future<void>.delayed(Duration.zero);
      await establish(pair);
      expect(pair.serviceB.isEndpointCurrent('endpoint-a'), isFalse);

      for (var cycle = 0; cycle < 5; cycle++) {
        final initiator = cycle.isEven ? pair.serviceA : pair.serviceB;
        await initiator.disconnect(cycle.isEven ? 'endpoint-b' : 'endpoint-a');
        await waitFor(
          () =>
              pair.transportA.startDiscoveryCalls == cycle + 2 &&
              pair.transportB.startDiscoveryCalls == cycle + 2,
        );
        await cleanBoth(pair);
        expect(pair.serviceA.isEndpointCurrent('endpoint-b'), isFalse);
        expect(pair.serviceB.isEndpointCurrent('endpoint-a'), isFalse);
        final requests = pair.transportB.requestCalls;
        await pair.serviceB.connect('endpoint-a');
        expect(pair.transportB.requestCalls, requests);
        // เหมือน Huawei พบ Realme ฝั่งเดียว: ต้องใช้ endpointFound ใหม่และ proof เดิม
        pair.transportA.discoverPeer();
        await Future<void>.delayed(Duration.zero);
        await establish(pair, approve: false);
        expect(pair.serviceA.pendingConnectionRequests, isEmpty);
        expect(pair.serviceB.pendingConnectionRequests, isEmpty);
        expect(pair.transportA.startAdvertisingCalls, cycle + 2);
        expect(pair.transportB.startAdvertisingCalls, cycle + 2);
        expect(pair.transportA.idleEndpointClearCalls, cycle + 1);
        expect(pair.transportB.idleEndpointClearCalls, cycle + 1);
      }
    },
  );

  test(
    'cancel during negotiation does not restart an active discovery epoch',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await pair.serviceA.startSession();
      await pair.serviceB.startSession();
      pair.transportA.holdConnectionResult = true;
      pair.transportB.holdConnectionResult = true;
      pair.transportA.discoverPeer();
      await Future<void>.delayed(Duration.zero);
      await pair.serviceA.connect('endpoint-b');
      await pending(pair);
      await pair.serviceA.cancelConnection('endpoint-b');
      await cleanBoth(pair);
      expect(pair.transportA.startDiscoveryCalls, 1);
      expect(pair.transportB.startDiscoveryCalls, 1);
    },
  );

  for (final state in [
    NearbyConnectionState.connected,
    NearbyConnectionState.connecting,
  ]) {
    test('disconnect recovery preserves another ${state.name} peer', () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await pair.serviceA.startSession();
      pair.transportA.discoverPeer();
      await Future<void>.delayed(Duration.zero);
      await establish(pair);
      pair.transportA.discoverAlias(
        const NearbyPeer(id: 'other', name: 'Other'),
      );
      await Future<void>.delayed(Duration.zero);
      pair.serviceA.peerStates['other'] = state;
      await pair.serviceA.disconnect('endpoint-b');
      expect(pair.transportA.stopDiscoveryCalls, 0);
      expect(pair.transportA.stopAdvertisingCalls, 0);
      expect(pair.transportA.idleEndpointClearCalls, 0);
      expect(pair.serviceA.peerStates['other'], state);
    });
  }

  test(
    '30/30 one-sided disconnect and immediate trusted reconnect without local callback',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await establish(pair);
      pair.transportA.omitLocalDisconnectCallback = true;
      for (var cycle = 0; cycle < 30; cycle++) {
        final proofsA = pair.cryptoA.verifyCalls;
        final proofsB = pair.cryptoB.verifyCalls;
        await pair.serviceA.disconnect('endpoint-b');
        await cleanBoth(pair);
        expect(
          (await pair.repositoriesA.nearbyDevices.getDevice(
            'device-b',
          ))?.isTrusted,
          isTrue,
        );
        if (cycle.isEven) {
          pair.transportA.discoverPeer();
          pair.transportB.discoverPeer();
        }
        await establish(pair, approve: false);
        expect(pair.serviceA.pendingConnectionRequests, isEmpty);
        expect(pair.serviceB.pendingConnectionRequests, isEmpty);
        expect(pair.cryptoA.verifyCalls, greaterThan(proofsA));
        expect(pair.cryptoB.verifyCalls, greaterThan(proofsB));
        expect(pair.serviceA.endpointToDeviceId, hasLength(1));
        expect(pair.serviceB.endpointToDeviceId, hasLength(1));
        await pair.serviceA.disconnect('endpoint-b');
        await cleanBoth(pair);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    '10/10 cancel while native result is pending recovers on next connection',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await establish(pair);
      await pair.serviceA.disconnect('endpoint-b');
      await cleanBoth(pair);
      for (var cycle = 0; cycle < 10; cycle++) {
        pair.transportA.holdConnectionResult = true;
        pair.transportB.holdConnectionResult = true;
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () =>
              pair.transportA.acceptedConnections.isNotEmpty &&
              pair.transportB.acceptedConnections.isNotEmpty,
        );
        expect(
          pair.serviceA.peerStates['endpoint-b'],
          NearbyConnectionState.connecting,
        );
        await pair.serviceA.cancelConnection('endpoint-b');
        await cleanBoth(pair);
        pair.transportA.holdConnectionResult = false;
        pair.transportB.holdConnectionResult = false;
        await establish(pair, approve: false);
        await pair.serviceA.disconnect('endpoint-b');
        await cleanBoth(pair);
      }
    },
  );

  test(
    'cancel approval and late request task completion cannot revive the session',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      final gate = pair.transportA.requestGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final request = pair.serviceA.connect('endpoint-b');
      await pending(pair);
      await pair.serviceA.cancelConnection('endpoint-b');
      await cleanBoth(pair);
      gate.complete();
      await request;
      pair.transportA.requestGate = null;
      expectClean(pair.serviceA);
      await establish(pair);
    },
  );

  test(
    'cancel during identity verification ignores the late proof and reconnects',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      final gate = pair.cryptoA.verificationGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await pair.serviceA.connect('endpoint-b');
      await pending(pair);
      await pair.serviceA.acceptConnectionRequest('endpoint-b');
      await pair.serviceB.acceptConnectionRequest('endpoint-a');
      await waitFor(
        () =>
            pair.cryptoA.verifyCalls > 0 &&
            pair.serviceB.transientConnectionCounts['completedHandshakes'] == 1,
      );
      await pair.serviceA.cancelConnection('endpoint-b');
      await cleanBoth(pair);
      gate.complete();
      pair.cryptoA.verificationGate = null;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expectClean(pair.serviceA);
      final reconnect = pair.serviceA.connect('endpoint-b');
      await pending(pair);
      await pair.serviceA.acceptConnectionRequest('endpoint-b');
      await reconnect;
      await connected(pair);
    },
  );

  test(
    'native failure and request exception fully clean state before retry',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      pair.transportA.failNextRequest = true;
      await pair.serviceA.connect('endpoint-b');
      expectClean(pair.serviceA);
      pair.transportA.holdConnectionResult = true;
      pair.transportB.holdConnectionResult = true;
      await pair.serviceA.connect('endpoint-b');
      await pending(pair);
      pair.transportA.failConnection();
      await waitFor(
        () =>
            pair.serviceA.peerStates['endpoint-b'] ==
                NearbyConnectionState.failed &&
            pair.serviceB.peerStates['endpoint-a'] ==
                NearbyConnectionState.failed,
      );
      expectClean(pair.serviceA);
      expectClean(pair.serviceB);
      pair.transportA.holdConnectionResult = false;
      pair.transportB.holdConnectionResult = false;
      await establish(pair);
    },
  );

  test(
    'cancel while native accept is pending releases the accept lock',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await pair.serviceA.connect('endpoint-b');
      await pending(pair);
      final gate = pair.transportA.acceptGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final accept = pair.serviceA.acceptConnectionRequest('endpoint-b');
      await waitFor(() => pair.transportA.acceptCalls.isNotEmpty);
      await pair.serviceA.cancelConnection('endpoint-b');
      await cleanBoth(pair);
      gate.complete();
      await accept;
      pair.transportA.acceptGate = null;
      expectClean(pair.serviceA);
      await establish(pair);
    },
  );

  test(
    'automatic first contact does not wait for an approval timeout',
    () async {
      final pair = await HandshakePair.create(
        requireBothNativeAccepts: true,
        incomingApprovalTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(pair.close);
      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () =>
            pair.serviceA.peerStates['endpoint-b'] ==
                NearbyConnectionState.connected &&
            pair.serviceB.peerStates['endpoint-a'] ==
                NearbyConnectionState.connected,
      );
      expect(pair.serviceA.pendingConnectionRequests, isEmpty);
      expect(pair.serviceB.pendingConnectionRequests, isEmpty);
    },
  );

  test(
    'request failure and cancel resume paused discovery once, keeping advertising',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await pair.serviceA.configureTransportTestMode(
        NearbyTransportTestMode.clusterPauseDiscovery,
      );
      await pair.serviceB.configureTransportTestMode(
        NearbyTransportTestMode.clusterPauseDiscovery,
      );
      await pair.serviceA.startSession();
      await pair.serviceB.startSession();
      pair.transportA.discoverPeer();
      pair.transportB.discoverPeer();
      await waitFor(() => pair.serviceA.isEndpointCurrent('endpoint-b'));
      pair.transportA.failNextRequest = true;
      await pair.serviceA.connect('endpoint-b');
      expectClean(pair.serviceA);
      expect(pair.serviceA.isDiscovering, isTrue);
      expect(pair.serviceA.isAdvertising, isTrue);
      expect(pair.transportA.startDiscoveryCalls, 2);
      expect(pair.transportA.startAdvertisingCalls, 1);
      pair.transportA.discoverPeer();
      pair.transportB.discoverPeer();
      await waitFor(() => pair.serviceA.isEndpointCurrent('endpoint-b'));
      pair.transportA.holdConnectionResult = true;
      pair.transportB.holdConnectionResult = true;
      await pair.serviceA.connect('endpoint-b');
      await pending(pair);
      expect(pair.serviceA.isDiscovering, isFalse);
      await pair.serviceA.cancelConnection('endpoint-b');
      await cleanBoth(pair);
      await pair.serviceA.startDiscovery();
      expect(pair.serviceA.isDiscovering, isTrue);
      expect(pair.serviceA.isAdvertising, isTrue);
      expect(pair.transportA.startDiscoveryCalls, 3);
      expect(pair.transportA.startAdvertisingCalls, 1);
    },
  );

  test('disconnect cancels a scheduled automatic retry', () async {
    final pair = await HandshakePair.create(requireBothNativeAccepts: true);
    addTearDown(pair.close);
    await establish(pair);
    await pair.serviceA.disconnect('endpoint-b');
    await cleanBoth(pair);
    final aInitiates =
        (await pair.cryptoA.getPublicIdentity()).fingerprint.compareTo(
          (await pair.cryptoB.getPublicIdentity()).fingerprint,
        ) <
        0;
    final initiator = aInitiates ? pair.serviceA : pair.serviceB;
    final transport = aInitiates ? pair.transportA : pair.transportB;
    transport.failNextRequest = true;
    transport.discoverPeer();
    await waitFor(
      () => initiator.transientConnectionCounts['reconnectTimers'] == 1,
    );
    await initiator.disconnect(transport.localEndpointId);
    expectClean(initiator);
    await establish(pair, approve: false);
  });

  test('hard timeout cleans state and a new attempt succeeds', () async {
    final pair = await HandshakePair.create(
      requireBothNativeAccepts: true,
      hardNegotiationTimeout: const Duration(milliseconds: 80),
    );
    addTearDown(pair.close);
    pair.transportA.holdConnectionResult = true;
    pair.transportB.holdConnectionResult = true;
    await pair.serviceA.connect('endpoint-b');
    await pending(pair);
    await pair.serviceA.acceptConnectionRequest('endpoint-b');
    await pair.serviceB.acceptConnectionRequest('endpoint-a');
    await waitFor(
      () =>
          pair.serviceA.peerStates['endpoint-b'] ==
              NearbyConnectionState.failed ||
          pair.serviceB.peerStates['endpoint-a'] ==
              NearbyConnectionState.failed,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expectClean(pair.serviceA);
    expectClean(pair.serviceB);
    pair.transportA.holdConnectionResult = false;
    pair.transportB.holdConnectionResult = false;
    await establish(pair);
  });

  test(
    'late callbacks from endpoint A leave endpoint B and its proof intact',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await establish(pair);
      await pair.serviceA.disconnect('endpoint-b');
      await cleanBoth(pair);
      pair.transportA.changeEndpointIds(
        local: 'endpoint-b-new',
        remote: 'endpoint-a-new',
      );
      pair.transportB.changeEndpointIds(
        local: 'endpoint-a-new',
        remote: 'endpoint-b-new',
      );
      pair.transportA.discoverPeer();
      pair.transportB.discoverPeer();
      await connected(pair);
      final before = pair.serviceA.transientConnectionCounts;
      for (var duplicate = 0; duplicate < 2; duplicate++) {
        pair.transportA.repeatDisconnectedCallback('endpoint-b');
        pair.transportB.repeatDisconnectedCallback('endpoint-a');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(pair.serviceA.transientConnectionCounts, before);
      expect(pair.serviceA.deviceToEndpointId['device-b'], 'endpoint-b-new');
      expect(pair.serviceB.deviceToEndpointId['device-a'], 'endpoint-a-new');
    },
  );

  test(
    'remove trust while connected preserves chat and requires consent again',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await establish(pair);
      final history = await pair.repositoriesA.conversations
          .listConversations();
      await pair.serviceA.removeTrustedPeer('device-b');
      await cleanBoth(pair);
      final saved = await pair.repositoriesA.nearbyDevices.getDevice(
        'device-b',
      );
      expect(saved?.isTrusted, isFalse);
      expect(saved?.publicIdentityFingerprint, isNull);
      expect(saved?.autoReconnectEnabled, isFalse);
      expect(
        await pair.repositoriesA.conversations.listConversations(),
        hasLength(history.length),
      );
      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () => pair.serviceA.deviceToEndpointId['device-b'] == 'endpoint-b',
      );
      final repinned = await pair.repositoriesA.nearbyDevices.getDevice(
        'device-b',
      );
      expect(repinned?.isTrusted, isTrue);
    },
  );

  test(
    'remove trust while connecting cancels pending native negotiation',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await establish(pair);
      await pair.serviceA.disconnect('endpoint-b');
      await cleanBoth(pair);
      pair.transportA.holdConnectionResult = true;
      pair.transportB.holdConnectionResult = true;
      await pair.serviceA.connect('endpoint-b');
      await waitFor(() => pair.transportA.acceptedConnections.isNotEmpty);
      await pair.serviceA.removeTrustedPeer('device-b');
      await cleanBoth(pair);
      expect(
        (await pair.repositoriesA.nearbyDevices.getDevice(
          'device-b',
        ))?.publicIdentityFingerprint,
        isNull,
      );
    },
  );

  test(
    'local state clears before a delayed native disconnect finishes',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await establish(pair);
      final gate = pair.transportA.disconnectGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final disconnect = pair.serviceA.disconnect('endpoint-b');
      expectClean(pair.serviceA);
      final reconnect = pair.serviceA.connect('endpoint-b');
      expectClean(pair.serviceA);
      gate.complete();
      await disconnect;
      pair.transportA.disconnectGate = null;
      await reconnect;
      await connected(pair);
    },
  );
}
