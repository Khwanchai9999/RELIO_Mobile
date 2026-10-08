import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/location/location_service.dart';
import 'package:relio_mobile/core/media/media_storage_service.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  test('protocol v1 encodes media metadata and location packets', () {
    final media = RelioPacket.mediaMetadata(
      senderDeviceId: 'device-a',
      senderUserId: 'minnie',
      messageId: 'message-1',
      attachmentId: 'attachment-1',
      transferId: 'transfer-1',
      mediaType: 'image',
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
      byteSize: 42,
      payloadId: '7',
    );
    final location = RelioPacket.locationMessage(
      senderDeviceId: 'device-a',
      senderUserId: 'minnie',
      messageId: 'message-2',
      conversationId: 'device-b',
      latitude: 13.7563,
      longitude: 100.5018,
      capturedAt: DateTime.utc(2026, 1, 1),
    );

    expect(
      RelioPacket.fromBytes(media.toBytes()).type,
      RelioPacketType.mediaMetadata,
    );
    expect(
      RelioPacket.fromBytes(location.toBytes()).type,
      RelioPacketType.locationMessage,
    );
  });

  test('protocol v1 encodes and validates read receipts', () {
    final receipt = RelioPacket.readReceipt(
      senderDeviceId: 'device-b',
      senderUserId: 'user-b',
      messageId: 'message-1',
      readAt: DateTime.utc(2026, 10, 1),
    );

    final decoded = RelioPacket.fromBytes(receipt.toBytes());
    expect(decoded.type, RelioPacketType.readReceipt);
    expect(decoded.payload['messageId'], 'message-1');
    expect(decoded.payload['readAt'], '2026-10-01T00:00:00.000Z');
  });

  test('malformed media metadata is rejected without a crash', () {
    expect(
      () => RelioPacket.fromJson({
        'protocolVersion': 1,
        'packetId': 'packet',
        'type': 'mediaMetadata',
        'senderDeviceId': 'device',
        'senderUserId': 'user',
        'createdAt': DateTime.now().toIso8601String(),
        'payload': {'mediaType': 'archive'},
      }),
      throwsA(isA<RelioPacketException>()),
    );
  });

  test(
    'current schema preserves messages while attachments persist transfer state',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final repos = RelioRepositories(db);
      await repos.conversations.ensureConversation(
        id: 'peer',
        participantId: 'peer',
        displayName: 'Peer',
        participantStatus: DeviceStatus.normal,
      );
      final message = await repos.messages.createOutgoingText(
        conversationId: 'peer',
        senderId: 'minnie',
        senderDeviceId: 'device-a',
        text: 'before attachment',
      );
      await repos.attachments.createPending(
        id: 'attachment',
        conversationId: 'peer',
        messageId: message.id,
        transferId: 'transfer',
        mediaType: MediaType.image,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        localPath: 'managed/photo.jpg',
        byteSize: 100,
      );
      await repos.attachments.updateProgress(
        'attachment',
        status: MediaTransferState.transferring,
        bytesTransferred: 42,
      );

      expect(db.schemaVersion, 8);
      expect(
        (await repos.messages.getMessage(message.id))?.text,
        'before attachment',
      );
      expect(
        (await repos.attachments.getByTransferId('transfer'))?.bytesTransferred,
        42,
      );
    },
  );

  test(
    'mock file transfer emits deterministic progress and completion',
    () async {
      final directory = await Directory.systemTemp.createTemp('relio-v04-');
      final file = File('${directory.path}/photo.jpg')
        ..writeAsBytesSync(Uint8List.fromList([0xff, 0xd8, 0xff]));
      final transport = MockNearbyTransport();
      addTearDown(() async {
        await transport.dispose();
        await directory.delete(recursive: true);
      });
      final events = <NearbyTransferEvent>[];
      final subscription = transport.transferEvents.listen(events.add);
      addTearDown(subscription.cancel);

      final payloadId = await transport.sendFile(file.path, peerId: 'peer');
      await Future<void>.delayed(Duration.zero);

      expect(payloadId, 'mock-payload-1');
      expect(events.map((event) => event.status), [
        NearbyTransferStatus.started,
        NearbyTransferStatus.success,
      ]);
      expect(events.last.bytesTransferred, 3);
    },
  );

  test(
    'media storage rejects invalid content and owns generated paths',
    () async {
      final directory = await Directory.systemTemp.createTemp('relio-media-');
      final source = File('${directory.path}/not-a-photo.jpg')
        ..writeAsStringSync('not an image');
      final storage = MediaStorageService(
        rootDirectory: Directory('${directory.path}/managed'),
      );
      addTearDown(() => directory.delete(recursive: true));

      expect(
        () => storage.copySelectedFile(source.path),
        throwsA(isA<MediaStorageException>()),
      );
    },
  );

  test('image size cap and MIME signature are enforced', () async {
    final directory = await Directory.systemTemp.createTemp(
      'relio-media-policy-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final storage = MediaStorageService(
      rootDirectory: Directory('${directory.path}/managed'),
    );
    final oversized = File('${directory.path}/large.png');
    await oversized.writeAsBytes([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      ...List<int>.filled(15 * 1024 * 1024, 0),
    ]);
    await expectLater(
      storage.validateFile(oversized.path),
      throwsA(isA<MediaStorageException>()),
    );

    final wrongMime = File('${directory.path}/wrong.jpg')
      ..writeAsBytesSync([137, 80, 78, 71, 13, 10, 26, 10, 0]);
    await expectLater(
      storage.storeIncomingFile(
        sourcePath: wrongMime.path,
        fileName: 'wrong.jpg',
        expectedMimeType: 'image/jpeg',
        expectedBytes: 9,
      ),
      throwsA(isA<MediaStorageException>()),
    );
  });

  test(
    'video is bounded, copied locally, and retains failed transfer state',
    () async {
      final directory = await Directory.systemTemp.createTemp('relio-video-');
      addTearDown(() => directory.delete(recursive: true));
      final root = Directory('${directory.path}/managed');
      final file = File('${directory.path}/sample.mp4')
        ..writeAsBytesSync([
          0,
          0,
          0,
          24,
          102,
          116,
          121,
          112,
          105,
          115,
          111,
          109,
          0,
          0,
          0,
          1,
        ]);
      final storage = MediaStorageService(
        rootDirectory: root,
        policy: const MediaTransferPolicy(maxVideoBytes: 16),
      );
      final metadata = await storage.validateFile(file.path);

      expect(metadata.mimeType, 'video/mp4');
      expect(metadata.mediaType, 'video');
      expect(metadata.byteSize, 16);
      final managedPath = await storage.copySelectedFile(file.path);
      expect(await storage.isManagedFile(managedPath), isTrue);

      final oversized = File('${directory.path}/oversized.mp4')
        ..writeAsBytesSync([
          0,
          0,
          0,
          24,
          102,
          116,
          121,
          112,
          105,
          115,
          111,
          109,
          ...List<int>.filled(5, 0),
        ]);
      await expectLater(
        storage.validateFile(oversized.path),
        throwsA(isA<MediaStorageException>()),
      );

      final database = AppDatabase.memory();
      addTearDown(database.close);
      final repositories = RelioRepositories(database);
      await repositories.conversations.ensureConversation(
        id: 'video-peer',
        participantId: 'video-peer',
        displayName: 'Video peer',
        participantStatus: DeviceStatus.offline,
      );
      final attachment = await repositories.attachments.createPending(
        id: 'video-attachment',
        conversationId: 'video-peer',
        messageId: 'video-message',
        transferId: 'video-transfer',
        mediaType: MediaType.video,
        fileName: 'sample.mp4',
        mimeType: metadata.mimeType,
        localPath: managedPath,
        byteSize: metadata.byteSize,
      );
      await repositories.attachments.markFailed(attachment.id, 'test_failure');
      final failed = await repositories.attachments.getById(attachment.id);

      expect(failed?.mediaType, MediaType.video);
      expect(failed?.mimeType, 'video/mp4');
      expect(failed?.byteSize, 16);
      expect(failed?.transferStatus, MediaTransferState.failed);
      expect(failed?.errorCode, 'test_failure');
    },
  );

  test(
    'fake location service supports success and unavailable states',
    () async {
      final now = DateTime.utc(2026, 1, 1);
      final success = FakeLocationService(
        LocationResult.success(
          LocationData(
            latitude: 13.7563,
            longitude: 100.5018,
            capturedAt: now,
            source: 'test',
          ),
        ),
      );
      final unavailable = FakeLocationService(
        const LocationResult.failure(LocationFailure.serviceDisabled),
      );

      expect(
        (await success.getCurrentOrLastKnown()).location?.latitude,
        13.7563,
      );
      expect(
        (await unavailable.getCurrentOrLastKnown()).failure,
        LocationFailure.serviceDisabled,
      );
    },
  );

  test('NearbyService persists media locally before mock file send', () async {
    final db = AppDatabase.memory();
    final transport = MockNearbyTransport();
    final directory = await Directory.systemTemp.createTemp('relio-send-');
    final repos = RelioRepositories(db);
    final identity = RelioDeviceIdentityRepository(db);
    final storage = MediaStorageService(rootDirectory: directory);
    await repos.conversations.ensureConversation(
      id: 'peer',
      participantId: 'peer-device',
      displayName: 'Peer',
      participantStatus: DeviceStatus.normal,
    );
    final message = await repos.messages.createOutgoingText(
      conversationId: 'peer',
      senderId: 'minnie',
      senderDeviceId: await identity.getDeviceId(),
      text: 'placeholder',
    );
    final file = File('${directory.path}/photo.jpg')
      ..writeAsBytesSync(Uint8List.fromList([0xff, 0xd8, 0xff]));
    final attachment = await repos.attachments.createPending(
      id: 'attachment',
      conversationId: 'peer',
      messageId: message.id,
      transferId: 'transfer',
      mediaType: MediaType.image,
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
      localPath: file.path,
      byteSize: 3,
    );
    final service = NearbyService(
      transport: transport,
      messages: repos.messages,
      conversations: repos.conversations,
      identity: identity,
      nearbyDevices: repos.nearbyDevices,
      attachments: repos.attachments,
      mediaStorage: storage,
    );
    addTearDown(() async {
      await service.close();
      await db.close();
      await directory.delete(recursive: true);
    });
    await service.initialize();

    await service.sendMediaMessage(message, attachment);

    expect(transport.sentFiles, [file.path]);
    expect(
      (await repos.messages.getMessage(message.id))?.status,
      DeliveryStatus.nearbySent,
    );
    expect(
      (await repos.attachments.getById('attachment'))?.transferStatus,
      MediaTransferState.transferring,
    );
  });

  test(
    'pending offline image is transferred when its peer reconnects',
    () async {
      final db = AppDatabase.memory();
      final transport = MockNearbyTransport();
      final directory = await Directory.systemTemp.createTemp('relio-offline-');
      final repositories = RelioRepositories(db);
      final identity = RelioDeviceIdentityRepository(db);
      final storage = MediaStorageService(rootDirectory: directory);
      await repositories.conversations.ensureConversation(
        id: 'offline-peer',
        participantId: 'offline-peer-device',
        displayName: 'Offline peer',
        participantStatus: DeviceStatus.offline,
      );
      final file = File('${directory.path}/photo.jpg')
        ..writeAsBytesSync(Uint8List.fromList([0xff, 0xd8, 0xff]));
      final attachment = await repositories.attachments.createPending(
        id: 'offline-attachment',
        conversationId: 'offline-peer',
        messageId: 'offline-image-message',
        transferId: 'offline-image-transfer',
        mediaType: MediaType.image,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        localPath: file.path,
        byteSize: 3,
      );
      final message = await repositories.messages.createOutgoingMedia(
        conversationId: 'offline-peer',
        senderId: 'sender',
        senderDeviceId: await identity.getDeviceId(),
        type: MessageType.image,
        fileName: 'photo.jpg',
        localPath: file.path,
        attachmentId: attachment.id,
        messageId: attachment.messageId,
      );
      expect(message.status, DeliveryStatus.pending);

      final service = NearbyService(
        transport: transport,
        messages: repositories.messages,
        conversations: repositories.conversations,
        identity: identity,
        nearbyDevices: repositories.nearbyDevices,
        attachments: repositories.attachments,
        mediaStorage: storage,
      );
      addTearDown(() async {
        await service.close();
        await db.close();
        await directory.delete(recursive: true);
      });
      await service.initialize();
      transport.simulatePeer(
        id: 'offline-peer-endpoint',
        name: 'Offline peer',
        deviceId: 'offline-peer-device',
      );
      await Future<void>.delayed(Duration.zero);
      await service.connect('offline-peer-endpoint');
      transport.simulateIncoming(
        peerId: 'offline-peer-endpoint',
        bytes: RelioPacket.hello(
          senderDeviceId: 'offline-peer-device',
          senderUserId: 'peer-user',
          displayName: 'Offline peer',
        ).toBytes(),
      );
      final sendDeadline = DateTime.now().add(const Duration(seconds: 2));
      while ((await repositories.messages.getMessage(message.id))?.status !=
              DeliveryStatus.nearbySent &&
          DateTime.now().isBefore(sendDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(transport.sentFiles, [file.path]);
      expect(
        (await repositories.messages.getMessage(message.id))?.status,
        DeliveryStatus.nearbySent,
      );
    },
  );

  test(
    'NearbyService correlates file-before-metadata and persists incoming media',
    () async {
      final db = AppDatabase.memory();
      final transport = MockNearbyTransport();
      final root = await Directory.systemTemp.createTemp('relio-receive-');
      final source = File('${root.path}/incoming.jpg')
        ..writeAsBytesSync(Uint8List.fromList([0xff, 0xd8, 0xff]));
      final repos = RelioRepositories(db);
      final identity = RelioDeviceIdentityRepository(db);
      final service = NearbyService(
        transport: transport,
        messages: repos.messages,
        conversations: repos.conversations,
        identity: identity,
        nearbyDevices: repos.nearbyDevices,
        attachments: repos.attachments,
        mediaStorage: MediaStorageService(
          rootDirectory: Directory('${root.path}/managed'),
        ),
      );
      addTearDown(() async {
        await service.close();
        await db.close();
        await root.delete(recursive: true);
      });
      await service.initialize();
      transport.simulatePeer(id: 'endpoint-1', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      await service.connect('endpoint-1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      transport.simulateIncoming(
        peerId: 'endpoint-1',
        bytes: RelioPacket.hello(
          senderDeviceId: 'peer-device',
          senderUserId: 'peer-user',
          displayName: 'Peer',
        ).toBytes(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final packet = RelioPacket.mediaMetadata(
        senderDeviceId: 'peer-device',
        senderUserId: 'peer-user',
        messageId: 'incoming-message',
        attachmentId: 'incoming-attachment',
        transferId: 'incoming-transfer',
        mediaType: 'image',
        fileName: 'incoming.jpg',
        mimeType: 'image/jpeg',
        byteSize: 3,
        payloadId: 'native-payload-1',
      );

      transport.simulateIncomingFile(
        peerId: 'endpoint-1',
        payloadId: 'native-payload-1',
        filePath: source.path,
      );
      transport.simulateIncoming(peerId: 'endpoint-1', bytes: packet.toBytes());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(
        (await repos.messages.getMessage('incoming-message'))?.type,
        MessageType.image,
      );
      expect(
        (await repos.attachments.getById(
          'incoming-attachment',
        ))?.transferStatus,
        MediaTransferState.completed,
      );
    },
  );
}
