import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/diagnostics/diagnostics_log_service.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';

import 'support/nearby_pair.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'first contact enrolls both identities after consent and survives',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);

      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
      );
      await pair.serviceB.acceptConnectionRequest('endpoint-a');
      await waitFor(
        () =>
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
            pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
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
    },
  );

  test('wrong identity signature fails closed and is attributed', () async {
    final pair = await HandshakePair.create(corruptSignatureB: true);
    addTearDown(pair.close);

    await pair.serviceA.connect('endpoint-b');
    await waitFor(
      () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
    );
    await pair.serviceB.acceptConnectionRequest('endpoint-a');
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
    'repeated unhinted incoming requests produce one consent prompt',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);

      pair.transportB.clearDiscoveredFingerprintHint();
      pair.transportB.discoverPeer();
      for (var attempt = 0; attempt < 3; attempt++) {
        pair.transportB.simulateIncomingRequest(
          name: 'Phone A',
          fingerprint: null,
        );
      }
      await waitFor(
        () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
      );
      expect(pair.transportB.acceptCalls, hasLength(1));
      expect(pair.serviceB.pendingConnectionRequests, hasLength(1));
      expect(
        pair.serviceB.identityApprovalChangesPinnedKey('endpoint-a'),
        isFalse,
      );
      final events = await readEvents(pair.logsB);
      expect(
        events.map((event) => event['event']),
        contains('incoming_prompt_suppressed_active_connection'),
      );
    },
  );

  test('changed pinned identity requires a second explicit approval', () async {
    final pair = await HandshakePair.create();
    addTearDown(pair.close);

    await pair.serviceA.connect('endpoint-b');
    await waitFor(
      () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
    );
    await pair.serviceB.acceptConnectionRequest('endpoint-a');
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
      () => pair.serviceA.pendingConnectionRequests.containsKey('endpoint-b'),
    );
    await pair.serviceA.acceptConnectionRequest('endpoint-b');
    await waitFor(
      () => pair.serviceA.identityApprovalChangesPinnedKey('endpoint-b'),
    );

    expect(
      (await pair.repositoriesA.nearbyDevices.getDevice(
        'device-b',
      ))?.publicIdentityKey,
      'test-public-key:device-b',
    );
    expect(pair.serviceA.deviceIdForEndpoint('endpoint-b'), isNull);

    await pair.serviceA.acceptConnectionRequest('endpoint-b');
    await waitFor(
      () => pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b',
    );
    expect(
      (await pair.repositoriesA.nearbyDevices.getDevice(
        'device-b',
      ))?.publicIdentityKey,
      'test-public-key:device-b-rotated',
    );
  });

  test('trusted reconnect auto-accepts only a uniquely pinned key', () async {
    final pair = await HandshakePair.create();
    addTearDown(pair.close);

    await pair.serviceA.connect('endpoint-b');
    await waitFor(
      () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
    );
    await pair.serviceB.acceptConnectionRequest('endpoint-a');
    await waitFor(
      () =>
          pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
          pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
    );
    final savedA = await pair.repositoriesB.nearbyDevices.getDevice('device-a');
    expect(savedA?.isTrusted, isTrue);
    expect(savedA?.autoReconnectEnabled, isTrue);
    if (pair.serviceB.pendingConnectionRequests.isNotEmpty) {
      fail(
        'initial B pending=${pair.serviceB.pendingConnectionRequests.keys} '
        'identityChanged=${pair.serviceB.identityApprovalChangesPinnedKey('endpoint-b')} '
        'name=${pair.serviceB.pendingConnectionRequests['endpoint-b']?.peer.name}',
      );
    }

    await pair.serviceA.disconnect('endpoint-b', reason: 'test_reconnect');
    await waitFor(
      () =>
          pair.serviceA.peerStates['endpoint-b'] ==
          NearbyConnectionState.disconnected,
    );

    pair.transportA.omitIncomingFingerprintHint = true;
    pair.transportB.discoverPeer();
    await waitFor(
      () =>
          pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
          pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a' &&
          pair.serviceA.peerStates['endpoint-b'] ==
              NearbyConnectionState.connected &&
          pair.serviceB.peerStates['endpoint-a'] ==
              NearbyConnectionState.connected,
    );

    expect(pair.transportA.acceptedConnections, contains('endpoint-b'));
    if (pair.serviceA.pendingConnectionRequests.isNotEmpty) {
      fail(
        'A pending=${pair.serviceA.pendingConnectionRequests.keys} '
        'identityChanged=${pair.serviceA.identityApprovalChangesPinnedKey('endpoint-b')} '
        'peer=${pair.serviceA.pendingConnectionRequests['endpoint-b']?.peer.name}',
      );
    }
    final reconnectEventsB = await readEvents(pair.logsB);
    if (pair.serviceB.pendingConnectionRequests.isNotEmpty) {
      fail(
        'B pending=${pair.serviceB.pendingConnectionRequests.keys} '
        'identityChanged=${pair.serviceB.identityApprovalChangesPinnedKey('endpoint-b')} '
        'request=${pair.serviceB.pendingConnectionRequests['endpoint-b']?.peer.name} '
        'events=${reconnectEventsB.where((event) => event['event'].toString().contains('prompt') || event['event'].toString().contains('approval')).map((event) => '${event['event']}:${event['peerAlias']}:${event['reason']}').toList()}',
      );
    }
    expect(
      pair.serviceA.peerStates['endpoint-b'],
      NearbyConnectionState.connected,
    );
    expect(
      pair.serviceB.peerStates['endpoint-a'],
      NearbyConnectionState.connected,
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
  });

  test(
    'simultaneous challenges do not overwrite either pending nonce',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);

      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
      );
      await pair.serviceB.acceptConnectionRequest('endpoint-a');
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
      await waitFor(
        () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
      );
      await pair.serviceB.acceptConnectionRequest('endpoint-a');
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
