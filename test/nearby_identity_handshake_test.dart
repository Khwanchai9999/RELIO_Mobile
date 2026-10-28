import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/diagnostics/diagnostics_log_service.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';

import 'support/nearby_pair.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'first contact automatically enrolls verified identities and survives',
    () async {
      final pair = await HandshakePair.create(displayNameA: 'RELIO H QA');
      addTearDown(pair.close);
      final defaultNameB = await pair.identityB.getDisplayName();
      expect(pair.serviceA.authenticatedConnectedPeers, isEmpty);
      expect(defaultNameB, matches(RegExp(r'^ผู้ใช้ RELIO \d{4}$')));

      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () =>
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
            pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
      );
      await waitFor(() async {
        final conversationsA = await pair.repositoriesA.conversations
            .listConversations();
        final conversationsB = await pair.repositoriesB.conversations
            .listConversations();
        return conversationsA.any(
              (conversation) => conversation.participantId == 'device-b',
            ) &&
            conversationsB.any(
              (conversation) => conversation.participantId == 'device-a',
            );
      });

      expect(
        pair.serviceA.authenticatedConnectedPeers.single.deviceId,
        'device-b',
      );
      expect(
        pair.serviceA.peerStates['endpoint-b'],
        NearbyConnectionState.connected,
      );
      expect(
        pair.serviceB.peerStates['endpoint-a'],
        NearbyConnectionState.connected,
      );
      expect(
        (await pair.repositoriesA.nearbyDevices.getDevice(
          'device-b',
        ))?.isTrusted,
        isTrue,
      );
      expect(
        (await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        ))?.isTrusted,
        isTrue,
      );
      expect(
        (await pair.repositoriesA.nearbyDevices.getDevice(
          'device-b',
        ))?.displayName,
        defaultNameB,
      );
      expect(
        (await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        ))?.displayName,
        'RELIO H QA',
      );
      expect(
        pair.serviceA.discoveredPeers
            .singleWhere((peer) => peer.endpointId == 'endpoint-b')
            .name,
        defaultNameB,
      );
      expect(
        pair.serviceB.discoveredPeers
            .singleWhere((peer) => peer.endpointId == 'endpoint-a')
            .name,
        'RELIO H QA',
      );

      // A native discovery refresh may expose the fingerprint alias again;
      // the completed RELIO identity must keep its canonical Profile name.
      pair.transportB.refreshPeerName('RELIO ca87603a');
      await waitFor(
        () =>
            pair.serviceA.discoveredPeers
                .singleWhere((peer) => peer.endpointId == 'endpoint-b')
                .name ==
            defaultNameB,
      );
      expect(
        pair.serviceA.discoveredPeers
            .singleWhere((peer) => peer.endpointId == 'endpoint-b')
            .name,
        defaultNameB,
      );

      expect(
        (await pair.repositoriesB.conversations.listConversations())
            .singleWhere(
              (conversation) => conversation.participantId == 'device-a',
            )
            .displayName,
        'RELIO H QA',
      );

      await pair.identityA.setDisplayName('RELIO H QA 2');
      await pair.serviceA.propagateCurrentStatus();
      await waitFor(() async {
        final savedPeer = await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        );
        final livePeer = pair.serviceB.discoveredPeers.singleWhere(
          (peer) => peer.endpointId == 'endpoint-a',
        );
        return savedPeer?.displayName == 'RELIO H QA 2' &&
            livePeer.name == 'RELIO H QA 2';
      });
      expect(
        (await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        ))?.displayName,
        'RELIO H QA 2',
      );
      expect(
        (await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        ))?.displayName,
        isNot(contains('@')),
      );

      expect(
        pair.transportA.sentPackets.where(
          (packet) => packet == 'identityChallenge',
        ),
        hasLength(1),
      );
      expect(
        pair.transportB.sentPackets.where(
          (packet) => packet == 'identityChallenge',
        ),
        hasLength(1),
      );
      final eventsA = await readEvents(pair.logsA);
      final eventsB = await readEvents(pair.logsB);
      for (final event in [
        'identity_handshake_started',
        'identity_challenge_created',
        'identity_challenge_sent',
        'identity_response_received',
        'identity_public_key_received',
        'identity_signature_verify_started',
        'identity_signature_verify_success',
        'identity_enrollment_started',
        'identity_fingerprint_pinned',
        'identity_enrollment_completed',
        'identity_handshake_completed',
        'identity_hello_sent',
        'identity_hello_received',
      ]) {
        expect(eventsA.map((entry) => entry['event']), contains(event));
        expect(eventsB.map((entry) => entry['event']), contains(event));
      }
      final stage = eventsA.firstWhere(
        (entry) => entry['event'] == 'identity_handshake_started',
      );
      expect(stage['protocolVersion'], 2);
      expect(stage['handshakeState'], 'identity_handshake_started');
      expect(stage['elapsedMs'], isA<int>());
      expect(stage['connectionTraceId'], isNotEmpty);
      expect(stage['peerAlias'], DiagnosticsLogService.peerAlias('endpoint-b'));
      expect(pair.serviceA.pendingConnectionRequests, isEmpty);
      expect(pair.serviceB.pendingConnectionRequests, isEmpty);
      expect(pair.transportB.acceptCalls, contains('endpoint-a'));
    },
  );

  test('wrong identity signature fails closed and is attributed', () async {
    final pair = await HandshakePair.create(corruptSignatureB: true);
    addTearDown(pair.close);

    await pair.serviceA.connect('endpoint-b');
    await waitFor(
      () => pair.serviceA.peerErrors['endpoint-b'] == 'identity_proof_invalid',
    );
    await pair.logsA.flush();
    final events = await readEvents(pair.logsA);
    expect(
      events.map((entry) => entry['event']),
      contains('identity_signature_verify_failed'),
    );
    expect(
      events.map((entry) => entry['event']),
      contains('identity_handshake_failed'),
    );
    expect(
      events.map((entry) => entry['event']),
      contains('disconnect_requested_by_app'),
    );
    expect(
      events.map((entry) => entry['event']),
      contains('disconnect_requested_reason'),
    );
    expect(pair.serviceA.deviceIdForEndpoint('endpoint-b'), isNull);
    expect(
      await pair.repositoriesA.nearbyDevices.getDevice('device-b'),
      isNull,
    );
  });

  test(
    'unhinted incoming requests are accepted only to verify signed identity',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);

      pair.transportB.clearDiscoveredFingerprintHint();
      // Also clear the service's cached discovery record so this truly tests
      // an incoming request with no available identity hint.
      pair.serviceB.discoveredPeers.removeWhere(
        (peer) => peer.endpointId == 'endpoint-a',
      );
      pair.transportB.discoverPeer();
      for (var attempt = 0; attempt < 3; attempt++) {
        pair.transportB.simulateIncomingRequest(
          name: 'Phone A',
          fingerprint: null,
        );
      }
      await waitFor(() => pair.transportB.acceptCalls.contains('endpoint-a'));
      expect(pair.serviceB.pendingConnectionRequests, isEmpty);
      final events = await readEvents(pair.logsB);
      expect(
        events.map((event) => event['event']),
        contains('identity_challenge_sent'),
      );
    },
  );

  test(
    'changed pinned identity is rejected without replacing the stored pin',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);

      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () => pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b',
      );
      final previous = await pair.repositoriesA.nearbyDevices.getDevice(
        'device-b',
      );
      expect(previous?.publicIdentityKey, 'test-public-key:device-b');

      await pair.serviceA.disconnect('endpoint-b', reason: 'rotate_test_key');
      pair.cryptoB.rotateIdentity();
      await pair.serviceB.connect('endpoint-a');
      await waitFor(
        () =>
            pair.serviceA.peerErrors['endpoint-b'] == 'identity_proof_invalid',
      );

      expect(
        (await pair.repositoriesA.nearbyDevices.getDevice(
          'device-b',
        ))?.publicIdentityKey,
        'test-public-key:device-b',
      );
      expect(pair.serviceA.deviceIdForEndpoint('endpoint-b'), isNull);
    },
  );

  test(
    'trusted reconnect proves identity without another approval prompt',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);

      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () =>
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
            pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
      );
      final savedA = await pair.repositoriesB.nearbyDevices.getDevice(
        'device-a',
      );
      expect(savedA?.isTrusted, isTrue);
      expect(savedA?.autoReconnectEnabled, isTrue);
      expect(pair.serviceB.pendingConnectionRequests, isEmpty);

      await pair.serviceA.disconnect('endpoint-b', reason: 'test_reconnect');
      await waitFor(
        () =>
            pair.serviceA.peerStates['endpoint-b'] ==
            NearbyConnectionState.disconnected,
      );

      pair.transportA.discoverPeer();
      pair.transportB.discoverPeer();
      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () =>
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
            pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a' &&
            pair.serviceA.peerStates['endpoint-b'] ==
                NearbyConnectionState.connected &&
            pair.serviceB.peerStates['endpoint-a'] ==
                NearbyConnectionState.connected,
      );
      expect(pair.serviceA.pendingConnectionRequests, isEmpty);
      expect(pair.serviceB.pendingConnectionRequests, isEmpty);
      expect(pair.transportA.sentPackets, contains('identityProof'));
      expect(pair.transportB.sentPackets, contains('identityProof'));
      expect(
        (await pair.repositoriesA.nearbyDevices.getDevice(
          'device-b',
        ))?.isTrusted,
        isTrue,
      );
      pair.serviceA.peerStates['unrelated-endpoint'] =
          NearbyConnectionState.connecting;
      expect(pair.serviceA.applicationState, NearbyApplicationState.connected);
      pair.serviceA.peerStates.remove('unrelated-endpoint');

      pair.serviceA.isAdvertising = true;
      pair.serviceA.isDiscovering = true;
      pair.serviceA.updateLifecycleContext(
        lifecycleState: 'resumed',
        route: '/chat/device-b',
      );
      final disconnectCountBeforeSessionStop =
          pair.transportA.disconnectCalls.length;
      await pair.serviceA.stopSession(
        reason: 'test_discovery_restart',
        caller: 'nearby_identity_handshake_test',
      );
      expect(
        pair.serviceA.peerStates['endpoint-b'],
        NearbyConnectionState.connected,
      );
      expect(
        pair.transportA.disconnectCalls,
        hasLength(disconnectCountBeforeSessionStop),
      );
      expect(pair.transportA.stopDiscoveryCalls, 1);
      expect(pair.transportA.stopAdvertisingCalls, 1);
      final stopEvents = await readEvents(pair.logsA);
      final stopEvent = stopEvents.firstWhere(
        (event) => event['event'] == 'nearby_session_stop_requested',
      );
      expect(stopEvent['caller'], 'nearby_identity_handshake_test');
      expect(stopEvent['reason'], 'test_discovery_restart');
      expect(stopEvent['screenRoute'], '/chat/device-b');
    },
  );

  test(
    'simultaneous challenges do not overwrite either pending nonce',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);

      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () =>
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
            pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
      );

      expect(pair.transportA.sentPackets, contains('identityProof'));
      expect(pair.transportB.sentPackets, contains('identityProof'));
      expect(
        pair.serviceA.peerStates['endpoint-b'],
        NearbyConnectionState.connected,
      );
      expect(
        pair.serviceB.peerStates['endpoint-a'],
        NearbyConnectionState.connected,
      );
    },
  );

  test(
    'identity timeout race is logged and attributes both disconnect sides',
    () async {
      final pair = await HandshakePair.create(
        handshakeTimeout: const Duration(milliseconds: 500),
        dropPayloads: true,
      );
      addTearDown(pair.close);

      await pair.serviceA.connect('endpoint-b');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        pair.serviceA.peerStates['endpoint-b'],
        isNot(NearbyConnectionState.connecting),
      );
      expect(
        pair.serviceB.peerStates['endpoint-a'],
        isNot(NearbyConnectionState.connecting),
      );

      final eventsA = await readEvents(pair.logsA);
      final eventsB = await readEvents(pair.logsB);
      final allEvents = [...eventsA, ...eventsB];
      expect(
        allEvents.map((event) => event['event']),
        contains('identity_handshake_timeout'),
      );
      expect(
        allEvents.map((event) => event['event']),
        contains('disconnect_requested_by_app'),
      );
      expect(
        allEvents.map((event) => event['event']),
        contains('disconnect_requested_reason'),
      );
      final nativeDisconnects = allEvents.where(
        (event) => event['event'] == 'native_endpoint_disconnected',
      );
      expect(nativeDisconnects.length, greaterThanOrEqualTo(2));
      expect(
        nativeDisconnects.map((event) => event['disconnectRequester']),
        containsAll(['app', 'nearby_or_remote']),
      );
    },
  );
}
