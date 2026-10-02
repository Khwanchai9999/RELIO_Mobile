import 'package:drift/drift.dart';
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
      await service.close();
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

  test('duplicate manual taps share one native connection request', () async {
    transport.simulatePeer(id: 'single-flight-peer', name: 'Peer');
    await Future<void>.delayed(Duration.zero);
    await Future.wait([
      service.connect('single-flight-peer'),
      service.connect('single-flight-peer'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(transport.connectionRequestCount, 1);
    expect(
      service.peerStates['single-flight-peer'],
      NearbyConnectionState.connected,
    );
  });

  test(
    'incoming request remains app-service state and accept/reject use transport',
    () async {
      transport.simulateIncomingConnection(id: 'incoming-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      expect(service.pendingConnectionRequests.keys, contains('incoming-peer'));

      await service.acceptConnectionRequest('incoming-peer');
      expect(transport.acceptedConnections, contains('incoming-peer'));
      expect(service.pendingConnectionRequests, isEmpty);

      transport.simulateIncomingConnection(id: 'reject-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      await service.rejectConnectionRequest('reject-peer');
      expect(transport.rejectedConnections, contains('reject-peer'));
    },
  );

  test(
    'missing native connection result times out and permits retry',
    () async {
      await service.close();
      transport = MockNearbyTransport()..holdConnectionRequests = true;
      service = NearbyService(
        transport: transport,
        messages: repositories.messages,
        conversations: repositories.conversations,
        identity: RelioDeviceIdentityRepository(database),
        nearbyDevices: repositories.nearbyDevices,
        connectionAttemptTimeout: const Duration(milliseconds: 20),
      );
      await service.initialize();
      transport.simulatePeer(id: 'timeout-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);

      await service.connect('timeout-peer');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(service.peerErrors['timeout-peer'], 'connection_timeout');
      expect(service.peerStates['timeout-peer'], NearbyConnectionState.failed);

      transport.holdConnectionRequests = false;
      await service.connect('timeout-peer');
      expect(transport.connectionRequestCount, 2);
    },
  );

  test('unanswered incoming request expires and is rejected safely', () async {
    await service.close();
    transport = MockNearbyTransport();
    service = NearbyService(
      transport: transport,
      messages: repositories.messages,
      conversations: repositories.conversations,
      identity: RelioDeviceIdentityRepository(database),
      nearbyDevices: repositories.nearbyDevices,
      connectionAttemptTimeout: const Duration(milliseconds: 20),
    );
    await service.initialize();
    transport.simulateIncomingConnection(id: 'expiring-peer', name: 'Peer');
    await Future<void>.delayed(Duration.zero);
    expect(service.pendingConnectionRequests, contains('expiring-peer'));

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(service.pendingConnectionRequests, isEmpty);
    expect(transport.rejectedConnections, contains('expiring-peer'));
    expect(service.peerErrors['expiring-peer'], 'incoming_request_timeout');
  });

  test(
    'legacy trusted peer without a key falls back to manual approval',
    () async {
      const legacyId = 'legacy-device';
      final fingerprint = 'a' * 64;
      await database
          .into(database.nearbyDevices)
          .insert(
            NearbyDevicesCompanion.insert(
              deviceId: legacyId,
              displayName: 'Legacy peer',
              status: DeviceStatus.normal.name,
              lastSeenAt: DateTime.now(),
              isTrusted: const Value(true),
              autoReconnectEnabled: const Value(true),
              publicIdentityFingerprint: Value(fingerprint),
            ),
          );
      transport.simulateIncomingConnection(
        id: 'legacy-endpoint',
        name: 'Legacy peer',
        identityFingerprintHint: fingerprint,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(service.pendingConnectionRequests, contains('legacy-endpoint'));
      expect(transport.acceptedConnections, isNot(contains('legacy-endpoint')));
      expect(
        (await repositories.nearbyDevices.getDevice(legacyId))?.isTrusted,
        isTrue,
      );
    },
  );

  test(
    'manual connect racing trusted auto-reconnect makes one native request',
    () async {
      final local = await service.identityCrypto.getPublicIdentity();
      final upper = 'f' * 64;
      final fingerprint = local.fingerprint.compareTo(upper) < 0
          ? upper
          : '0' * 64;
      await repositories.nearbyDevices.upsert(
        deviceId: 'auto-device',
        displayName: 'Auto peer',
        status: DeviceStatus.normal,
      );
      await repositories.nearbyDevices.setTrustedIdentity(
        deviceId: 'auto-device',
        publicIdentityKey: 'test-public-key',
        fingerprint: fingerprint,
      );
      transport.simulatePeer(
        id: 'race-endpoint',
        name: 'Auto peer',
        identityFingerprintHint: fingerprint,
      );
      await service.connect('race-endpoint');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(transport.connectionRequestCount, 1);
    },
  );

  test('endpoint loss preserves locally stored conversation history', () async {
    await repositories.conversations.ensureConversation(
      id: 'history-peer',
      participantId: 'history-peer',
      displayName: 'Peer',
      participantStatus: DeviceStatus.normal,
    );
    final message = await repositories.messages.createOutgoingText(
      conversationId: 'history-peer',
      senderId: 'local-user',
      senderDeviceId: 'local-device',
      text: 'Preserve this local history',
    );
    transport.simulatePeer(id: 'history-endpoint', name: 'Peer');
    await Future<void>.delayed(Duration.zero);
    transport.simulateConnectionLoss('history-endpoint');
    await Future<void>.delayed(Duration.zero);
    expect(
      (await repositories.messages.listMessages('history-peer')).single.id,
      message.id,
    );
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
      transport.simulatePeer(id: 'peer-1', name: 'Peer One');
      await Future<void>.delayed(Duration.zero);
      await service.connect('peer-1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      transport.simulateIncoming(
        peerId: 'peer-1',
        bytes: RelioPacket.hello(
          senderDeviceId: 'peer-1',
          senderUserId: 'peer-1',
          displayName: 'Peer One',
        ).toBytes(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
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

      final sent = transport.sentPayloads
          .map(RelioPacket.fromBytes)
          .firstWhere((packet) => packet.type == RelioPacketType.textMessage);
      final ack = RelioPacket.ack(
        senderDeviceId: 'peer-1',
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
    'incoming text requires hello and mock connection loss is observable',
    () async {
      transport.simulatePeer(id: 'peer-1', name: 'Peer One');
      await Future<void>.delayed(Duration.zero);
      await service.connect('peer-1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
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
      expect(await repositories.messages.listMessages('peer-device'), isEmpty);

      final hello = RelioPacket.hello(
        senderDeviceId: 'peer-device',
        senderUserId: 'peer-1',
        displayName: 'Peer One',
      );
      transport.simulateIncoming(peerId: 'peer-1', bytes: hello.toBytes());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      transport.simulateIncoming(peerId: 'peer-1', bytes: packet.toBytes());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        (await repositories.messages.listMessages('peer-device')).single.text,
        'รับข้อความแล้ว',
      );
      expect(
        transport.sentPayloads.map(RelioPacket.fromBytes),
        contains(
          isA<RelioPacket>().having(
            (packet) => packet.type,
            'type',
            RelioPacketType.ack,
          ),
        ),
      );

      transport.simulateConnectionLoss('peer-1');
      await Future<void>.delayed(Duration.zero);
      expect(
        service.eventLog.any((item) => item.contains('disconnected')),
        isTrue,
      );
    },
  );
}
