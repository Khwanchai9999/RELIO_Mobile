import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  late AppDatabase database;
  late RelioRepositories repositories;
  late MockNearbyTransport transport;
  late NearbyService service;

  setUp(() async {
    database = AppDatabase.memory();
    repositories = RelioRepositories(database);
    transport = MockNearbyTransport();
    service = NearbyService(
      transport: transport,
      messages: repositories.messages,
      conversations: repositories.conversations,
      identity: RelioDeviceIdentityRepository(database),
      nearbyDevices: repositories.nearbyDevices,
      sos: repositories.sos,
      settings: repositories.settings,
    );
    await service.initialize();
    addTearDown(() async {
      await service.close();
      await database.close();
    });
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test(
    'connection performs hello and maps endpoint to RELIO device identity',
    () async {
      transport.simulatePeer(id: 'endpoint-a', name: 'Peer A');
      await settle();
      await service.connect('endpoint-a');
      await settle();

      expect(transport.sentPayloads, isNotEmpty);
      expect(
        RelioPacket.fromBytes(transport.sentPayloads.first).type,
        RelioPacketType.hello,
      );

      transport.simulateIncoming(
        peerId: 'endpoint-a',
        bytes: RelioPacket.hello(
          senderDeviceId: 'device-peer-a',
          senderUserId: 'peer-a',
          displayName: 'Peer A',
          status: DeviceStatus.rescue,
        ).toBytes(),
      );
      await settle();

      expect(service.deviceIdForEndpoint('endpoint-a'), 'device-peer-a');
      expect(
        (await repositories.nearbyDevices.listDevices()).single.status,
        DeviceStatus.rescue,
      );
    },
  );

  test(
    'outgoing and incoming text use direct peer routing and ACK idempotently',
    () async {
      await repositories.conversations.ensureConversation(
        id: 'conversation-a',
        participantId: 'device-peer-a',
        displayName: 'Peer A',
        participantStatus: DeviceStatus.normal,
      );
      transport.simulatePeer(id: 'endpoint-a', name: 'Peer A');
      await settle();
      await service.connect('endpoint-a');
      await settle();
      transport.simulateIncoming(
        peerId: 'endpoint-a',
        bytes: RelioPacket.hello(
          senderDeviceId: 'device-peer-a',
          senderUserId: 'peer-a',
          displayName: 'Peer A',
        ).toBytes(),
      );
      await settle();

      final message = await repositories.messages.createOutgoingText(
        conversationId: 'conversation-a',
        senderId: 'minnie',
        senderDeviceId: await RelioDeviceIdentityRepository(
          database,
        ).getDeviceId(),
        text: 'Hello RELIO',
      );
      await service.sendMessage(message);
      expect(
        (await repositories.messages.getMessage(message.id))?.status,
        DeliveryStatus.nearbySent,
      );

      final sentText = transport.sentPayloads
          .map(RelioPacket.fromBytes)
          .where((packet) => packet.type == RelioPacketType.textMessage)
          .single;
      expect(sentText.payload['text'], 'Hello RELIO');

      final incoming = RelioPacket.textMessage(
        senderDeviceId: 'device-peer-a',
        senderUserId: 'peer-a',
        messageId: 'incoming-1',
        conversationId: 'conversation-a',
        text: 'รับแล้ว',
        timestamp: DateTime.now(),
      );
      transport.simulateIncoming(
        peerId: 'endpoint-a',
        bytes: incoming.toBytes(),
      );
      transport.simulateIncoming(
        peerId: 'endpoint-a',
        bytes: incoming.toBytes(),
      );
      await settle();
      expect(
        (await repositories.messages.listMessages(
          'conversation-a',
        )).where((item) => item.id == 'incoming-1'),
        hasLength(1),
      );

      final ack = RelioPacket.ack(
        senderDeviceId: 'device-peer-a',
        senderUserId: 'peer-a',
        acknowledgedPacketId: sentText.packetId,
        messageId: message.id,
      );
      transport.simulateIncoming(
        peerId: 'endpoint-a',
        bytes: Uint8List.fromList(ack.toBytes()),
      );
      transport.simulateIncoming(
        peerId: 'endpoint-a',
        bytes: Uint8List.fromList(ack.toBytes()),
      );
      await settle();
      expect(
        (await repositories.messages.getMessage(message.id))?.status,
        DeliveryStatus.delivered,
      );
    },
  );

  test('incoming SOS is persisted once and updates the peer status', () async {
    transport.simulatePeer(id: 'endpoint-sos', name: 'SOS Peer');
    await settle();
    await service.connect('endpoint-sos');
    await settle();
    final packet = RelioPacket.sos(
      senderDeviceId: 'device-sos',
      senderUserId: 'sos-user',
      displayName: 'SOS Peer',
      sosId: 'sos-1',
      message: 'need help',
      createdAt: DateTime.now(),
      isActive: true,
    );
    transport.simulateIncoming(peerId: 'endpoint-sos', bytes: packet.toBytes());
    transport.simulateIncoming(peerId: 'endpoint-sos', bytes: packet.toBytes());
    await settle();

    expect((await repositories.sos.getById('sos-1'))?.isActive, isTrue);
    expect((await repositories.sos.getById('sos-1'))?.message, 'need help');
    expect(
      (await repositories.nearbyDevices.listDevices()).single.status,
      DeviceStatus.sos,
    );
  });

  test('send failure keeps the message locally and marks it failed', () async {
    await repositories.conversations.ensureConversation(
      id: 'peer-fail',
      participantId: 'peer-fail',
      displayName: 'Peer Fail',
      participantStatus: DeviceStatus.normal,
    );
    transport.failSends = true;
    final message = await repositories.messages.createOutgoingText(
      conversationId: 'peer-fail',
      senderId: 'minnie',
      senderDeviceId: 'device-local',
      text: 'must not disappear',
    );
    await service.sendMessage(message);

    final stored = await repositories.messages.getMessage(message.id);
    expect(stored?.text, 'must not disappear');
    expect(stored?.status, DeliveryStatus.failed);
  });
}
