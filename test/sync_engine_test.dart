import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/media/media_storage_service.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/core/sync/sync_engine.dart';
import 'package:relio_mobile/core/sync/sync_types.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
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
    expect(
      await harness.repositories.messages.getMessage(message.id),
      isNotNull,
    );
    expect(
      (await harness.repositories.syncQueue.listAll()).any(
        (item) => item.status == SyncQueueStatus.pending.value,
      ),
      isTrue,
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
}

class SyncHarness {
  SyncHarness._(
    this.database,
    this.cloud,
    this.repositories,
    this.engine,
    this.tempDirectory,
  );

  final AppDatabase database;
  final FakeCloudDataSource cloud;
  final RelioRepositories repositories;
  final SyncEngine engine;
  final Directory tempDirectory;

  static Future<SyncHarness> create({SyncClock? clock}) async {
    final database = AppDatabase.memory();
    final cloud = FakeCloudDataSource();
    final repositories = RelioRepositories(
      database,
      ownerUserIdProvider: () => cloud.currentIdentity?.userId,
    );
    final tempDirectory = await Directory.systemTemp.createTemp('relio-sync');
    final engine = SyncEngine(
      repositories: repositories,
      cloud: cloud,
      identity: RelioDeviceIdentityRepository(database),
      mediaStorage: MediaStorageService(rootDirectory: tempDirectory),
      clock: clock,
    );
    return SyncHarness._(database, cloud, repositories, engine, tempDirectory);
  }

  Future<RelioMessage> createMessage({required String senderId}) async {
    await repositories.conversations.ensureConversation(
      id: 'conversation-a',
      participantId: 'peer-a',
      displayName: 'Peer A',
      participantStatus: DeviceStatus.normal,
    );
    return repositories.messages.createOutgoingText(
      conversationId: 'conversation-a',
      senderId: senderId,
      senderDeviceId: 'device-a',
      text: 'local message',
    );
  }

  Future<void> dispose() async {
    await engine.dispose();
    await cloud.dispose();
    await database.close();
    await tempDirectory.delete(recursive: true);
  }
}

class TestSyncClock implements SyncClock {
  TestSyncClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}
