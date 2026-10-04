import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/media/media_storage_service.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

import 'support/nearby_pair.dart';
import 'support/recording_notifications.dart';

// ภาพ PNG จริงขนาด 1 pixel เพื่อทดสอบ bytes ที่ปลายทางได้รับ
final imageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII=',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'repeated image transfer has one attachment, unread and notification',
    () async {
      final sink = RecordingNotifications();
      addTearDown(sink.taps.close);
      final pair = await connectedPair(notifications: sink);
      addTearDown(pair.close);
      final media = await prepareImage(pair);
      await pair.serviceA.sendMediaMessage(media.message, media.attachment);
      await waitFor(
        () =>
            pair.transportB.packets
                .where((p) => p.type == RelioPacketType.mediaAck)
                .length ==
            1,
      );
      await pair.serviceA.sendMediaMessage(media.message, media.attachment);
      await waitFor(
        () =>
            pair.transportB.packets
                .where((p) => p.type == RelioPacketType.mediaAck)
                .length ==
            2,
      );
      expect(
        await pair.repositoriesB.messages.listMessages('device-a'),
        hasLength(1),
      );
      expect(await pair.repositoriesB.attachments.listAll(), hasLength(1));
      expect(
        (await pair.repositoriesB.conversations.getConversation(
          'device-a',
        ))!.unreadCount,
        1,
      );
      expect(sink.shown, hasLength(1));
    },
  );

  for (final fileFirst in [false, true]) {
    test('image bytes persist on receiver with fileFirst=$fileFirst', () async {
      final pair = await connectedPair();
      addTearDown(pair.close);
      pair.transportA.fileBeforeMetadata = fileFirst;
      final media = await prepareImage(pair);
      await pair.serviceA.sendMediaMessage(media.message, media.attachment);
      await waitFor(
        () async =>
            (await pair.repositoriesA.messages.getMessage(
              media.message.id,
            ))?.status ==
            DeliveryStatus.delivered,
      );
      final received = (await pair.repositoriesB.attachments.getById(
        media.attachment.id,
      ))!;
      expect(
        received.localPath,
        startsWith('${pair.logsB.directory!.path}/media'),
      );
      expect(received.localPath, isNot(media.attachment.localPath));
      expect(await File(received.localPath).readAsBytes(), imageBytes);
      expect(
        (await pair.repositoriesB.messages.getMessage(
          media.message.id,
        ))?.localFilePath,
        received.localPath,
      );
      final metadata = pair.transportA.packets.firstWhere(
        (p) => p.type == RelioPacketType.mediaMetadata,
      );
      expect(metadata.payload['sha256'], sha256.convert(imageBytes).toString());
      expect(
        jsonEncode(metadata.payload),
        isNot(contains(media.attachment.localPath)),
      );
    });
  }

  test(
    'same-size corrupt image must fail integrity and never complete',
    () async {
      final pair = await connectedPair();
      addTearDown(pair.close);
      pair.transportA.corruptFile = true;
      final media = await prepareImage(pair);
      await pair.serviceA.sendMediaMessage(media.message, media.attachment);
      await waitFor(
        () => pair.transportB.packets.any(
          (p) => p.type == RelioPacketType.mediaAck,
        ),
      );
      final ack = pair.transportB.packets.lastWhere(
        (p) => p.type == RelioPacketType.mediaAck,
      );
      expect(ack.payload['status'], 'failed');
      expect(
        await pair.repositoriesB.messages.getMessage(media.message.id),
        isNull,
      );
    },
  );

  test(
    'metadata alone cannot ACK; interruption preserves message and retries same UUID',
    () async {
      final pair = await connectedPair();
      addTearDown(pair.close);
      pair.transportA.holdFiles = true;
      final media = await prepareImage(pair);
      await pair.serviceA.sendMediaMessage(media.message, media.attachment);
      await waitFor(
        () async => (await readEvents(
          pair.logsB,
        )).any((e) => e['event'] == 'media_metadata_received'),
      );
      expect(
        pair.transportB.packets.where(
          (p) => p.type == RelioPacketType.mediaAck,
        ),
        isEmpty,
      );
      pair.transportA.failTransfers();
      await pair.serviceA.disconnect('endpoint-b');
      await waitFor(
        () async =>
            (await pair.repositoriesA.attachments.getById(
              media.attachment.id,
            ))?.transferStatus ==
            MediaTransferState.failed,
      );
      expect(
        await pair.repositoriesA.conversations.getConversation('device-b'),
        isNotNull,
      );
      expect(
        (await pair.repositoriesA.messages.getMessage(
          media.message.id,
        ))?.status,
        DeliveryStatus.failed,
      );
      pair.transportB.discoverPeer();
      await waitFor(
        () =>
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
            pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
      );
      pair.transportA.holdFiles = false;
      await pair.serviceA.retryMessage(media.message.id);
      await waitFor(
        () async =>
            (await pair.repositoriesA.messages.getMessage(
              media.message.id,
            ))?.status ==
            DeliveryStatus.delivered,
      );
      expect(
        await pair.repositoriesB.messages.listMessages('device-a'),
        hasLength(1),
      );
      expect(await pair.repositoriesB.attachments.listAll(), hasLength(1));
    },
  );
}

Future<HandshakePair> connectedPair({
  RecordingNotifications? notifications,
}) async {
  final pair = await HandshakePair.create(notificationsB: notifications);
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
  // การจับคู่ต้องผ่าน hello ก่อนส่งสื่อของผู้ใช้
  await waitFor(
    () =>
        pair.transportA.sentPackets.contains('hello') &&
        pair.transportB.sentPackets.contains('hello'),
  );
  return pair;
}

Future<({RelioMessage message, RelioMediaAttachment attachment})> prepareImage(
  HandshakePair pair,
) async {
  final picked = File('${pair.logsA.directory!.path}/picked.png');
  await picked.writeAsBytes(imageBytes);
  final storage = MediaStorageService(
    rootDirectory: Directory('${pair.logsA.directory!.path}/media'),
  );
  final managed = await storage.copySelectedFile(picked.path);
  final attachment = await pair.repositoriesA.attachments.createPending(
    id: 'image-attachment',
    messageId: 'image-message',
    transferId: 'image-transfer',
    mediaType: MediaType.image,
    fileName: 'photo.png',
    mimeType: 'image/png',
    localPath: managed,
    byteSize: imageBytes.length,
  );
  final message = await pair.repositoriesA.messages.createOutgoingMedia(
    conversationId: 'device-b',
    senderId: 'user-a',
    senderDeviceId: 'device-a',
    type: MessageType.image,
    fileName: 'photo.png',
    localPath: managed,
    attachmentId: attachment.id,
    messageId: attachment.messageId,
  );
  return (message: message, attachment: attachment);
}
