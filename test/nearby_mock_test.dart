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
    final identity = RelioDeviceIdentityRepository(database);
    service = NearbyService(
      transport: transport,
      messages: repositories.messages,
      conversations: repositories.conversations,
      identity: identity,
      nearbyDevices: repositories.nearbyDevices,
    );
    await service.initialize();
    addTearDown(() async {
      service.dispose();
      await database.close();
    });
  });

  test('mock discovery and connection are deterministic', () async {
    transport.simulatePeer(id: 'peer-1', name: 'Peer One');
    await Future<void>.delayed(Duration.zero);
    expect(service.discoveredPeers.single.id, 'peer-1');
    await service.connect('peer-1');
    expect(transport.peers['peer-1']?.connected, isTrue);
  });

  test(
    'message send transitions to nearbySent and then delivered by ACK',
    () async {
      await repositories.conversations.ensureConversation(
        id: 'peer-1',
        participantId: 'peer-1',
        displayName: 'Peer One',
        participantStatus: DeviceStatus.normal,
      );
      final message = await repositories.messages.createOutgoingText(
        conversationId: 'peer-1',
        senderId: 'minnie',
        senderDeviceId: await RelioDeviceIdentityRepository(
          database,
        ).getDeviceId(),
        text: 'Hello RELIO',
      );

      await service.sendMessage(message);
      expect(
        (await repositories.messages.listMessages('peer-1')).single.status,
        DeliveryStatus.nearbySent,
      );

      final sent = RelioPacket.fromBytes(transport.sentPayloads.single);
      final ack = RelioPacket.ack(
        senderDeviceId: 'peer-device',
        senderUserId: 'peer-1',
        acknowledgedPacketId: sent.packetId,
        messageId: message.id,
      );
      transport.simulateIncoming(
        peerId: 'peer-1',
        bytes: Uint8List.fromList(ack.toBytes()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        (await repositories.messages.listMessages('peer-1')).single.status,
        DeliveryStatus.delivered,
      );
    },
  );

  test(
    'incoming text is persisted and mock connection loss is observable',
    () async {
      final packet = RelioPacket.textMessage(
        senderDeviceId: 'peer-device',
        senderUserId: 'peer-1',
        messageId: 'incoming-1',
        conversationId: 'peer-1',
        text: 'รับข้อความแล้ว',
        timestamp: DateTime.now(),
      );
      transport.simulateIncoming(peerId: 'peer-1', bytes: packet.toBytes());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        (await repositories.messages.listMessages('peer-1')).single.text,
        'รับข้อความแล้ว',
      );
      expect(transport.sentPayloads, hasLength(1));

      transport.simulatePeer(id: 'peer-1', name: 'Peer One');
      await service.connect('peer-1');
      transport.simulateConnectionLoss('peer-1');
      await Future<void>.delayed(Duration.zero);
      expect(
        service.eventLog.any((item) => item.contains('disconnected')),
        isTrue,
      );
    },
  );
}
