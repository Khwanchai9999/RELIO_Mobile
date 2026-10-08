import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
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
      await file.writeAsBytes([1, 2, 3]);
      final attachment = await harness.repositories.attachments.createPending(
        id: 'attachment-a',
        conversationId: message.conversationId!,
        messageId: message.id,
        transferId: 'transfer-a',
        mediaType: MediaType.image,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        localPath: file.path,
        byteSize: 3,
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
        .singleWhere((item) => item.entityId == message.id);

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
    await harness.createMessage(senderId: 'retry-owner');
    harness.cloud.failureMode = FakeCloudFailure.temporaryServer;

    await harness.engine.initialize();
    await harness.engine.run();

    final first = (await harness.repositories.syncQueue.listAll()).first;
    expect(first.status, SyncQueueStatus.pending.value);
    expect(first.attemptCount, 1);
    expect(
      first.nextAttemptAt!.toUtc(),
      clock.current.add(const Duration(seconds: 5)),
    );

    await harness.engine.run();
    final beforeDue = (await harness.repositories.syncQueue.listAll()).first;
    expect(beforeDue.attemptCount, 1);

    clock.current = first.nextAttemptAt!;
    await harness.engine.run();
    final second = (await harness.repositories.syncQueue.listAll()).first;
    expect(second.attemptCount, 2);
  });

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
        .singleWhere((item) => item.entityId == message.id);
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
      await file.writeAsBytes([1, 2, 3]);
      final attachment = await harness.repositories.attachments.createPending(
        id: 'attachment-a',
        conversationId: message.conversationId!,
        messageId: message.id,
        transferId: 'transfer-a',
        mediaType: MediaType.image,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        localPath: file.path,
        byteSize: 3,
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
      expect(harness.cloud.files[path], [1, 2, 3]);
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
