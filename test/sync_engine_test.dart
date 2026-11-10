import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/connectivity/qa_internet_simulator.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/media/media_storage_service.dart';
import 'package:relio_mobile/core/notifications/local_notification_service.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/core/sync/sync_engine.dart';
import 'package:relio_mobile/core/sync/sync_types.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  test(
    'QA simulated offline keeps local writes and blocks SyncEngine Cloud work',
    () async {
      final simulator = QaInternetSimulator.forTesting();
      final cloud = _CountingSyncCloud();
      final identity = await cloud.register(
        email: 'offline-qa@example.invalid',
        password: 'not-a-real-password',
        displayName: 'Offline QA',
      );
      cloud.operationCount = 0;
      final harness = await SyncHarness.create(
        cloud: cloud,
        internetSimulator: simulator,
      );
      addTearDown(() async {
        await harness.dispose();
        await cloud.dispose();
        simulator.dispose();
      });
      final conversation = await harness.repositories.conversations
          .ensureConversation(
            id: 'offline-local-chat',
            participantId: 'peer-device',
            displayName: 'Peer',
            participantStatus: DeviceStatus.normal,
          );
      await harness.repositories.cloudLinks.save(
        CloudConversationBinding(
          localConversationId: conversation.id,
          cloudConversationId: 'cloud-conversation',
          ownerUserId: identity.userId,
          peerUserId: 'peer-user',
        ),
      );
      simulator.setSimulatedOffline(true);
      await harness.engine.initialize();

      final message = await harness.repositories.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: identity.userId,
        senderDeviceId: 'local-device',
        text: 'D2D remains local while simulated offline',
      );
      await harness.engine.run();

      expect(
        await harness.repositories.messages.getMessage(message.id),
        isNotNull,
      );
      expect(cloud.operationCount, 0);
      expect(
        (await harness.repositories.syncQueue.listAll()).any(
          (item) => item.entityId == message.id && item.status == 'pending',
        ),
        isTrue,
      );
    },
  );

  test(
    'direct Cloud chat pulls, dedupes, and reconciles read receipts',
    () async {
      final backend = FakeCloudBackend();
      final cloudA = FakeCloudDataSource(backend: backend);
      final cloudB = FakeCloudDataSource(backend: backend);
      addTearDown(cloudA.dispose);
      addTearDown(cloudB.dispose);
      final accountA = await cloudA.register(
        email: 'a@example.com',
        password: 'password',
        displayName: 'Account A',
      );
      final accountB = cloudA.createTestIdentity(
        email: 'b@example.com',
        displayName: 'Account B',
      );
      final harnessA = await SyncHarness.create(cloud: cloudA);
      addTearDown(harnessA.dispose);

      final localConversation = await harnessA.repositories.conversations
          .ensureConversation(
            id: 'nearby-local-conversation',
            participantId: 'device-b',
            displayName: 'Account B',
            participantStatus: DeviceStatus.offline,
          );
      final linked = await harnessA.engine.linkConversationToCloud(
        localConversationId: localConversation.id,
        peerUserId: accountB.userId,
      );
      final secondLink = await cloudA.createOrGetDirectConversation(
        peerUserId: accountB.userId,
      );
      expect(secondLink.id, linked.cloudConversationId);
      String? activeConversationId;
      final notificationSink = RecordingNotificationSink();
      final harnessB = await SyncHarness.create(
        cloud: cloudB,
        isConversationActive: (id) => id == activeConversationId,
        localNotifications: notificationSink,
      );
      addTearDown(harnessB.dispose);

      final sent = await harnessA.repositories.messages.createOutgoingText(
        conversationId: localConversation.id,
        senderId: accountA.userId,
        senderDeviceId: 'device-a',
        text: 'ข้อความทดสอบ Cloud',
      );
      await harnessA.engine.initialize();
      await harnessA.engine.run();
      expect(
        cloudA.messages[sent.id]?.conversationId,
        linked.cloudConversationId,
      );

      await cloudB.signIn(email: accountB.email, password: 'password');
      await harnessB.engine.initialize();
      await harnessB.engine.run();
      final accountBLinks = await harnessB.repositories.cloudLinks.listForOwner(
        accountB.userId,
      );
      final importedLink = accountBLinks.single;
      activeConversationId = importedLink.localConversationId;
      final imported = await harnessB.repositories.conversations
          .getConversation(importedLink.localConversationId);
      expect(imported, isNotNull);
      final received = await harnessB.repositories.messages.getMessage(sent.id);
      expect(received?.text, 'ข้อความทดสอบ Cloud');
      expect(received?.outgoing, isFalse);
      expect(imported?.unreadCount, 1);
      expect(notificationSink.showCount, 1);
      expect(
        (await harnessB.repositories.cloudLinks.get(
          localConversationId: importedLink.localConversationId,
          ownerUserId: accountB.userId,
        ))?.messageCursor?.id,
        sent.id,
      );
      await harnessB.engine.run();
      expect(notificationSink.showCount, 1);

      await harnessB.repositories.messages.createIncomingText(
        conversationId: importedLink.localConversationId,
        senderId: accountA.userId,
        senderDeviceId: 'device-a',
        messageId: sent.id,
        text: sent.text,
        createdAt: sent.createdAt!,
      );
      expect(
        (await harnessB.repositories.conversations.getConversation(
          importedLink.localConversationId,
        ))?.unreadCount,
        1,
      );

      final readIds = await harnessB.repositories.messages.markConversationRead(
        importedLink.localConversationId,
      );
      await harnessB.engine.queueReadReceipts(
        localConversationId: importedLink.localConversationId,
        messageIds: readIds,
      );
      expect(cloudB.readReceipts, hasLength(1));

      await harnessA.engine.run();
      expect(
        (await harnessA.repositories.messages.getMessage(sent.id))?.readAt,
        isNotNull,
      );

      final second = await harnessA.repositories.messages.createOutgoingText(
        conversationId: localConversation.id,
        senderId: accountA.userId,
        senderDeviceId: 'device-a',
        text: 'ข้อความขณะเปิดแชท',
      );
      await harnessA.engine.run();
      await harnessB.engine.run();
      expect(
        (await harnessB.repositories.messages.getMessage(second.id))?.readAt,
        isNotNull,
      );
      expect(
        (await harnessB.repositories.conversations.getConversation(
          importedLink.localConversationId,
        ))?.unreadCount,
        0,
      );
      expect(notificationSink.showCount, 1);
      await harnessA.engine.run();
      expect(
        (await harnessA.repositories.messages.getMessage(second.id))?.readAt,
        isNotNull,
      );
    },
  );

  test(
    'private backup uploads without a shared binding and restores by owner',
    () async {
      final cloud = FakeCloudDataSource();
      final owner = await cloud.register(
        email: 'private-backup@example.com',
        password: 'password',
      );
      final source = await SyncHarness.create(cloud: cloud);
      addTearDown(source.dispose);
      final conversation = await source.repositories.conversations
          .ensureConversation(
            id: 'private-local-conversation',
            participantId: 'nearby-only-peer',
            displayName: 'Nearby peer',
            participantStatus: DeviceStatus.offline,
          );
      final message = await source.repositories.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: 'local-device-principal',
        senderDeviceId: 'stable-device-id',
        text: 'private history copy',
      );
      final mediaInputs = <(MessageType, String, List<int>)>[
        (MessageType.image, 'backup-photo.jpg', [0xff, 0xd8, 0xff]),
        (
          MessageType.video,
          'backup-clip.mp4',
          [0, 0, 0, 0, 102, 116, 121, 112, 105, 115, 111, 109],
        ),
      ];
      final mediaMessages = <RelioMessage>[];
      for (var i = 0; i < mediaInputs.length; i++) {
        final (type, name, bytes) = mediaInputs[i];
        final path = '${source.tempDirectory.path}/$name';
        await File(path).writeAsBytes(bytes);
        final mediaMessage = await source.repositories.messages
            .createOutgoingMedia(
              conversationId: conversation.id,
              senderId: 'local-device-principal',
              senderDeviceId: 'stable-device-id',
              type: type,
              fileName: name,
              localPath: path,
              attachmentId: 'backup-attachment-$i',
              messageId: 'backup-media-message-$i',
            );
        mediaMessages.add(mediaMessage);
        await source.repositories.attachments.createPending(
          id: 'backup-attachment-$i',
          conversationId: conversation.id,
          messageId: mediaMessage.id,
          transferId: 'backup-transfer-$i',
          mediaType: type == MessageType.video
              ? MediaType.video
              : MediaType.image,
          fileName: name,
          mimeType: type == MessageType.video ? 'video/mp4' : 'image/jpeg',
          localPath: path,
          byteSize: bytes.length,
        );
      }

      await source.engine.initialize();
      await source.engine.run();

      expect(cloud.privateBackupRecords, hasLength(4));
      expect(
        cloud.privateBackupRecords.keys,
        everyElement(startsWith(owner.userId)),
      );
      expect(cloud.messages, isEmpty);
      final queue = await source.repositories.syncQueue.listAll();
      expect(
        queue
            .where((row) => row.operation == SyncOperation.messageUpsert.value)
            .every((row) => row.status == SyncQueueStatus.pending.value),
        isTrue,
      );
      expect(
        queue
            .where(
              (row) => row.operation == SyncOperation.privateBackupUpsert.value,
            )
            .every((row) => row.status == SyncQueueStatus.completed.value),
        isTrue,
      );
      expect(
        cloud.files.keys.where((key) => key.contains('/private-backups/')),
        hasLength(2),
      );

      await cloud.signOut();
      final other = cloud.createTestIdentity(email: 'other@example.com');
      await cloud.signIn(email: other.email, password: 'password');
      expect(
        await cloud.fetchPrivateBackupRecords(recordType: 'message'),
        isEmpty,
      );
      await cloud.signOut();
      await cloud.signIn(email: owner.email, password: 'password');

      final restore = await SyncHarness.create(cloud: cloud);
      addTearDown(restore.dispose);
      final restoredCount = await restore.engine.restorePrivateBackup();
      expect(restoredCount, 3);
      final restoredConversation =
          (await restore.repositories.conversations.listConversations()).single;
      final restoredMessages = await restore.repositories.messages.listMessages(
        restoredConversation.id,
      );
      final restored = restoredMessages.singleWhere(
        (item) => item.id == message.id,
      );
      expect(restored.text, message.text);
      expect(restored.senderId, message.senderId);
      expect(restored.senderDeviceId, message.senderDeviceId);
      expect(restored.outgoing, isTrue);
      for (var i = 0; i < mediaMessages.length; i++) {
        final media = restoredMessages.singleWhere(
          (item) => item.id == mediaMessages[i].id,
        );
        expect(media.type, mediaMessages[i].type);
        expect(media.localFilePath, isNotNull);
        expect(
          await File(media.localFilePath!).readAsBytes(),
          mediaInputs[i].$3,
        );
        final attachment = await restore.repositories.attachments.getById(
          'backup-attachment-$i',
        );
        expect(attachment?.transferStatus, MediaTransferState.completed);
      }
    },
  );

  test('Fake Cloud denies nonmembers and supports keyset pagination', () async {
    final backend = FakeCloudBackend();
    final owner = FakeCloudDataSource(backend: backend);
    final peerClient = FakeCloudDataSource(backend: backend);
    final outsider = FakeCloudDataSource(backend: backend);
    final ownerIdentity = await owner.register(
      email: 'owner@example.com',
      password: 'password',
    );
    final peerIdentity = owner.createTestIdentity(email: 'peer@example.com');
    owner.createTestIdentity(email: 'outsider@example.com');
    final direct = await owner.createOrGetDirectConversation(
      peerUserId: peerIdentity.userId,
    );
    await peerClient.signIn(email: 'peer@example.com', password: 'password');
    await outsider.signIn(email: 'outsider@example.com', password: 'password');

    for (var index = 0; index < 3; index++) {
      await owner.upsertMessage(
        CloudMessageDto(
          id: 'stable-$index',
          conversationId: direct.id,
          senderId: ownerIdentity.userId,
          senderDeviceId: 'owner-device',
          messageType: 'text',
          content: 'message $index',
          createdAt: DateTime.utc(2026, 1, 1, 0, 0, index),
          updatedAt: DateTime.utc(2026, 1, 1, 0, 0, index),
          deliveryStatus: 'pending',
          isOutgoing: true,
        ),
      );
    }
    final firstPage = await peerClient.fetchMessagesPage(
      conversationId: direct.id,
      limit: 2,
    );
    expect(firstPage.messages, hasLength(2));
    expect(firstPage.hasMore, isTrue);
    final last = firstPage.messages.last;
    final secondPage = await peerClient.fetchMessagesPage(
      conversationId: direct.id,
      cursor: CloudMessageCursor(createdAt: last.createdAt, id: last.id),
      limit: 2,
    );
    expect(secondPage.messages, hasLength(1));
    expect(secondPage.hasMore, isFalse);
    await expectLater(
      outsider.fetchMessagesPage(conversationId: direct.id),
      throwsA(isA<CloudException>()),
    );
    await owner.dispose();
    await peerClient.dispose();
    await outsider.dispose();
  });

  test('authenticated data syncs only under its current owner', () async {
    final harness = await SyncHarness.create();
    addTearDown(harness.dispose);
    final identity = await harness.cloud.register(
      email: 'owner@example.com',
      password: 'password',
    );
    final message = await harness.createMessage(senderId: 'local-owner');

    await harness.engine.initialize();
    await harness.engine.run();

    expect(harness.cloud.messages[message.id]?.id, message.id);
    expect(harness.cloud.messages[message.id]?.senderId, identity.userId);
    expect(harness.cloud.conversations, isNotEmpty);
    final queue = await harness.repositories.syncQueue.listAll();
    expect(queue.every((item) => item.ownerUserId == identity.userId), isTrue);
    expect(
      queue.where(
        (item) => item.operation == SyncOperation.messageUpsert.value,
      ),
      hasLength(1),
    );
  });

  test(
    'owned message syncs while its legacy conversation and Guest rows stay unowned',
    () async {
      final harness = await SyncHarness.create();
      addTearDown(harness.dispose);
      final accountA = await harness.cloud.register(
        email: 'mixed-owner@example.com',
        password: 'password',
      );
      final peer = harness.cloud.createTestIdentity(
        email: 'mixed-peer@example.com',
      );
      final conversation = await harness.repositories.conversations
          .ensureConversation(
            id: 'mixed-conversation',
            participantId: 'mixed-peer-device',
            displayName: 'Peer',
            participantStatus: DeviceStatus.offline,
          );
      await harness.engine.linkConversationToCloud(
        localConversationId: conversation.id,
        peerUserId: peer.userId,
      );
      await harness.cloud.signOut();
      final guestOne = await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.profile.value,
        entityId: 'guest-one',
        operation: SyncOperation.profileUpsert.value,
      );
      final guestTwo = await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.profile.value,
        entityId: 'guest-two',
        operation: SyncOperation.profileUpsert.value,
      );
      final legacyConversation = await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.conversation.value,
        entityId: conversation.id,
        operation: SyncOperation.conversationUpsert.value,
      );
      await harness.cloud.signIn(
        email: 'mixed-owner@example.com',
        password: 'password',
      );
      final message = await harness.repositories.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: 'local-sender-label',
        senderDeviceId: 'mixed-owner-device',
        text: 'owned message with legacy Guest queue rows',
      );

      await harness.engine.initialize();
      await harness.engine.run();

      final messageQueue = (await harness.repositories.syncQueue.listAll())
          .singleWhere(
            (item) =>
                item.entityId == message.id &&
                item.operation == SyncOperation.messageUpsert.value,
          );
      expect(messageQueue.ownerUserId, accountA.userId);
      expect(messageQueue.status, SyncQueueStatus.completed.value);
      expect(harness.cloud.messages[message.id]?.senderId, accountA.userId);
      expect(
        (await harness.repositories.messages.getMessage(
          message.id,
        ))?.cloudSyncStatus,
        CloudSyncStatus.synced.value,
      );

      final rows = await harness.repositories.syncQueue.listAll();
      for (final guest in [guestOne, guestTwo, legacyConversation]) {
        final unchanged = rows.singleWhere((item) => item.id == guest.id);
        expect(unchanged.ownerUserId, isNull);
        expect(unchanged.status, SyncQueueStatus.pending.value);
      }
      expect(
        harness.engine.snapshot.state,
        SyncEngineState.waitingForOwnership,
      );
    },
  );

  test(
    'mixed Account A, Account B, and Guest rows process only the current owner',
    () async {
      final harness = await SyncHarness.create();
      addTearDown(harness.dispose);
      final guestOne = await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.profile.value,
        entityId: 'mixed-guest-one',
        operation: SyncOperation.profileUpsert.value,
      );
      final guestTwo = await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.profile.value,
        entityId: 'mixed-guest-two',
        operation: SyncOperation.profileUpsert.value,
      );
      final accountA = await harness.cloud.register(
        email: 'mixed-a@example.com',
        password: 'password',
      );
      final accountAQueue = await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.profile.value,
        entityId: 'account-a-profile',
        operation: SyncOperation.profileUpsert.value,
      );
      await harness.cloud.signOut();
      final accountB = await harness.cloud.register(
        email: 'mixed-b@example.com',
        password: 'password',
      );
      final accountBQueue = await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.profile.value,
        entityId: 'account-b-profile',
        operation: SyncOperation.profileUpsert.value,
      );

      await harness.engine.initialize();
      await harness.engine.run();
      var rows = await harness.repositories.syncQueue.listAll();
      expect(
        rows.singleWhere((item) => item.id == accountBQueue.id).status,
        SyncQueueStatus.completed.value,
      );
      expect(
        rows.singleWhere((item) => item.id == accountAQueue.id).status,
        SyncQueueStatus.pending.value,
      );
      for (final guest in [guestOne, guestTwo]) {
        final unchanged = rows.singleWhere((item) => item.id == guest.id);
        expect(unchanged.ownerUserId, isNull);
        expect(unchanged.status, SyncQueueStatus.pending.value);
      }
      expect(
        harness.engine.snapshot.state,
        SyncEngineState.waitingForOwnership,
      );

      await harness.cloud.signOut();
      await harness.cloud.signIn(
        email: 'mixed-a@example.com',
        password: 'password',
      );
      await harness.engine.run();
      await harness.engine.run();

      rows = await harness.repositories.syncQueue.listAll();
      expect(
        rows.singleWhere((item) => item.id == accountAQueue.id).status,
        SyncQueueStatus.completed.value,
      );
      expect(
        rows.singleWhere((item) => item.id == accountBQueue.id).ownerUserId,
        accountB.userId,
      );
      expect(
        rows.singleWhere((item) => item.id == accountBQueue.id).status,
        SyncQueueStatus.completed.value,
      );
      for (final guest in [guestOne, guestTwo]) {
        final unchanged = rows.singleWhere((item) => item.id == guest.id);
        expect(unchanged.ownerUserId, isNull);
        expect(unchanged.status, SyncQueueStatus.pending.value);
      }
      expect(accountA.userId, isNot(accountB.userId));
    },
  );

  test(
    'guest history stays local after a later login until explicit adoption',
    () async {
      final harness = await SyncHarness.create();
      addTearDown(harness.dispose);
      final message = await harness.createMessage(senderId: 'guest-device');
      expect(
        (await harness.repositories.syncQueue.listAll()).first.ownerUserId,
        isNull,
      );

      await harness.cloud.register(
        email: 'new@example.com',
        password: 'password',
      );
      final peer = harness.cloud.createTestIdentity(
        email: 'peer@example.com',
        displayName: 'Peer',
      );
      final currentIdentity = harness.cloud.currentIdentity!;
      await harness.repositories.conversations.adoptUnowned(
        currentIdentity.userId,
      );
      await harness.engine.linkConversationToCloud(
        localConversationId: 'conversation-a',
        peerUserId: peer.userId,
      );
      await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.message.value,
        entityId: message.id,
        operation: SyncOperation.messageUpsert.value,
      );
      await harness.engine.initialize();
      await harness.engine.run();

      expect(harness.cloud.messages, isEmpty);
      expect(
        harness.engine.snapshot.state,
        SyncEngineState.waitingForOwnership,
      );
      expect(
        (await harness.repositories.syncQueue.listAll()).first.ownerUserId,
        isNull,
      );

      await harness.engine.adoptGuestItemsAndRun();
      expect(harness.cloud.messages[message.id]?.id, message.id);
    },
  );

  test('account A queue cannot upload as account B', () async {
    final harness = await SyncHarness.create();
    addTearDown(harness.dispose);
    final accountA = await harness.cloud.register(
      email: 'a@example.com',
      password: 'password',
    );
    await harness.createMessage(senderId: 'account-a');
    await harness.cloud.signOut();
    await harness.cloud.register(email: 'b@example.com', password: 'password');

    await harness.engine.initialize();
    await harness.engine.run();

    expect(harness.cloud.messages, isEmpty);
    final queue = await harness.repositories.syncQueue.listAll();
    expect(queue.every((item) => item.ownerUserId == accountA.userId), isTrue);
  });

  test('sign-out stops sync and keeps the local queue', () async {
    final harness = await SyncHarness.create();
    addTearDown(harness.dispose);
    await harness.cloud.register(email: 'a@example.com', password: 'password');
    final message = await harness.createMessage(senderId: 'account-a');
    harness.cloud.failureMode = FakeCloudFailure.temporaryServer;

    await harness.engine.initialize();
    await harness.engine.run();
    await harness.cloud.signOut();
    harness.cloud.failureMode = FakeCloudFailure.none;
    await harness.engine.run();

    expect(harness.cloud.messages, isEmpty);
    expect(await harness.repositories.messages.getMessage(message.id), isNull);
    expect(
      (await harness.repositories.syncQueue.listAll()).any(
        (item) => item.status == SyncQueueStatus.pending.value,
      ),
      isTrue,
    );
    await harness.cloud.signIn(email: 'a@example.com', password: 'password');
    expect(
      await harness.repositories.messages.getMessage(message.id),
      isNotNull,
    );
  });

  test('unknown ownership blocks upload instead of guessing', () async {
    final harness = await SyncHarness.create();
    addTearDown(harness.dispose);
    await harness.repositories.syncQueue.enqueue(
      entityType: SyncEntityType.profile.value,
      entityId: 'profile',
      operation: SyncOperation.profileUpsert.value,
    );
    await harness.cloud.register(
      email: 'owner@example.com',
      password: 'password',
    );

    await harness.engine.initialize();
    await harness.engine.run();

    expect(harness.engine.snapshot.state, SyncEngineState.waitingForOwnership);
    expect(harness.cloud.messages, isEmpty);
    expect(
      (await harness.repositories.syncQueue.listAll()).single.ownerUserId,
      isNull,
    );
  });

  test(
    'attachment ownership must match its parent message ownership',
    () async {
      final harness = await SyncHarness.create();
      addTearDown(harness.dispose);
      final accountA = await harness.cloud.register(
        email: 'a@example.com',
        password: 'password',
      );
      final message = await harness.createMessage(senderId: 'account-a');
      final file = File('${harness.tempDirectory.path}/photo.jpg');
      const imageBytes = [0xff, 0xd8, 0xff];
      await file.writeAsBytes(imageBytes);
      final attachment = await harness.repositories.attachments.createPending(
        id: 'attachment-a',
        conversationId: message.conversationId!,
        messageId: message.id,
        transferId: 'transfer-a',
        mediaType: MediaType.image,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        localPath: file.path,
        byteSize: imageBytes.length,
      );
      await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.attachment.value,
        entityId: attachment.id,
        operation: SyncOperation.attachmentMetadataUpsert.value,
        ownerUserId: 'account-b',
      );

      await harness.engine.initialize();
      await harness.engine.run();

      expect(harness.cloud.attachments, isEmpty);
      final attachmentQueue = (await harness.repositories.syncQueue.listAll())
          .singleWhere((item) => item.entityId == attachment.id);
      expect(attachmentQueue.ownerUserId, 'account-b');
      expect(accountA.userId, isNotEmpty);
    },
  );

  test('retry cannot bypass ownership after account switching', () async {
    final harness = await SyncHarness.create();
    addTearDown(harness.dispose);
    final accountA = await harness.cloud.register(
      email: 'a@example.com',
      password: 'password',
    );
    final message = await harness.createMessage(senderId: 'account-a');
    harness.cloud.failureMode = FakeCloudFailure.temporaryServer;
    await harness.engine.initialize();
    await harness.engine.run();
    final failedAttempt = (await harness.repositories.syncQueue.listAll())
        .singleWhere(
          (item) =>
              item.entityId == message.id &&
              item.operation == SyncOperation.messageUpsert.value,
        );

    harness.cloud.failureMode = FakeCloudFailure.none;
    await harness.cloud.signOut();
    await harness.cloud.register(email: 'b@example.com', password: 'password');
    await harness.repositories.syncQueue.retry(failedAttempt.id);
    await harness.engine.run();

    final retried = (await harness.repositories.syncQueue.listAll())
        .singleWhere((item) => item.id == failedAttempt.id);
    expect(retried.ownerUserId, accountA.userId);
    expect(harness.cloud.messages, isEmpty);
  });

  test('transient failure uses persisted backoff before retrying', () async {
    final clock = TestSyncClock(DateTime.utc(2026, 1, 1));
    final harness = await SyncHarness.create(clock: clock);
    addTearDown(harness.dispose);
    await harness.cloud.register(
      email: 'retry@example.com',
      password: 'password',
    );
    final message = await harness.createMessage(senderId: 'retry-owner');
    harness.cloud.failureMode = FakeCloudFailure.temporaryServer;

    await harness.engine.initialize();
    await harness.engine.run();

    final first = (await harness.repositories.syncQueue.listAll()).singleWhere(
      (item) =>
          item.entityId == message.conversationId &&
          item.operation == SyncOperation.conversationUpsert.value,
    );
    expect(first.status, SyncQueueStatus.pending.value);
    expect(first.attemptCount, 1);
    expect(
      first.nextAttemptAt!.toUtc(),
      clock.current.add(const Duration(seconds: 5)),
    );

    await harness.engine.run();
    final beforeDue = (await harness.repositories.syncQueue.listAll())
        .singleWhere((item) => item.id == first.id);
    expect(beforeDue.attemptCount, 1);

    clock.current = first.nextAttemptAt!;
    await harness.engine.run();
    final second = (await harness.repositories.syncQueue.listAll()).singleWhere(
      (item) => item.id == first.id,
    );
    expect(second.attemptCount, 2);
  });

  test(
    'offline message remains queued then syncs once when Cloud returns',
    () async {
      final clock = TestSyncClock(DateTime.utc(2026, 1, 1));
      final harness = await SyncHarness.create(clock: clock);
      addTearDown(harness.dispose);
      final owner = await harness.cloud.register(
        email: 'offline-sync@example.com',
        password: 'password',
      );
      final peer = harness.cloud.createTestIdentity(
        email: 'offline-sync-peer@example.com',
        displayName: 'Peer',
      );
      final conversation = await harness.repositories.conversations
          .ensureConversation(
            id: 'offline-conversation',
            participantId: 'offline-peer-device',
            displayName: 'Peer',
            participantStatus: DeviceStatus.offline,
          );
      await harness.engine.linkConversationToCloud(
        localConversationId: conversation.id,
        peerUserId: peer.userId,
      );

      harness.cloud.offline = true;
      final message = await harness.repositories.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: owner.userId,
        senderDeviceId: 'offline-owner-device',
        text: 'offline queued message',
      );
      await harness.engine.initialize();
      await harness.engine.run();

      final queued = (await harness.repositories.syncQueue.listAll())
          .singleWhere(
            (item) =>
                item.entityId == message.id &&
                item.operation == SyncOperation.messageUpsert.value,
          );
      expect(queued.ownerUserId, owner.userId);
      expect(queued.status, SyncQueueStatus.pending.value);
      expect(
        (await harness.repositories.syncQueue.listAll()).any(
          (item) =>
              item.status == SyncQueueStatus.pending.value &&
              item.nextAttemptAt != null,
        ),
        isTrue,
      );
      expect(harness.cloud.messages, isEmpty);
      expect(
        (await harness.repositories.messages.getMessage(
          message.id,
        ))?.cloudSyncStatus,
        CloudSyncStatus.pending.value,
      );

      harness.cloud.offline = false;
      final retryAt = (await harness.repositories.syncQueue.listAll())
          .where(
            (item) => item.operation == SyncOperation.conversationUpsert.value,
          )
          .map((item) => item.nextAttemptAt)
          .whereType<DateTime>()
          .first;
      clock.current = retryAt;
      await harness.engine.run();
      var synced = await harness.repositories.messages.getMessage(message.id);
      expect(synced?.cloudSyncStatus, CloudSyncStatus.synced.value);
      expect(synced?.status, DeliveryStatus.pending);
      expect(harness.cloud.messages.keys.where((id) => id == message.id), [
        message.id,
      ]);
      final completed = (await harness.repositories.syncQueue.listAll())
          .singleWhere(
            (item) =>
                item.entityId == message.id &&
                item.operation == SyncOperation.messageUpsert.value,
          );
      expect(completed.status, SyncQueueStatus.completed.value);

      await harness.engine.run();
      synced = await harness.repositories.messages.getMessage(message.id);
      expect(synced?.cloudSyncStatus, CloudSyncStatus.synced.value);
      expect(harness.cloud.messages.keys.where((id) => id == message.id), [
        message.id,
      ]);
    },
  );

  test('retry after a successful cloud upsert remains idempotent', () async {
    final harness = await SyncHarness.create();
    addTearDown(harness.dispose);
    await harness.cloud.register(
      email: 'idempotent@example.com',
      password: 'password',
    );
    final message = await harness.createMessage(senderId: 'owner');

    await harness.engine.initialize();
    await harness.engine.run();
    final messageQueue = (await harness.repositories.syncQueue.listAll())
        .singleWhere(
          (item) =>
              item.entityId == message.id &&
              item.operation == SyncOperation.messageUpsert.value,
        );
    await harness.repositories.syncQueue.retry(messageQueue.id);
    await harness.engine.run();

    expect(harness.cloud.messages, hasLength(1));
    expect(harness.cloud.messages[message.id]?.id, message.id);
  });

  test(
    'attachment sync uses a verified owner path and managed local file',
    () async {
      final harness = await SyncHarness.create();
      addTearDown(harness.dispose);
      final identity = await harness.cloud.register(
        email: 'media@example.com',
        password: 'password',
      );
      final message = await harness.createMessage(senderId: 'local-label');
      final file = File('${harness.tempDirectory.path}/photo.jpg');
      const imageBytes = [0xff, 0xd8, 0xff];
      await file.writeAsBytes(imageBytes);
      final attachment = await harness.repositories.attachments.createPending(
        id: 'attachment-a',
        conversationId: message.conversationId!,
        messageId: message.id,
        transferId: 'transfer-a',
        mediaType: MediaType.image,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        localPath: file.path,
        byteSize: imageBytes.length,
      );
      await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.attachment.value,
        entityId: attachment.id,
        operation: SyncOperation.attachmentMetadataUpsert.value,
      );
      await harness.repositories.syncQueue.enqueue(
        entityType: SyncEntityType.attachment.value,
        entityId: attachment.id,
        operation: SyncOperation.attachmentUpload.value,
      );

      await harness.engine.initialize();
      await harness.engine.run();

      final path =
          'users/${identity.userId}/messages/${message.id}/attachment-a-photo.jpg';
      expect(harness.cloud.attachments[attachment.id]?.storagePath, path);
      expect(harness.cloud.files[path], imageBytes);
    },
  );

  test('missing queued message becomes an explicit terminal failure', () async {
    final harness = await SyncHarness.create();
    addTearDown(harness.dispose);
    await harness.cloud.register(
      email: 'missing-message@example.com',
      password: 'password',
    );
    final row = await harness.repositories.syncQueue.enqueue(
      entityType: SyncEntityType.message.value,
      entityId: 'deleted-local-message',
      operation: SyncOperation.messageUpsert.value,
    );

    await harness.engine.initialize();
    await harness.engine.run();

    final failed = (await harness.repositories.syncQueue.listAll()).singleWhere(
      (item) => item.id == row.id,
    );
    expect(failed.status, SyncQueueStatus.failed.value);
    expect(failed.lastError, 'message_missing');
  });

  test(
    'malformed conversation and unsupported location fail explicitly',
    () async {
      final harness = await SyncHarness.create();
      addTearDown(harness.dispose);
      await harness.cloud.register(
        email: 'malformed-message@example.com',
        password: 'password',
      );
      final conversation = await harness.repositories.conversations
          .ensureConversation(
            id: 'malformed-conversation',
            participantId: 'malformed-peer',
            displayName: 'Peer',
            participantStatus: DeviceStatus.offline,
          );
      final message = await harness.repositories.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: 'local',
        senderDeviceId: 'device-local',
        text: 'bad local reference',
      );
      await harness.database.customStatement(
        'UPDATE messages SET conversation_id = ? WHERE id = ?',
        ['', message.id],
      );
      final location = await harness.repositories.messages
          .createOutgoingLocation(
            conversationId: conversation.id,
            senderId: 'local',
            senderDeviceId: 'device-local',
            location: LocationData(
              latitude: 13.7,
              longitude: 100.5,
              capturedAt: DateTime.utc(2026),
            ),
          );

      await harness.engine.initialize();
      await harness.engine.run();

      final queue = await harness.repositories.syncQueue.listAll();
      final malformed = queue.singleWhere(
        (item) => item.entityId == message.id,
      );
      final unsupported = queue.singleWhere(
        (item) => item.entityId == location.id,
      );
      expect(malformed.status, SyncQueueStatus.failed.value);
      expect(malformed.lastError, 'conversation_id_missing');
      expect(unsupported.status, SyncQueueStatus.failed.value);
      expect(unsupported.lastError, 'unsupported_location_cloud_sync');
      expect(
        (await harness.repositories.messages.getMessage(
          location.id,
        ))?.cloudSyncStatus,
        CloudSyncStatus.failed.value,
      );
    },
  );

  test(
    'recoverable Cloud binding wait resumes after supported link flow',
    () async {
      final harness = await SyncHarness.create();
      addTearDown(harness.dispose);
      final owner = await harness.cloud.register(
        email: 'recoverable-binding@example.com',
        password: 'password',
      );
      final conversation = await harness.repositories.conversations
          .ensureConversation(
            id: 'recoverable-conversation',
            participantId: 'recoverable-peer',
            displayName: 'Peer',
            participantStatus: DeviceStatus.offline,
          );
      final message = await harness.repositories.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: owner.userId,
        senderDeviceId: 'device-owner',
        text: 'wait for explicit link',
      );

      await harness.engine.initialize();
      await harness.engine.run();
      expect(harness.engine.snapshot.state, SyncEngineState.waitingForBinding);
      var messageRow = (await harness.repositories.syncQueue.listAll())
          .singleWhere(
            (item) =>
                item.entityId == message.id &&
                item.operation == SyncOperation.messageUpsert.value,
          );
      expect(messageRow.status, SyncQueueStatus.pending.value);
      expect(messageRow.lastError, isNull);

      final peer = harness.cloud.createTestIdentity(
        email: 'recoverable-peer@example.com',
      );
      await harness.engine.linkConversationToCloud(
        localConversationId: conversation.id,
        peerUserId: peer.userId,
      );
      messageRow = (await harness.repositories.syncQueue.listAll()).singleWhere(
        (item) =>
            item.entityId == message.id &&
            item.operation == SyncOperation.messageUpsert.value,
      );
      expect(messageRow.status, SyncQueueStatus.completed.value);
      expect(harness.cloud.messages[message.id]?.senderId, owner.userId);
    },
  );

  for (final mediaType in [MessageType.image, MessageType.video]) {
    test(
      '${mediaType.name} Cloud message, object, and metadata complete once',
      () async {
        final harness = await SyncHarness.create();
        addTearDown(harness.dispose);
        final owner = await harness.cloud.register(
          email: '${mediaType.name}-cloud@example.com',
          password: 'password',
        );
        final conversation = await harness.repositories.conversations
            .ensureConversation(
              id: '${mediaType.name}-conversation',
              participantId: '${mediaType.name}-peer',
              displayName: 'Peer',
              participantStatus: DeviceStatus.offline,
            );
        final peer = harness.cloud.createTestIdentity(
          email: '${mediaType.name}-peer@example.com',
        );
        await harness.engine.linkConversationToCloud(
          localConversationId: conversation.id,
          peerUserId: peer.userId,
        );
        final messageId = '${mediaType.name}-message';
        final attachmentId = '${mediaType.name}-attachment';
        final fileName = mediaType == MessageType.image
            ? 'photo.jpg'
            : 'clip.mp4';
        final file = File('${harness.tempDirectory.path}/$fileName');
        final fileBytes = mediaType == MessageType.image
            ? [0xff, 0xd8, 0xff]
            : [0, 0, 0, 0, 102, 116, 121, 112, 105, 115, 111, 109];
        await file.writeAsBytes(fileBytes);
        await harness.repositories.attachments.createPending(
          id: attachmentId,
          conversationId: conversation.id,
          messageId: messageId,
          transferId: '${mediaType.name}-transfer',
          mediaType: mediaType == MessageType.image
              ? MediaType.image
              : MediaType.video,
          fileName: fileName,
          mimeType: mediaType == MessageType.image ? 'image/jpeg' : 'video/mp4',
          localPath: file.path,
          byteSize: fileBytes.length,
        );
        final message = await harness.repositories.messages.createOutgoingMedia(
          conversationId: conversation.id,
          senderId: owner.userId,
          senderDeviceId: 'device-owner',
          type: mediaType,
          fileName: fileName,
          localPath: file.path,
          attachmentId: attachmentId,
          messageId: messageId,
        );

        await harness.engine.initialize();
        await harness.engine.run();

        final cloudMessage = harness.cloud.messages[message.id];
        final cloudAttachment = harness.cloud.attachments[attachmentId];
        expect(cloudMessage?.messageType, mediaType.name);
        expect(cloudMessage?.senderId, owner.userId);
        expect(cloudAttachment?.messageId, message.id);
        expect(harness.cloud.files[cloudAttachment!.storagePath], fileBytes);
        final queue = await harness.repositories.syncQueue.listAll();
        expect(
          queue
              .where(
                (row) =>
                    row.entityId == message.id &&
                    row.operation == SyncOperation.messageUpsert.value,
              )
              .single
              .status,
          SyncQueueStatus.completed.value,
        );
        expect(
          queue
              .where((row) => row.entityId == attachmentId)
              .every((row) => row.status == SyncQueueStatus.completed.value),
          isTrue,
        );
        await harness.engine.run();
        expect(harness.cloud.messages, hasLength(1));
        expect(harness.cloud.attachments, hasLength(1));
        expect(harness.cloud.files, hasLength(2));
      },
    );
  }

  test(
    'authorized Cloud media is pulled, verified, and stored locally',
    () async {
      final backend = FakeCloudBackend();
      final cloudA = FakeCloudDataSource(backend: backend);
      final cloudB = FakeCloudDataSource(backend: backend);
      addTearDown(cloudA.dispose);
      addTearDown(cloudB.dispose);
      final accountA = await cloudA.register(
        email: 'media-sender@example.com',
        password: 'password',
      );
      final accountB = cloudA.createTestIdentity(
        email: 'media-recipient@example.com',
      );
      final harnessA = await SyncHarness.create(cloud: cloudA);
      final retryClock = TestSyncClock(DateTime.utc(2026, 11, 2));
      final harnessB = await SyncHarness.create(
        cloud: cloudB,
        clock: retryClock,
      );
      addTearDown(harnessA.dispose);
      addTearDown(harnessB.dispose);

      final conversation = await harnessA.repositories.conversations
          .ensureConversation(
            id: 'media-sender-conversation',
            participantId: 'recipient-device',
            displayName: 'Recipient',
            participantStatus: DeviceStatus.offline,
          );
      final linkA = await harnessA.engine.linkConversationToCloud(
        localConversationId: conversation.id,
        peerUserId: accountB.userId,
      );
      const attachmentId = 'shared-cloud-image';
      const messageId = 'shared-cloud-image-message';
      const bytes = [137, 80, 78, 71, 13, 10, 26, 10];
      final source = File('${harnessA.tempDirectory.path}/shared.png');
      await source.writeAsBytes(bytes);
      await harnessA.repositories.attachments.createPending(
        id: attachmentId,
        conversationId: conversation.id,
        messageId: messageId,
        transferId: 'shared-cloud-image-transfer',
        mediaType: MediaType.image,
        fileName: 'shared.png',
        mimeType: 'image/png',
        localPath: source.path,
        byteSize: bytes.length,
      );
      await harnessA.repositories.messages.createOutgoingMedia(
        conversationId: conversation.id,
        senderId: accountA.userId,
        senderDeviceId: 'sender-device',
        type: MessageType.image,
        fileName: 'shared.png',
        localPath: source.path,
        attachmentId: attachmentId,
        messageId: messageId,
      );
      await harnessA.engine.initialize();
      await harnessA.engine.run();
      final remoteAttachment = cloudA.attachments[attachmentId]!;
      expect(remoteAttachment.storagePath, contains(accountA.userId));
      expect(remoteAttachment.sha256, isNotNull);
      expect(cloudA.files[remoteAttachment.storagePath], bytes);

      await cloudB.signIn(email: accountB.email, password: 'password');
      cloudB.failureMode = FakeCloudFailure.downloadFailure;
      await harnessB.engine.initialize();
      await harnessB.engine.run();
      final linkB = (await harnessB.repositories.cloudLinks.listForOwner(
        accountB.userId,
      )).single;
      expect(linkB.cloudConversationId, linkA.cloudConversationId);
      var downloadQueue = (await harnessB.repositories.syncQueue.listAll())
          .singleWhere(
            (row) =>
                row.entityId == attachmentId &&
                row.operation == SyncOperation.attachmentDownload.value,
          );
      expect(downloadQueue.status, SyncQueueStatus.pending.value);
      expect(downloadQueue.nextAttemptAt, isNotNull);
      expect(
        (await harnessB.repositories.attachments.getById(
          attachmentId,
        ))?.cloudFileStatus,
        'downloadPending',
      );
      cloudB.failureMode = FakeCloudFailure.none;
      retryClock.current = downloadQueue.nextAttemptAt!.add(
        const Duration(seconds: 1),
      );
      await harnessB.engine.run();

      final receivedMessage = await harnessB.repositories.messages.getMessage(
        messageId,
      );
      final receivedAttachment = await harnessB.repositories.attachments
          .getById(attachmentId);
      expect(receivedMessage?.type, MessageType.image);
      expect(receivedMessage?.localFilePath, isNotEmpty);
      expect(receivedAttachment?.cloudFileStatus, 'synced');
      expect(receivedAttachment?.transferStatus, MediaTransferState.completed);
      expect(receivedAttachment?.checksumSha256, remoteAttachment.sha256);
      expect(await File(receivedMessage!.localFilePath!).readAsBytes(), bytes);
      downloadQueue = (await harnessB.repositories.syncQueue.listAll())
          .singleWhere(
            (row) =>
                row.entityId == attachmentId &&
                row.operation == SyncOperation.attachmentDownload.value,
          );
      expect(downloadQueue.status, SyncQueueStatus.completed.value);
    },
  );
}

class SyncHarness {
  SyncHarness._(
    this.database,
    this.cloud,
    this.repositories,
    this.engine,
    this.tempDirectory,
    this.ownsCloud,
  );

  final AppDatabase database;
  final FakeCloudDataSource cloud;
  final RelioRepositories repositories;
  final SyncEngine engine;
  final Directory tempDirectory;
  final bool ownsCloud;

  static Future<SyncHarness> create({
    SyncClock? clock,
    FakeCloudDataSource? cloud,
    QaInternetSimulator? internetSimulator,
    bool Function(String conversationId)? isConversationActive,
    LocalNotificationSink? localNotifications,
  }) async {
    final database = AppDatabase.memory();
    final activeCloud = cloud ?? FakeCloudDataSource();
    final repositories = RelioRepositories(
      database,
      ownerUserIdProvider: () => activeCloud.currentIdentity?.userId,
    );
    final tempDirectory = await Directory.systemTemp.createTemp('relio-sync');
    final engine = SyncEngine(
      repositories: repositories,
      cloud: activeCloud,
      identity: RelioDeviceIdentityRepository(database),
      mediaStorage: MediaStorageService(rootDirectory: tempDirectory),
      isConversationActive: isConversationActive,
      localNotifications: localNotifications,
      clock: clock,
      internetSimulator: internetSimulator,
    );
    return SyncHarness._(
      database,
      activeCloud,
      repositories,
      engine,
      tempDirectory,
      cloud == null,
    );
  }

  Future<RelioMessage> createMessage({required String senderId}) async {
    final conversation = await repositories.conversations.ensureConversation(
      id: 'conversation-a',
      participantId: 'peer-a',
      displayName: 'Peer A',
      participantStatus: DeviceStatus.normal,
    );
    final current = cloud.currentIdentity;
    if (current != null) {
      final peer = cloud.createTestIdentity(
        email: 'peer-${current.userId}@example.com',
        displayName: 'Peer',
      );
      await engine.linkConversationToCloud(
        localConversationId: conversation.id,
        peerUserId: peer.userId,
      );
    }
    return repositories.messages.createOutgoingText(
      conversationId: conversation.id,
      senderId: senderId,
      senderDeviceId: 'device-a',
      text: 'local message',
    );
  }

  Future<void> dispose() async {
    await engine.dispose();
    if (ownsCloud) await cloud.dispose();
    await database.close();
    await tempDirectory.delete(recursive: true);
  }
}

class _CountingSyncCloud extends FakeCloudDataSource {
  int operationCount = 0;

  @override
  Future<List<CloudConversationDto>> listMyDirectConversations() {
    operationCount++;
    return super.listMyDirectConversations();
  }
}

class RecordingNotificationSink implements LocalNotificationSink {
  int showCount = 0;

  @override
  Stream<String> get tappedRoutes => const Stream<String>.empty();

  @override
  Future<String?> consumeInitialRoute() async => null;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> get notificationsAllowed async => true;

  @override
  Future<String?> getFcmToken() async => null;

  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
    required String route,
    required bool urgent,
    required bool soundEnabled,
    required bool vibrationEnabled,
  }) async {
    showCount++;
  }
}

class TestSyncClock implements SyncClock {
  TestSyncClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}
