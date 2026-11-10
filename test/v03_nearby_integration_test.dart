import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'support/recording_notifications.dart';

import 'support/principal_packets.dart';

void main() {
  late AppDatabase database;
  late RelioRepositories repositories;
  late MockNearbyTransport transport;
  late NearbyService service;
  late RecordingNotifications notifications;

  setUp(() async {
    database = AppDatabase.memory();
    repositories = RelioRepositories(database);
    transport = MockNearbyTransport();
    notifications = RecordingNotifications();
    service = NearbyService(
      transport: transport,
      messages: repositories.messages,
      conversations: repositories.conversations,
      identity: RelioDeviceIdentityRepository(database),
      nearbyDevices: repositories.nearbyDevices,
      sos: repositories.sos,
      settings: repositories.settings,
      localNotifications: notifications,
    );
    await service.initialize();
    addTearDown(() async {
      await service.close();
      await database.close();
    });
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('replays the latest inactive SOS tombstone after reconnect', () async {
    final localDeviceId = await RelioDeviceIdentityRepository(
      database,
    ).getDeviceId();
    final active = await repositories.sos.createAndActivate(
      ownerDeviceId: localDeviceId,
      ownerUserId: 'local-user',
    );

    transport.simulatePeer(id: 'endpoint-sos-replay', name: 'SOS Peer');
    await settle();
    await service.connect('endpoint-sos-replay');
    await settle();
    final activePacket = transport.sentPayloads
        .map(RelioPacket.fromBytes)
        .where((packet) => packet.type == RelioPacketType.sos)
        .single;
    expect(activePacket.payload['isActive'], isTrue);
    expect(activePacket.payload['stateRevision'], 1);

    transport.simulateConnectionLoss('endpoint-sos-replay');
    await settle();
    await repositories.sos.deactivate(active.id);
    final cleared = await repositories.sos.getById(active.id);
    expect(cleared?.isActive, isFalse);
    await service.sendSos(cleared!);

    transport.simulatePeer(id: 'endpoint-sos-replay', name: 'SOS Peer');
    await settle();
    await service.connect('endpoint-sos-replay');
    await settle();
    final replayedClear = transport.sentPayloads
        .map(RelioPacket.fromBytes)
        .where(
          (packet) =>
              packet.type == RelioPacketType.sos &&
              packet.payload['isActive'] == false,
        )
        .last;
    expect(replayedClear.payload['sosId'], active.id);
    expect(replayedClear.payload['stateRevision'], 3);
  });

  test(
    'sends SOS over a connected session after discovery visibility is lost',
    () async {
      transport.simulatePeer(id: 'endpoint-sos-visible-loss', name: 'SOS Peer');
      await settle();
      await service.connect('endpoint-sos-visible-loss');
      await settle();
      transport.simulateIncoming(
        peerId: 'endpoint-sos-visible-loss',
        bytes: await applicationBytes(
          RelioPacket.hello(
            senderDeviceId: 'device-sos-visible-loss',
            senderUserId: 'sos-user',
            displayName: 'SOS Peer',
          ),
          repositories,
        ),
      );
      await settle();
      transport.sentPayloads.clear();
      transport.sentPeerIds.clear();

      transport.simulateEndpointLoss('endpoint-sos-visible-loss');
      await settle();
      final localDeviceId = await RelioDeviceIdentityRepository(
        database,
      ).getDeviceId();
      final event = await repositories.sos.createAndActivate(
        ownerDeviceId: localDeviceId,
        ownerUserId: '',
      );
      await service.sendSos(event);

      expect(transport.sentPeerIds, ['endpoint-sos-visible-loss']);
      final packet = transport.sentPayloads.map(RelioPacket.fromBytes).single;
      expect(packet.type, RelioPacketType.sos);
      expect(packet.payload['isActive'], isTrue);
      expect(service.lastError, isNull);
    },
  );

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
        bytes: await applicationBytes(
          RelioPacket.hello(
            senderDeviceId: 'device-peer-a',
            senderUserId: 'peer-a',
            displayName: 'Peer A',
            status: DeviceStatus.rescue,
          ),
          repositories,
        ),
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
        remotePrincipalId: 'guest:device-peer-a',
        displayName: 'Peer A',
        participantStatus: DeviceStatus.normal,
      );
      transport.simulatePeer(id: 'endpoint-a', name: 'Peer A');
      await settle();
      await service.connect('endpoint-a');
      await settle();
      transport.simulateIncoming(
        peerId: 'endpoint-a',
        bytes: await applicationBytes(
          RelioPacket.hello(
            senderDeviceId: 'device-peer-a',
            senderUserId: 'peer-a',
            displayName: 'Peer A',
          ),
          repositories,
        ),
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
        bytes: await applicationBytes(incoming, repositories),
      );
      transport.simulateIncoming(
        peerId: 'endpoint-a',
        bytes: await applicationBytes(incoming, repositories),
      );
      await settle();
      expect(
        transport.sentPayloads
            .map(RelioPacket.fromBytes)
            .where((packet) => packet.type == RelioPacketType.ack),
        hasLength(2),
      );
      expect(
        (await repositories.messages.listMessages(
          'conversation-a',
        )).where((item) => item.id == 'incoming-1'),
        hasLength(1),
      );
      expect(service.lastError, isNull);

      final ack = RelioPacket.ack(
        senderDeviceId: 'device-peer-a',
        senderUserId: 'peer-a',
        acknowledgedPacketId: sentText.packetId,
        messageId: message.id,
      );
      transport.simulateIncoming(
        peerId: 'endpoint-a',
        bytes: Uint8List.fromList(await applicationBytes(ack, repositories)),
      );
      transport.simulateIncoming(
        peerId: 'endpoint-a',
        bytes: Uint8List.fromList(await applicationBytes(ack, repositories)),
      );
      await settle();
      expect(
        (await repositories.messages.getMessage(message.id))?.status,
        DeliveryStatus.delivered,
      );
    },
  );

  test(
    'pending local text flushes only after a peer hello identifies it',
    () async {
      const peerDeviceId = 'device-peer-queued';
      await repositories.conversations.ensureConversation(
        id: peerDeviceId,
        participantId: peerDeviceId,
        remotePrincipalId: 'guest:$peerDeviceId',
        displayName: 'Queued Peer',
        participantStatus: DeviceStatus.normal,
      );
      final message = await repositories.messages.createOutgoingText(
        conversationId: peerDeviceId,
        senderId: 'minnie',
        senderDeviceId: await RelioDeviceIdentityRepository(
          database,
        ).getDeviceId(),
        text: 'ส่งเมื่อเชื่อมต่อได้',
      );

      transport.simulatePeer(id: 'endpoint-queued', name: 'Queued Peer');
      await settle();
      await service.connect('endpoint-queued');
      await settle();
      expect(
        (await repositories.messages.getMessage(message.id))?.status,
        DeliveryStatus.pending,
      );

      transport.simulateIncoming(
        peerId: 'endpoint-queued',
        bytes: await applicationBytes(
          RelioPacket.hello(
            senderDeviceId: peerDeviceId,
            senderUserId: 'peer-user',
            displayName: 'Queued Peer',
          ),
          repositories,
        ),
      );
      await settle();

      final sent = transport.sentPayloads
          .map(RelioPacket.fromBytes)
          .where((packet) => packet.type == RelioPacketType.textMessage)
          .single;
      expect(sent.payload['messageId'], message.id);
      expect(sent.payload['text'], 'ส่งเมื่อเชื่อมต่อได้');
      expect(
        (await repositories.messages.getMessage(message.id))?.status,
        DeliveryStatus.nearbySent,
      );
    },
  );

  test(
    'a new active SOS replaces prior active event IDs from its peer',
    () async {
      transport.simulatePeer(id: 'endpoint-sos-replace', name: 'SOS Peer');
      await settle();
      await service.connect('endpoint-sos-replace');
      await settle();
      transport.simulateIncoming(
        peerId: 'endpoint-sos-replace',
        bytes: await applicationBytes(
          RelioPacket.hello(
            senderDeviceId: 'device-sos-replace',
            senderUserId: 'sos-user',
            displayName: 'SOS Peer',
          ),
          repositories,
        ),
      );
      await settle();

      for (final sos in [
        RelioPacket.sos(
          senderDeviceId: 'device-sos-replace',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          sosId: 'sos-old',
          createdAt: DateTime.now(),
          isActive: true,
          stateRevision: 1,
        ),
        RelioPacket.sos(
          senderDeviceId: 'device-sos-replace',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          sosId: 'sos-current',
          createdAt: DateTime.now(),
          isActive: true,
          stateRevision: 2,
        ),
      ]) {
        transport.simulateIncoming(
          peerId: 'endpoint-sos-replace',
          bytes: await applicationBytes(sos, repositories),
        );
        await settle();
      }

      expect((await repositories.sos.getById('sos-old'))?.isActive, isFalse);
      expect(
        (await repositories.sos.readActive(
          ownerDeviceId: 'device-sos-replace',
        ))?.id,
        'sos-current',
      );
      expect(service.peerStatuses['device-sos-replace'], DeviceStatus.sos);
    },
  );

  test('incoming SOS and clear are persisted and update peer status', () async {
    transport.simulatePeer(id: 'endpoint-sos', name: 'SOS Peer');
    await settle();
    await service.connect('endpoint-sos');
    await settle();
    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.hello(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
        ),
        repositories,
      ),
    );
    await settle();
    final locationCapturedAt = DateTime.now().subtract(
      const Duration(minutes: 11),
    );
    final packet = RelioPacket.sos(
      senderDeviceId: 'device-sos',
      senderUserId: 'sos-user',
      displayName: 'SOS Peer',
      sosId: 'sos-1',
      message: 'need help',
      latitude: 13.75,
      longitude: 100.5,
      accuracyMeters: 10,
      locationCapturedAt: locationCapturedAt,
      createdAt: DateTime.now(),
      isActive: true,
      stateRevision: 1,
    );
    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(packet, repositories),
    );
    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(packet, repositories),
    );
    await settle();

    final receivedSos = await repositories.sos.getById('sos-1');
    expect(receivedSos?.isActive, isTrue);
    expect(receivedSos?.message, 'need help');
    expect(receivedSos?.latitude, 13.75);
    expect(receivedSos?.longitude, 100.5);
    expect(receivedSos?.locationAccuracy, 10);
    expect(
      receivedSos?.locationCapturedAt
          ?.difference(locationCapturedAt)
          .inMilliseconds
          .abs(),
      lessThan(1000),
    );
    expect(receivedSos?.updatedAt.isAfter(locationCapturedAt), isTrue);
    expect(
      notifications.shown.where((item) => item.id == 'sos-1'),
      hasLength(1),
    );
    expect(
      (await repositories.nearbyDevices.listDevices()).single.status,
      DeviceStatus.sos,
    );

    for (final statusPacket in [
      RelioPacket.deviceStatus(
        senderDeviceId: 'device-sos',
        senderUserId: 'sos-user',
        displayName: 'SOS Peer',
        status: DeviceStatus.rescue,
        rescueActive: true,
      ),
      RelioPacket.hello(
        senderDeviceId: 'device-sos',
        senderUserId: 'sos-user',
        displayName: 'SOS Peer',
        status: DeviceStatus.rescue,
        rescueActive: true,
      ),
    ]) {
      transport.simulateIncoming(
        peerId: 'endpoint-sos',
        bytes: await applicationBytes(statusPacket, repositories),
      );
      await settle();
      expect(service.peerStatuses['device-sos'], DeviceStatus.sos);
      expect(
        (await repositories.nearbyDevices.listDevices()).single.status,
        DeviceStatus.sos,
      );
    }

    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          status: DeviceStatus.normal,
          rescueActive: false,
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.sos);
    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          status: DeviceStatus.sos,
          rescueActive: true,
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.sos);

    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.sos(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          sosId: 'sos-1',
          message: 'need help',
          createdAt: packet.createdAt,
          isActive: false,
          stateRevision: 2,
        ),
        repositories,
      ),
    );
    await settle();

    expect((await repositories.sos.getById('sos-1'))?.isActive, isFalse);
    expect(
      await repositories.sos.readActive(ownerDeviceId: 'device-sos'),
      isNull,
    );
    expect(
      notifications.shown.where((item) => item.id == 'sos-1'),
      hasLength(1),
    );
    expect(service.peerStatuses['device-sos'], DeviceStatus.rescue);
    expect(
      (await repositories.nearbyDevices.listDevices()).single.status,
      DeviceStatus.rescue,
    );

    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(packet, repositories),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.rescue);
    expect(
      await repositories.sos.readActive(ownerDeviceId: 'device-sos'),
      isNull,
    );

    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.sos(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          sosId: 'sos-1',
          createdAt: packet.createdAt,
          isActive: true,
          stateRevision: 3,
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.sos);

    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          status: DeviceStatus.sos,
          rescueActive: true,
          updatedAt: DateTime.now().add(const Duration(seconds: 2)),
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.sos);

    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          status: DeviceStatus.sos,
          rescueActive: false,
          updatedAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.sos);

    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.sos(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          sosId: 'sos-1',
          createdAt: packet.createdAt,
          isActive: false,
          stateRevision: 4,
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.rescue);
    expect(
      (await repositories.nearbyDevices.listDevices()).single.status,
      DeviceStatus.rescue,
    );

    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          status: DeviceStatus.normal,
          rescueActive: false,
          updatedAt: DateTime.now().add(const Duration(seconds: 3)),
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.normal);

    // Duplicate clear is idempotent; an old active SOS cannot resurrect it.
    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.sos(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          sosId: 'sos-1',
          createdAt: packet.createdAt,
          isActive: false,
          stateRevision: 4,
        ),
        repositories,
      ),
    );
    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(packet, repositories),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.normal);
    expect(
      await repositories.sos.readActive(ownerDeviceId: 'device-sos'),
      isNull,
    );

    transport.simulateConnectionLoss('endpoint-sos');
    await settle();
    await service.connect('endpoint-sos');
    await settle();
    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.hello(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          status: DeviceStatus.normal,
          rescueActive: false,
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.normal);

    transport.simulateConnectionLoss('endpoint-sos');
    await settle();
    await service.connect('endpoint-sos');
    await settle();
    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.hello(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          status: DeviceStatus.rescue,
          rescueActive: true,
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.rescue);
    expect(
      await repositories.sos.readActive(ownerDeviceId: 'device-sos'),
      isNull,
    );

    // A persisted stale SOS presentation is reconciled from the cleared event
    // and the authoritative Rescue bit in the reconnect hello.
    await repositories.nearbyDevices.upsert(
      deviceId: 'device-sos',
      displayName: 'SOS Peer',
      status: DeviceStatus.sos,
    );
    transport.simulateConnectionLoss('endpoint-sos');
    await settle();
    await service.connect('endpoint-sos');
    await settle();
    transport.simulateIncoming(
      peerId: 'endpoint-sos',
      bytes: await applicationBytes(
        RelioPacket.hello(
          senderDeviceId: 'device-sos',
          senderUserId: 'sos-user',
          displayName: 'SOS Peer',
          status: DeviceStatus.sos,
          rescueActive: false,
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-sos'], DeviceStatus.normal);
    expect(
      (await repositories.nearbyDevices.listDevices()).single.status,
      DeviceStatus.normal,
    );
  });

  test(
    'new SOS routes only to established RFCOMM peer and correlates its ACK',
    () async {
      Future<void> connectAndIdentify(String endpoint, String deviceId) async {
        transport.simulatePeer(id: endpoint, name: deviceId);
        await settle();
        await service.connect(endpoint);
        await settle();
        transport.simulateIncoming(
          peerId: endpoint,
          bytes: await applicationBytes(
            RelioPacket.hello(
              senderDeviceId: deviceId,
              senderUserId: '$deviceId-user',
              displayName: deviceId,
            ),
            repositories,
          ),
        );
        await settle();
      }

      await connectAndIdentify('old-nearby-endpoint', 'device-old');
      await connectAndIdentify('classic:realme-address', 'device-realme');
      transport.sentPayloads.clear();
      transport.sentPeerIds.clear();

      // Discovery loss must not leave the old endpoint eligible for SOS routing.
      transport.simulateEndpointLoss('old-nearby-endpoint');
      transport.simulateConnectionLoss('old-nearby-endpoint');
      await settle();

      final localDeviceId = await RelioDeviceIdentityRepository(
        database,
      ).getDeviceId();
      final event = await repositories.sos.createAndActivate(
        ownerDeviceId: localDeviceId,
        ownerUserId: '',
        message: 'outbound route check',
      );
      await service.sendSos(event);

      expect(transport.sentPeerIds, ['classic:realme-address']);
      final sentPacket = transport.sentPayloads
          .map(RelioPacket.fromBytes)
          .single;
      expect(sentPacket.type, RelioPacketType.sos);
      expect(sentPacket.payload['sosId'], event.id);
      expect(sentPacket.payload['stateRevision'], 1);
      expect(service.lastError, isNull);

      transport.simulateIncoming(
        peerId: 'classic:realme-address',
        bytes: await applicationBytes(
          RelioPacket.ack(
            senderDeviceId: 'device-realme',
            senderUserId: 'device-realme-user',
            acknowledgedPacketId: sentPacket.packetId,
          ),
          repositories,
        ),
      );
      await settle();

      expect(
        service.eventLog.any(
          (entry) =>
              entry.contains('SOS ACK received') &&
              entry.contains('event=${event.id}'),
        ),
        isTrue,
      );
      expect(service.acknowledgementCount, 1);
    },
  );

  test('incoming Rescue and normal status propagate and clear', () async {
    transport.simulatePeer(id: 'endpoint-rescue', name: 'Rescue Peer');
    await settle();
    await service.connect('endpoint-rescue');
    await settle();
    transport.simulateIncoming(
      peerId: 'endpoint-rescue',
      bytes: await applicationBytes(
        RelioPacket.hello(
          senderDeviceId: 'device-rescue',
          senderUserId: 'rescue-user',
          displayName: 'Rescue Peer',
        ),
        repositories,
      ),
    );
    await settle();

    transport.simulateIncoming(
      peerId: 'endpoint-rescue',
      bytes: await applicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-rescue',
          senderUserId: 'rescue-user',
          displayName: 'Rescue Peer',
          status: DeviceStatus.rescue,
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-rescue'], DeviceStatus.rescue);
    expect(
      (await repositories.nearbyDevices.listDevices()).single.status,
      DeviceStatus.rescue,
    );

    transport.simulateIncoming(
      peerId: 'endpoint-rescue',
      bytes: await applicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-rescue',
          senderUserId: 'rescue-user',
          displayName: 'Rescue Peer',
          status: DeviceStatus.normal,
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-rescue'], DeviceStatus.normal);
    expect(
      (await repositories.nearbyDevices.listDevices()).single.status,
      DeviceStatus.normal,
    );

    final newestStatusAt = DateTime.now().add(const Duration(seconds: 2));
    transport.simulateIncoming(
      peerId: 'endpoint-rescue',
      bytes: await applicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-rescue',
          senderUserId: 'rescue-user',
          displayName: 'Rescue Peer',
          status: DeviceStatus.normal,
          rescueActive: false,
          updatedAt: newestStatusAt,
        ),
        repositories,
      ),
    );
    await settle();
    transport.simulateIncoming(
      peerId: 'endpoint-rescue',
      bytes: await applicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: 'device-rescue',
          senderUserId: 'rescue-user',
          displayName: 'Rescue Peer',
          status: DeviceStatus.rescue,
          rescueActive: true,
          updatedAt: newestStatusAt.subtract(const Duration(seconds: 1)),
        ),
        repositories,
      ),
    );
    await settle();
    expect(service.peerStatuses['device-rescue'], DeviceStatus.normal);
  });

  test('send failure keeps the message locally and marks it failed', () async {
    await repositories.conversations.ensureConversation(
      id: 'peer-fail',
      participantId: 'peer-fail',
      remotePrincipalId: 'guest:peer-fail',
      displayName: 'Peer Fail',
      participantStatus: DeviceStatus.normal,
    );
    transport.simulatePeer(
      id: 'fail-endpoint',
      name: 'Peer Fail',
      deviceId: 'peer-fail',
    );
    await settle();
    await service.connect('fail-endpoint');
    transport.simulateIncoming(
      peerId: 'fail-endpoint',
      bytes: await applicationBytes(
        RelioPacket.hello(
          senderDeviceId: 'peer-fail',
          senderUserId: 'peer-fail',
          displayName: 'Peer Fail',
        ),
        repositories,
      ),
    );
    await settle();
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
