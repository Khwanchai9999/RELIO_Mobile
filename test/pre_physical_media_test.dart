import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/media/media_storage_service.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
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
    'media diagnostics keep transfer and file payload correlation',
    () async {
      final pair = await connectedPair();
      addTearDown(pair.close);
      final media = await prepareImage(pair);
      await pair.serviceA.sendMediaMessage(media.message, media.attachment);
      await waitFor(
        () async =>
            (await pair.repositoriesA.messages.getMessage(
              media.message.id,
            ))?.status ==
            DeliveryStatus.delivered,
      );

      final senderEvents = await readEvents(pair.logsA);
      final receiverEvents = await readEvents(pair.logsB);
      final fileSent = senderEvents.firstWhere(
        (event) => event['event'] == 'FILE_SEND_ACCEPTED',
      );
      final metadataSent = senderEvents.firstWhere(
        (event) => event['event'] == 'METADATA_SEND_SUCCESS',
      );
      final fileMatched = receiverEvents.firstWhere(
        (event) => event['event'] == 'METADATA_FILE_MATCHED',
      );
      final messageReady = receiverEvents.firstWhere(
        (event) => event['event'] == 'MESSAGE_READY_FOR_UI',
      );

      for (final fields in [
        fileSent,
        metadataSent,
        fileMatched,
        messageReady,
      ]) {
        expect(fields['traceId'], media.attachment.transferId);
        expect(fields['messageId'], media.message.id);
        expect(fields['attachmentId'], media.attachment.id);
      }
      expect(metadataSent['filePayloadId'], fileSent['payloadId']);
      expect(fileMatched['payloadId'], fileSent['payloadId']);
    },
  );

  for (final fileFirst in [false, true]) {
    test(
      'video persists, ACKs and deduplicates with fileFirst=$fileFirst without crossing account scope',
      () async {
        final pair = await connectedPair();
        addTearDown(pair.close);
        pair.transportA.fileBeforeMetadata = fileFirst;
        final bytes = [
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
        ];
        final source = File('${pair.logsA.directory!.path}/qa.mp4');
        await source.writeAsBytes(bytes);
        final storage = MediaStorageService(
          rootDirectory: Directory('${pair.logsA.directory!.path}/media'),
        );
        final managed = await storage.copySelectedFile(source.path);
        final attachment = await pair.repositoriesA.attachments.createPending(
          id: 'video-attachment',
          conversationId: 'device-b',
          messageId: 'video-message',
          transferId: 'video-transfer',
          mediaType: MediaType.video,
          fileName: 'qa.mp4',
          mimeType: 'video/mp4',
          localPath: managed,
          byteSize: bytes.length,
        );
        final message = await pair.repositoriesA.messages.createOutgoingMedia(
          conversationId: 'device-b',
          senderId: 'user-a',
          senderDeviceId: 'device-a',
          type: MessageType.video,
          fileName: 'qa.mp4',
          localPath: managed,
          attachmentId: attachment.id,
          messageId: attachment.messageId,
        );
        final receiverUpdate = Completer<RelioMessage>();
        final messageSubscription = pair.repositoriesB.messages
            .watchMessages('device-a')
            .listen((items) {
              for (final item in items) {
                if (item.id == message.id &&
                    item.localFilePath != null &&
                    !receiverUpdate.isCompleted) {
                  receiverUpdate.complete(item);
                }
              }
            });
        addTearDown(messageSubscription.cancel);
        for (var attempt = 1; attempt <= 2; attempt++) {
          await pair.serviceA.sendMediaMessage(message, attachment);
          await waitFor(
            () =>
                pair.transportB.packets
                    .where(
                      (packet) =>
                          packet.type == RelioPacketType.mediaAck &&
                          packet.payload['status'] == 'completed',
                    )
                    .length ==
                attempt,
          );
        }
        await waitFor(
          () async =>
              (await pair.repositoriesA.messages.getMessage(
                message.id,
              ))?.status ==
              DeliveryStatus.delivered,
        );
        final received = (await pair.repositoriesB.attachments.getById(
          attachment.id,
        ))!;
        expect(await File(received.localPath).readAsBytes(), bytes);
        final streamed = await receiverUpdate.future.timeout(
          const Duration(seconds: 2),
        );
        expect(streamed.localFilePath, received.localPath);
        expect(
          await pair.repositoriesB.messages.listMessages('device-a'),
          hasLength(1),
        );
        expect(await pair.repositoriesB.attachments.listAll(), hasLength(1));
        final otherAccount = RelioRepositories(
          pair.databaseB,
          ownerUserIdProvider: () => 'different-account',
        );
        expect(await otherAccount.messages.getMessage(message.id), isNull);
        expect(await otherAccount.conversations.listConversations(), isEmpty);
      },
    );
  }

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
      final receiverUpdate = Completer<RelioMessage>();
      final messageSubscription = pair.repositoriesB.messages
          .watchMessages('device-a')
          .listen((items) {
            for (final item in items) {
              if (item.id == media.message.id &&
                  item.localFilePath != null &&
                  !receiverUpdate.isCompleted) {
                receiverUpdate.complete(item);
              }
            }
          });
      addTearDown(messageSubscription.cancel);
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
      final streamed = await receiverUpdate.future.timeout(
        const Duration(seconds: 2),
      );
      expect(streamed.localFilePath, received.localPath);
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
      final failure = (await readEvents(
        pair.logsB,
      )).lastWhere((event) => event['event'] == 'media_receive_failed');
      expect(failure['checkpoint'], 'file_validation_and_storage');
      expect(failure['reason'], contains('SHA-256'));
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
      await waitForReconnect(pair);
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

Future<void> waitForReconnect(HandshakePair pair) async {
  await waitFor(
    () =>
        pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
        pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
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
    conversationId: 'device-b',
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
