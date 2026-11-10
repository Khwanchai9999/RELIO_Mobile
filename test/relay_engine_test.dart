import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/diagnostics/diagnostics_log_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/relay/relay_engine.dart';
import 'package:relio_mobile/core/relay/relay_models.dart';
import 'package:relio_mobile/core/relay/relay_repository.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';

import 'test_database.dart';

void main() {
  test(
    'relay participation consent gates third-party envelope acceptance',
    () async {
      final node = await _node('device-b');
      addTearDown(node.close);
      var allowed = false;
      var secureReady = false;
      final engine = RelayEngine(
        transport: node.transport,
        identity: node.identity,
        repository: node.relay,
        relayParticipationAllowed: () async => allowed,
        secureRelayEnabled: () => secureReady,
      );
      await engine.initialize();
      RelayEnvelope envelope(String id) => RelayEnvelope.fromPayloadPacket(
        packet: RelioPacket.textMessage(
          senderDeviceId: 'device-a',
          senderUserId: 'account-a',
          messageId: id,
          conversationId: 'conversation-c',
          text: 'private text',
          timestamp: DateTime.now().toUtc(),
        ),
        destinationDeviceId: 'device-c',
      );

      final denied = envelope('consent-off');
      expect(
        await engine.handleIncomingPacket(
          'endpoint-a',
          RelioPacket.relayEnvelope(
            senderDeviceId: 'device-a',
            senderUserId: 'relay',
            relayPacketId: denied.packetId,
            relayPayload: denied.toJson(),
          ),
        ),
        RelayResult.blocked,
      );
      expect(await node.relay.packetCount(), 0);

      allowed = true;
      final blockedUntilSecure = envelope('consent-secure-protocol-off');
      expect(
        await engine.handleIncomingPacket(
          'endpoint-a',
          RelioPacket.relayEnvelope(
            senderDeviceId: 'device-a',
            senderUserId: 'relay',
            relayPacketId: blockedUntilSecure.packetId,
            relayPayload: blockedUntilSecure.toJson(),
          ),
        ),
        RelayResult.blocked,
      );
      expect(await node.relay.packetCount(), 0);

      secureReady = true;
      final accepted = envelope('consent-on');
      expect(
        await engine.handleIncomingPacket(
          'endpoint-a',
          RelioPacket.relayEnvelope(
            senderDeviceId: 'device-a',
            senderUserId: 'relay',
            relayPacketId: accepted.packetId,
            relayPayload: accepted.toJson(),
          ),
        ),
        RelayResult.stored,
      );
      expect(await node.relay.packetCount(), 1);
    },
  );

  test(
    'relay envelope keeps relay packet identity separate from payload ID',
    () {
      final packet = RelioPacket.textMessage(
        senderDeviceId: 'device-a',
        senderUserId: 'account-a',
        messageId: 'message-a',
        conversationId: 'conversation-a',
        text: 'private text',
        timestamp: DateTime.utc(2026, 1, 1),
      );
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: packet,
        destinationDeviceId: 'device-c',
      );

      expect(envelope.packetId, isNot(envelope.payloadId));
      expect(envelope.payloadId, 'message-a');
      expect(envelope.payloadType, 'textMessage');
      expect(envelope.visitedDeviceIds, ['device-a']);
      final restored = RelayEnvelope.fromJson(envelope.toJson());
      expect(restored.packetId, envelope.packetId);
      expect(restored.visitedDeviceIds, ['device-a']);
      expect(
        const RelayPolicy().validate(
          envelope.copyWith(
            visitedDeviceIds: ['device-a', 'device-b', 'device-a'],
          ),
        ),
        'invalidRoutePath',
      );
    },
  );

  test(
    'relay policy rejects a first hop that is also source or destination',
    () {
      final packet = RelioPacket.textMessage(
        senderDeviceId: 'device-a',
        senderUserId: 'device-a',
        messageId: 'invalid-first-hop',
        conversationId: 'conversation-c',
        text: 'synthetic',
        timestamp: DateTime.now().toUtc(),
      );
      final sourceLoop = RelayEnvelope.fromPayloadPacket(
        packet: packet,
        destinationDeviceId: 'device-c',
        firstHopDeviceId: 'device-a',
      );
      final destinationLoop = RelayEnvelope.fromPayloadPacket(
        packet: packet,
        destinationDeviceId: 'device-c',
        firstHopDeviceId: 'device-c',
      );

      expect(const RelayPolicy().validate(sourceLoop), 'invalidFirstHop');
      expect(const RelayPolicy().validate(destinationLoop), 'invalidFirstHop');
    },
  );

  test('QA policy raises only the Text hop ceiling', () {
    const qaPolicy = RelayPolicy(
      maxHops: RelayPolicy.qaAutomaticTextMaxHops,
      maxTextHops: RelayPolicy.qaAutomaticTextMaxHops,
    );
    final text = RelayEnvelope.fromPayloadPacket(
      packet: RelioPacket.textMessage(
        senderDeviceId: 'device-a',
        senderUserId: 'device-a',
        messageId: 'eight-hop-text',
        conversationId: 'conversation-d',
        text: 'synthetic',
        timestamp: DateTime.now().toUtc(),
      ),
      destinationDeviceId: 'device-d',
      maxHops: RelayPolicy.qaAutomaticTextMaxHops,
    );
    final sos = RelayEnvelope.fromPayloadPacket(
      packet: RelioPacket.sos(
        senderDeviceId: 'device-a',
        senderUserId: 'device-a',
        displayName: 'A',
        sosId: 'sos-eight-hop',
        message: 'help',
        latitude: 13.7,
        longitude: 100.5,
        createdAt: DateTime.now().toUtc(),
        isActive: true,
      ),
      destinationDeviceId: 'device-d',
      maxHops: RelayPolicy.qaAutomaticTextMaxHops,
    );

    expect(qaPolicy.validate(text), isNull);
    expect(qaPolicy.validate(sos), 'invalidHopCount');
    expect(const RelayPolicy().validate(text), 'invalidHopCount');
  });

  test(
    'A to B to C stores first, forwards once, and materializes only at C',
    () async {
      final a = await _node('device-a');
      final b = await _node('device-b');
      final c = await _node('device-c');
      addTearDown(() async {
        await a.close();
        await b.close();
        await c.close();
      });

      final packet =
          RelioPacket.textMessage(
            senderDeviceId: 'device-a',
            senderUserId: 'account-a',
            messageId: 'message-a',
            conversationId: 'conversation-a',
            text: 'private text',
            timestamp: DateTime.utc(2026, 1, 1),
          ).withPrincipals(
            (await a.identity.profiles.current()).principalId,
            (await c.identity.profiles.current()).principalId,
          );
      final relayLogsA = <String>[];
      final relayLogsB = <String>[];
      final relayLogsC = <String>[];
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: packet,
        destinationDeviceId: 'device-c',
        firstHopDeviceId: 'device-b',
        now: DateTime.now().toUtc(),
      );

      final engineA = RelayEngine(
        transport: a.transport,
        identity: a.identity,
        repository: a.relay,
        diagnostics: DiagnosticsLogService(qaLogcatSink: relayLogsA.add),
        connectedPeers: () => [
          const NearbyPeer(
            id: 'endpoint-b',
            name: 'B',
            connected: true,
            deviceId: 'device-b',
            capabilities: ['relay-v1'],
          ),
        ],
      );
      final engineB = RelayEngine(
        transport: b.transport,
        identity: b.identity,
        repository: b.relay,
        messages: b.repositories.messages,
        conversations: b.repositories.conversations,
        diagnostics: DiagnosticsLogService(qaLogcatSink: relayLogsB.add),
        connectedPeers: () => [
          const NearbyPeer(
            id: 'endpoint-a',
            name: 'A',
            connected: true,
            deviceId: 'device-a',
            capabilities: ['relay-v1'],
          ),
          const NearbyPeer(
            id: 'endpoint-c',
            name: 'C',
            connected: true,
            deviceId: 'device-c',
            capabilities: ['relay-v1'],
          ),
        ],
      );
      final engineC = RelayEngine(
        transport: c.transport,
        identity: c.identity,
        repository: c.relay,
        messages: c.repositories.messages,
        conversations: c.repositories.conversations,
        diagnostics: DiagnosticsLogService(qaLogcatSink: relayLogsC.add),
      );
      await engineA.initialize();
      await engineB.initialize();
      await engineC.initialize();

      expect(await engineA.enqueueEnvelope(envelope), RelayResult.stored);
      final sentToB = _relayBytes(a.transport);
      expect(sentToB, isNotEmpty);
      expect(await b.relay.packetCount(), 0);

      await engineB.handleIncomingBytes('endpoint-a', sentToB.single);
      expect(await b.relay.packetCount(), 1);
      expect(
        (await b.relay.getPacket(envelope.packetId))!.envelope.firstHopDeviceId,
        isNull,
      );
      final storedAck = b.transport.sentPayloads
          .map(RelioPacket.fromBytes)
          .where((item) => item.type == RelioPacketType.relayAck)
          .single;
      expect(storedAck.payload['status'], 'stored');
      expect(
        await engineA.handleIncomingPacket('endpoint-b', storedAck),
        RelayResult.stored,
      );
      expect(
        (await a.relay.getPacket(envelope.packetId))?.state,
        isNot(RelayPacketState.delivered),
      );
      expect(
        await b.repositories.messages.listMessages('conversation-a'),
        isEmpty,
      );
      final sentToC = _relayBytes(b.transport);
      expect(sentToC, isNotEmpty);

      await engineC.handleIncomingBytes('endpoint-b', sentToC.single);
      expect(
        (await c.repositories.messages.listMessages(
          'conversation-a',
        )).single.text,
        'private text',
      );
      expect(await c.relay.packetCount(), 1);
      expect(await c.repositories.syncQueue.listAll(), isEmpty);

      final correlationAlias = DiagnosticsLogService.peerAlias(
        envelope.payloadId,
      );
      expect(
        relayLogsA.any(
          (line) =>
              line.contains('forward_sent') &&
              line.contains('payloadAlias') &&
              line.contains(correlationAlias) &&
              line.contains('"hopCount":1'),
        ),
        isTrue,
      );
      expect(
        relayLogsB.any(
          (line) =>
              line.contains('envelope_stored') &&
              line.contains(correlationAlias) &&
              line.contains('"hopCount":1') &&
              line.contains(DiagnosticsLogService.peerAlias('device-a')),
        ),
        isTrue,
      );
      expect(
        relayLogsB.any(
          (line) =>
              line.contains('forward_sent') &&
              line.contains(correlationAlias) &&
              line.contains('"hopCount":2') &&
              line.contains(DiagnosticsLogService.peerAlias('device-c')),
        ),
        isTrue,
      );
      expect(
        relayLogsC.any(
          (line) =>
              line.contains('payload_delivered') &&
              line.contains(correlationAlias) &&
              line.contains('"hopCount":2') &&
              line.contains(DiagnosticsLogService.peerAlias('device-b')),
        ),
        isTrue,
      );
      expect(
        [...relayLogsA, ...relayLogsB, ...relayLogsC].join('\n'),
        isNot(contains('private text')),
      );

      final recipientAck = c.transport.sentPayloads
          .map(RelioPacket.fromBytes)
          .where((item) => item.type == RelioPacketType.relayAck)
          .single;
      expect(recipientAck.payload['relayPacketId'], envelope.packetId);
      expect(recipientAck.payload['status'], 'delivered');
      await engineB.handleIncomingPacket('endpoint-c', recipientAck);
      expect(
        (await b.relay.getForwardRecord(envelope.packetId, 'device-c'))?.status,
        'delivered',
      );
      expect(
        relayLogsC.any(
          (line) =>
              line.contains('ack_sent') &&
              line.contains('"ackStatus":"delivered"') &&
              line.contains(correlationAlias),
        ),
        isTrue,
      );
      expect(
        relayLogsB.any(
          (line) =>
              line.contains('ack_received') &&
              line.contains('"ackStatus":"delivered"') &&
              line.contains(correlationAlias),
        ),
        isTrue,
      );

      if (RelioBuildInfo.isTest) {
        final propagatedAck = b.transport.sentPayloads
            .map(RelioPacket.fromBytes)
            .where(
              (item) =>
                  item.type == RelioPacketType.relayAck &&
                  item.payload['status'] == 'delivered',
            )
            .single;
        expect(
          await engineA.handleIncomingPacket('endpoint-b', propagatedAck),
          RelayResult.delivered,
        );
        expect(
          (await a.relay.getPacket(envelope.packetId))?.state,
          RelayPacketState.delivered,
        );
        await engineA.handleIncomingPacket('endpoint-b', storedAck);
        expect(
          (await a.relay.getPacket(envelope.packetId))?.state,
          RelayPacketState.delivered,
        );
        expect(
          await engineA.handleIncomingPacket('unknown-endpoint', propagatedAck),
          RelayResult.blocked,
        );
      }

      await engineB.handleIncomingBytes('endpoint-a', sentToB.single);
      expect(await b.relay.packetCount(), 1);
      expect(
        await b.repositories.messages.listMessages('conversation-a'),
        isEmpty,
      );
    },
  );

  test(
    'relay rejects an envelope whose path has already visited this device',
    () async {
      final b = await _node('device-b');
      addTearDown(b.close);
      final packet = RelioPacket.textMessage(
        senderDeviceId: 'device-a',
        senderUserId: 'account-a',
        messageId: 'looped-message',
        conversationId: 'conversation-a',
        text: 'loop guard fixture',
        timestamp: DateTime.now().toUtc(),
      );
      final envelope =
          RelayEnvelope.fromPayloadPacket(
            packet: packet,
            destinationDeviceId: 'device-d',
            maxHops: RelayPolicy.qaAutomaticTextMaxHops,
          ).copyWith(
            hopCount: 2,
            previousHopDeviceId: 'device-c',
            visitedDeviceIds: const ['device-a', 'device-b', 'device-c'],
          );
      final incoming = RelioPacket.relayEnvelope(
        senderDeviceId: 'device-c',
        senderUserId: 'relay',
        relayPacketId: envelope.packetId,
        relayPayload: envelope.toJson(),
      );
      final engine = RelayEngine(
        transport: b.transport,
        identity: b.identity,
        repository: b.relay,
        connectedPeers: () => const [
          NearbyPeer(
            id: 'endpoint-d',
            name: 'D',
            connected: true,
            deviceId: 'device-d',
            capabilities: ['relay-v1'],
          ),
        ],
      );
      await engine.initialize();

      expect(
        await engine.handleIncomingPacket('endpoint-c', incoming),
        RelayResult.blocked,
      );
      expect(_relayBytes(b.transport), isEmpty);
      expect(
        (await b.relay.getPacket(envelope.packetId))?.state,
        RelayPacketState.blocked,
      );
      await engine.dispose();
    },
  );

  test('enqueuePayload sends through the sole eligible relay peer', () async {
    final a = await _node('device-a');
    addTearDown(a.close);
    final localProfile = await a.identity.profiles.current();
    final packet = RelioPacket.textMessage(
      senderDeviceId: 'device-a',
      senderUserId: 'device-a',
      messageId: 'relay-probe-message',
      conversationId: 'conversation-c',
      text: 'RELIO QA RELAY TEST relay-probe-message',
      timestamp: DateTime.now().toUtc(),
    ).withPrincipals(localProfile.principalId, 'guest:recipient-c');
    final engine = RelayEngine(
      transport: a.transport,
      identity: a.identity,
      repository: a.relay,
      connectedPeers: () => [
        const NearbyPeer(
          id: 'endpoint-b',
          name: 'B',
          connected: true,
          deviceId: 'device-b',
          capabilities: ['relay-v1'],
        ),
      ],
    );
    await engine.initialize();

    expect(
      await engine.enqueuePayload(packet, destinationDeviceId: 'device-c'),
      RelayResult.stored,
    );
    final sent = _relayBytes(a.transport);
    expect(sent, hasLength(1));
    final forwarded = RelayEnvelope.fromJson(
      RelioPacket.fromBytes(sent.single).payload.cast<String, dynamic>(),
    );
    expect(forwarded.destinationDeviceId, 'device-c');
    expect(forwarded.hopCount, 1);
    expect(forwarded.previousHopDeviceId, 'device-a');
    expect(
      (await a.relay.getPacket(forwarded.packetId))?.state,
      RelayPacketState.forwarded,
    );
  });

  test(
    'packet-scoped first hop sends to B even when C is directly connected',
    () async {
      final a = await _node('device-a');
      addTearDown(a.close);
      final packet = RelioPacket.textMessage(
        senderDeviceId: 'device-a',
        senderUserId: 'device-a',
        messageId: 'scoped-route-message',
        conversationId: 'conversation-c',
        text: 'synthetic scoped route',
        timestamp: DateTime.now().toUtc(),
      );
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: packet,
        destinationDeviceId: 'device-c',
        firstHopDeviceId: 'device-b',
      );
      final engine = RelayEngine(
        transport: a.transport,
        identity: a.identity,
        repository: a.relay,
        connectedPeers: () => const [
          NearbyPeer(
            id: 'endpoint-b',
            name: 'B',
            connected: true,
            deviceId: 'device-b',
            capabilities: ['relay-v1'],
          ),
          NearbyPeer(
            id: 'endpoint-c',
            name: 'C',
            connected: true,
            deviceId: 'device-c',
            capabilities: ['relay-v1'],
          ),
        ],
      );
      await engine.initialize();

      await engine.enqueueEnvelope(envelope);
      await engine.forwardPending();

      expect(a.transport.sentPeerIds, ['endpoint-b']);
      final firstHop = RelayEnvelope.fromJson(
        RelioPacket.fromBytes(
          _relayBytes(a.transport).single,
        ).payload.cast<String, dynamic>(),
      );
      expect(firstHop.hopCount, 1);
      expect(firstHop.previousHopDeviceId, 'device-a');
      expect(firstHop.firstHopDeviceId, isNull);
    },
  );

  test(
    'packet-scoped first hop never falls back to direct destination',
    () async {
      final a = await _node('device-a');
      addTearDown(a.close);
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: RelioPacket.textMessage(
          senderDeviceId: 'device-a',
          senderUserId: 'device-a',
          messageId: 'blocked-scoped-route',
          conversationId: 'conversation-c',
          text: 'synthetic scoped route',
          timestamp: DateTime.now().toUtc(),
        ),
        destinationDeviceId: 'device-c',
        firstHopDeviceId: 'device-b',
      );
      final engine = RelayEngine(
        transport: a.transport,
        identity: a.identity,
        repository: a.relay,
        connectedPeers: () => const [
          NearbyPeer(
            id: 'endpoint-c',
            name: 'C',
            connected: true,
            deviceId: 'device-c',
            capabilities: ['relay-v1'],
          ),
        ],
      );
      await engine.initialize();

      await engine.enqueueEnvelope(envelope);

      expect(a.transport.sentPayloads, isEmpty);
      expect(
        (await a.relay.getPacket(envelope.packetId))?.state,
        RelayPacketState.stored,
      );
    },
  );

  test(
    'ordinary relay still prefers a directly connected destination',
    () async {
      final a = await _node('device-a');
      addTearDown(a.close);
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: RelioPacket.textMessage(
          senderDeviceId: 'device-a',
          senderUserId: 'device-a',
          messageId: 'normal-route-message',
          conversationId: 'conversation-c',
          text: 'ordinary relay',
          timestamp: DateTime.now().toUtc(),
        ),
        destinationDeviceId: 'device-c',
      );
      final engine = RelayEngine(
        transport: a.transport,
        identity: a.identity,
        repository: a.relay,
        connectedPeers: () => const [
          NearbyPeer(
            id: 'endpoint-b',
            name: 'B',
            connected: true,
            deviceId: 'device-b',
            capabilities: ['relay-v1'],
          ),
          NearbyPeer(
            id: 'endpoint-c',
            name: 'C',
            connected: true,
            deviceId: 'device-c',
            capabilities: ['relay-v1'],
          ),
        ],
      );
      await engine.initialize();

      await engine.enqueueEnvelope(envelope);

      expect(a.transport.sentPeerIds, ['endpoint-c']);
    },
  );

  test(
    'TEST-only route API pins the selected intermediate when direct C exists',
    () async {
      final a = await _node('device-a');
      addTearDown(a.close);
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: RelioPacket.textMessage(
          senderDeviceId: 'device-a',
          senderUserId: 'device-a',
          messageId: 'qa-route-api-message',
          conversationId: 'conversation-c',
          text: 'synthetic QA route',
          timestamp: DateTime.now().toUtc(),
        ),
        destinationDeviceId: 'device-c',
      );
      final engine = RelayEngine(
        transport: a.transport,
        identity: a.identity,
        repository: a.relay,
        connectedPeers: () => const [
          NearbyPeer(
            id: 'endpoint-b',
            name: 'B',
            connected: true,
            deviceId: 'device-b',
            capabilities: ['relay-v1'],
          ),
          NearbyPeer(
            id: 'endpoint-c',
            name: 'C',
            connected: true,
            deviceId: 'device-c',
            capabilities: ['relay-v1'],
          ),
        ],
      );
      await engine.initialize();

      expect(RelioBuildInfo.isTest, isTrue);
      await engine.enqueueQaEnvelopeVia(envelope, firstHopDeviceId: 'device-b');
      expect(a.transport.sentPeerIds, ['endpoint-b']);
    },
    skip: !RelioBuildInfo.isTest,
  );

  test('expired relay data stays local and is not forwarded', () async {
    final node = await _node('device-b');
    addTearDown(node.close);
    final packet = RelioPacket.textMessage(
      senderDeviceId: 'device-a',
      senderUserId: 'account-a',
      messageId: 'expired-message',
      conversationId: 'conversation-a',
      text: 'expired',
      timestamp: DateTime.utc(2026, 1, 1),
    );
    final envelope = RelayEnvelope.fromPayloadPacket(
      packet: packet,
      destinationDeviceId: 'device-c',
      now: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      ttl: const Duration(minutes: 1),
    );
    final engine = RelayEngine(
      transport: node.transport,
      identity: node.identity,
      repository: node.relay,
      connectedPeers: () => [
        const NearbyPeer(
          id: 'endpoint-c',
          name: 'C',
          connected: true,
          deviceId: 'device-c',
          capabilities: ['relay-v1'],
        ),
      ],
    );
    await engine.initialize();
    expect(await engine.enqueueEnvelope(envelope), RelayResult.expired);
    expect(_relayBytes(node.transport), isEmpty);
    expect(
      (await node.relay.getPacket(envelope.packetId))?.state,
      RelayPacketState.expired,
    );
  });

  test('SOS and location relay preserve origin and capture metadata', () async {
    final node = await _node('device-c');
    addTearDown(node.close);
    final engine = RelayEngine(
      transport: node.transport,
      identity: node.identity,
      repository: node.relay,
      messages: node.repositories.messages,
      conversations: node.repositories.conversations,
      sos: node.repositories.sos,
      verifyRelayedOrigin: (envelope, packet) async =>
          packet.senderDeviceId == envelope.originDeviceId,
    );
    await engine.initialize();
    final capturedAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 3),
    );
    final sosPacket = RelioPacket.sos(
      senderDeviceId: 'device-a',
      senderUserId: 'account-a',
      displayName: 'A',
      sosId: 'sos-a',
      message: 'need help',
      latitude: 13.7,
      longitude: 100.5,
      accuracyMeters: 12.5,
      locationCapturedAt: capturedAt,
      createdAt: capturedAt,
      isActive: true,
    );
    final sosEnvelope = RelayEnvelope.fromPayloadPacket(
      packet: sosPacket,
      destinationDeviceId: 'device-c',
      now: DateTime.now().toUtc(),
    );
    expect(
      await engine.handleIncomingBytes(
        'endpoint-a',
        Uint8List.fromList(
          RelioPacket.relayEnvelope(
            senderDeviceId: 'device-a',
            senderUserId: 'account-a',
            relayPacketId: sosEnvelope.packetId,
            relayPayload: sosEnvelope.toJson(),
          ).toBytes(),
        ),
      ),
      RelayResult.delivered,
    );
    final storedSos = await node.repositories.sos.getById('sos-a');
    expect(storedSos?.ownerDeviceId, 'device-a');
    expect(
      storedSos?.locationCapturedAt?.toUtc().difference(capturedAt).inSeconds,
      0,
    );
    expect(storedSos?.locationAccuracy, 12.5);

    final locationPacket =
        RelioPacket.locationMessage(
          senderDeviceId: 'device-a',
          senderUserId: 'account-a',
          messageId: 'location-a',
          conversationId: 'conversation-a',
          latitude: 13.71,
          longitude: 100.51,
          capturedAt: capturedAt,
          accuracyMeters: 9.0,
        ).withPrincipals(
          'guest:device-a',
          (await node.identity.profiles.current()).principalId,
        );
    final locationEnvelope = RelayEnvelope.fromPayloadPacket(
      packet: locationPacket,
      destinationDeviceId: 'device-c',
      now: DateTime.now().toUtc(),
    );
    await engine.handleIncomingBytes(
      'endpoint-a',
      Uint8List.fromList(
        RelioPacket.relayEnvelope(
          senderDeviceId: 'device-a',
          senderUserId: 'account-a',
          relayPacketId: locationEnvelope.packetId,
          relayPayload: locationEnvelope.toJson(),
        ).toBytes(),
      ),
    );
    final storedLocation = await node.repositories.messages.getMessage(
      'location-a',
    );
    expect(storedLocation?.latitude, 13.71);
    expect(storedLocation?.longitude, 100.51);
  });

  test(
    'QA middle hold survives engine restart and forwards the stored envelope once',
    () async {
      final node = await _node('device-b');
      addTearDown(node.close);
      var paused = true;
      RelayEngine createEngine() => RelayEngine(
        transport: node.transport,
        identity: node.identity,
        repository: node.relay,
        qaTextForwardingPaused: () => paused,
        deviceIdForEndpoint: (endpoint) =>
            endpoint == 'endpoint-a' ? 'device-a' : 'device-c',
        connectedPeers: () => const [
          NearbyPeer(
            id: 'endpoint-c',
            name: 'C',
            connected: true,
            deviceId: 'device-c',
            capabilities: ['relay-v1'],
          ),
        ],
      );
      var engine = createEngine();
      await engine.initialize();
      final payload = RelioPacket.textMessage(
        senderDeviceId: 'device-a',
        senderUserId: 'relay',
        messageId: 'held-text',
        conversationId: 'synthetic',
        text: 'synthetic',
        timestamp: DateTime.now().toUtc(),
      );
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: payload,
        destinationDeviceId: 'device-c',
        maxHops: 2,
      ).copyWith(hopCount: 1, previousHopDeviceId: 'device-a');
      final wire = RelioPacket.relayEnvelope(
        senderDeviceId: 'device-a',
        senderUserId: 'relay',
        relayPacketId: envelope.packetId,
        relayPayload: envelope.toJson(),
      );
      await engine.handleIncomingPacket('endpoint-a', wire);
      expect(
        (await node.relay.getPacket(envelope.packetId))?.state,
        RelayPacketState.stored,
      );
      expect(_relayBytes(node.transport), isEmpty);
      expect(
        node.transport.sentPayloads
            .map(RelioPacket.fromBytes)
            .where((p) => p.type == RelioPacketType.relayAck)
            .single
            .payload['status'],
        'stored',
      );
      await engine.dispose();
      engine = createEngine();
      await engine.initialize();
      expect(_relayBytes(node.transport), isEmpty);
      paused = false;
      await engine.forwardPending();
      await engine.forwardPending();
      expect(_relayBytes(node.transport), hasLength(1));
      expect(
        RelioPacket.fromBytes(
          _relayBytes(node.transport).single,
        ).payload['hopCount'],
        2,
      );
      await engine.handleIncomingPacket('endpoint-a', wire);
      expect(_relayBytes(node.transport), hasLength(1));
      expect(await node.relay.packetCount(), 1);
      await engine.dispose();
    },
    skip: !RelioBuildInfo.isTest ? 'QA-only controlled forwarding hold' : false,
  );

  test(
    'QA delivered receipt survives absent upstream and middle restart',
    () async {
      final node = await _node('device-b');
      addTearDown(node.close);
      var upstream = false;
      var authenticated = false;
      var endpoint = 'endpoint-a';
      RelayEngine createEngine() => RelayEngine(
        transport: node.transport,
        identity: node.identity,
        repository: node.relay,
        receiptPeers: () => upstream && authenticated
            ? [
                NearbyPeer(
                  id: endpoint,
                  name: 'A',
                  connected: true,
                  deviceId: 'device-a',
                ),
              ]
            : [],
        connectedPeers: () => upstream
            ? [
                NearbyPeer(
                  id: endpoint,
                  name: 'A',
                  connected: true,
                  deviceId: 'device-a',
                ),
              ]
            : [],
      );
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: RelioPacket.textMessage(
          senderDeviceId: 'device-a',
          senderUserId: 'relay',
          messageId: 'receipt-after-restart',
          conversationId: 'synthetic',
          text: 'synthetic',
          timestamp: DateTime.now().toUtc(),
        ),
        destinationDeviceId: 'device-c',
        maxHops: 2,
      ).copyWith(hopCount: 1, previousHopDeviceId: 'device-a');
      await node.relay.storePacket(envelope);
      var engine = createEngine();
      await engine.initialize();
      await engine.forwardPending();
      expect(node.transport.sentPayloads, isEmpty); // stored is not delivered
      await node.relay.updatePacketState(
        envelope.packetId,
        RelayPacketState.delivered,
      );
      await engine.forwardPending();
      expect(node.transport.sentPayloads, isEmpty);
      await engine.dispose();
      engine = createEngine();
      await engine.initialize();
      upstream = true;
      await engine.forwardPending();
      expect(node.transport.sentPayloads, isEmpty);
      authenticated = true;
      node.transport.failSends = true;
      await engine.forwardPending();
      node.transport.failSends = false;
      await engine.forwardPending();
      await engine.forwardPending();
      expect(node.transport.sentPayloads, hasLength(1));
      final ack = RelioPacket.fromBytes(node.transport.sentPayloads.single);
      expect(ack.type, RelioPacketType.relayAck);
      expect(ack.payload['status'], 'delivered');
      expect(ack.payload['relayPacketId'], envelope.packetId);
      expect(_relayBytes(node.transport), isEmpty);
      endpoint = 'fresh-endpoint-a';
      await engine.forwardPending();
      expect(node.transport.sentPayloads, hasLength(2));
      expect(
        await node.relay.listDeliveredTextReceipts(
          envelope.expiresAt.add(const Duration(seconds: 1)),
        ),
        isEmpty,
      );
      expect(await node.relay.packetCount(), 1);
      await engine.dispose();
    },
    skip: !RelioBuildInfo.isTest ? 'QA-only receipt recovery' : false,
  );

  test('failed forwarding can retry from persistent history', () async {
    final node = await _node('device-a');
    addTearDown(node.close);
    node.transport.failSends = true;
    final engine = RelayEngine(
      transport: node.transport,
      identity: node.identity,
      repository: node.relay,
      connectedPeers: () => [
        const NearbyPeer(
          id: 'endpoint-b',
          name: 'B',
          connected: true,
          deviceId: 'device-b',
          capabilities: ['relay-v1'],
        ),
      ],
    );
    await engine.initialize();
    final packet = RelioPacket.textMessage(
      senderDeviceId: 'device-a',
      senderUserId: 'account-a',
      messageId: 'retry-message',
      conversationId: 'conversation-a',
      text: 'retry',
      timestamp: DateTime.now(),
    );
    final envelope = RelayEnvelope.fromPayloadPacket(
      packet: packet,
      destinationDeviceId: 'device-c',
    );
    await engine.enqueueEnvelope(envelope);
    final failed = await node.relay.getForwardRecord(
      envelope.packetId,
      'device-b',
    );
    expect(failed?.status, 'failed');
    node.transport.failSends = false;
    await engine.forwardPending();
    expect(_relayBytes(node.transport), hasLength(1));
    expect(
      (await node.relay.getForwardRecord(
        envelope.packetId,
        'device-b',
      ))?.status,
      'sent',
    );
  });

  test('media payloads are rejected by the relay policy', () {
    final packet = RelioPacket.mediaMetadata(
      senderDeviceId: 'device-a',
      senderUserId: 'account-a',
      messageId: 'message-a',
      attachmentId: 'attachment-a',
      transferId: 'transfer-a',
      mediaType: 'image',
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
      byteSize: 100,
    );
    expect(
      () => RelayEnvelope.fromPayloadPacket(
        packet: packet,
        destinationDeviceId: 'device-c',
      ),
      throwsArgumentError,
    );
  });
}

class _Node {
  _Node(this.database, this.repositories, this.identity, this.transport)
    : relay = DriftRelayRepository(database);

  final AppDatabase database;
  final RelioRepositories repositories;
  final RelioDeviceIdentityRepository identity;
  final MockNearbyTransport transport;
  final DriftRelayRepository relay;

  Future<void> close() async {
    await transport.dispose();
    await database.close();
  }
}

Future<_Node> _node(String deviceId) async {
  final database = createTestDatabase();
  final repositories = RelioRepositories(database);
  final identity = RelioDeviceIdentityRepository(database);
  final transport = MockNearbyTransport();
  await database
      .into(database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'device_id',
          value: deviceId,
          updatedAt: DateTime.now(),
        ),
      );
  return _Node(database, repositories, identity, transport);
}

List<Uint8List> _relayBytes(MockNearbyTransport transport) => transport
    .sentPayloads
    .where(
      (bytes) =>
          RelioPacket.fromBytes(bytes).type == RelioPacketType.relayEnvelope,
    )
    .toList(growable: false);
