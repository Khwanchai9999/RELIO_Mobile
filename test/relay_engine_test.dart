import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/relay/relay_engine.dart';
import 'package:relio_mobile/core/relay/relay_models.dart';
import 'package:relio_mobile/core/relay/relay_repository.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';

void main() {
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
      expect(
        RelayEnvelope.fromJson(envelope.toJson()).packetId,
        envelope.packetId,
      );
    },
  );

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
        now: DateTime.now().toUtc(),
      );

      final engineA = RelayEngine(
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
      final engineB = RelayEngine(
        transport: b.transport,
        identity: b.identity,
        repository: b.relay,
        messages: b.repositories.messages,
        conversations: b.repositories.conversations,
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
      final engineC = RelayEngine(
        transport: c.transport,
        identity: c.identity,
        repository: c.relay,
        messages: c.repositories.messages,
        conversations: c.repositories.conversations,
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

      await engineB.handleIncomingBytes('endpoint-a', sentToB.single);
      expect(await b.relay.packetCount(), 1);
      expect(
        await b.repositories.messages.listMessages('conversation-a'),
        isEmpty,
      );
    },
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

    final locationPacket = RelioPacket.locationMessage(
      senderDeviceId: 'device-a',
      senderUserId: 'account-a',
      messageId: 'location-a',
      conversationId: 'conversation-a',
      latitude: 13.71,
      longitude: 100.51,
      capturedAt: capturedAt,
      accuracyMeters: 9.0,
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
  final database = AppDatabase.memory();
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
