import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/core/sync/sync_types.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

import 'test_database.dart';

void main() {
  test(
    'local conversations and messages are partitioned by cloud account',
    () async {
      final database = AppDatabase.memory();
      addTearDown(database.close);
      var activeOwner = 'account-a';
      final repositories = RelioRepositories(
        database,
        ownerUserIdProvider: () => activeOwner,
      );

      final accountAConversation = await repositories.conversations
          .ensureConversation(
            id: 'peer-device',
            participantId: 'peer-device',
            displayName: 'Peer A',
            participantStatus: DeviceStatus.offline,
          );
      await repositories.messages.createOutgoingText(
        conversationId: accountAConversation.id,
        senderId: 'account-a',
        senderDeviceId: 'local-device',
        text: 'A private message',
      );

      activeOwner = 'account-b';
      expect(await repositories.conversations.listConversations(), isEmpty);
      expect(
        await repositories.conversations.getConversation(
          accountAConversation.id,
        ),
        isNull,
      );
      expect(
        await repositories.messages.listMessages(accountAConversation.id),
        isEmpty,
      );

      final accountBConversation = await repositories.conversations
          .ensureConversation(
            id: 'peer-device',
            participantId: 'peer-device',
            displayName: 'Peer B',
            participantStatus: DeviceStatus.offline,
          );
      expect(accountBConversation.id, isNot(accountAConversation.id));
      final routedConversation = await repositories.conversations
          .resolveRouteTarget('peer-device');
      expect(routedConversation.id, accountBConversation.id);
      expect(routedConversation.id, isNot(accountAConversation.id));
      await repositories.messages.createOutgoingText(
        conversationId: accountBConversation.id,
        senderId: 'account-b',
        senderDeviceId: 'local-device',
        text: 'B private message',
      );
      expect(
        (await repositories.messages.listMessages(
          accountBConversation.id,
        )).single.text,
        'B private message',
      );

      activeOwner = 'account-a';
      expect(
        (await repositories.messages.listMessages(
          accountAConversation.id,
        )).single.text,
        'A private message',
      );
    },
  );

  test(
    'account changes rebind conversation watch to the current owner',
    () async {
      final database = AppDatabase.memory();
      addTearDown(database.close);
      final ownerChanges = StreamController<Object?>.broadcast(sync: true);
      addTearDown(ownerChanges.close);
      var activeOwner = 'account-a';
      final repositories = RelioRepositories(
        database,
        ownerUserIdProvider: () => activeOwner,
        ownerScopeChanges: ownerChanges.stream,
      );
      final accountAConversation = await repositories.conversations
          .ensureConversation(
            id: 'peer-device',
            participantId: 'peer-device',
            displayName: 'Peer A',
            participantStatus: DeviceStatus.offline,
          );
      final accountBVisible = repositories.conversations
          .watchConversations()
          .firstWhere((rows) => rows.any((row) => row.displayName == 'Peer B'));

      activeOwner = 'account-b';
      ownerChanges.add('account-b');
      expect(await repositories.conversations.listConversations(), isEmpty);
      expect(
        await repositories.messages.listMessages(accountAConversation.id),
        isEmpty,
      );
      await repositories.conversations.ensureConversation(
        id: 'peer-device',
        participantId: 'peer-device',
        displayName: 'Peer B',
        participantStatus: DeviceStatus.offline,
      );
      expect(await accountBVisible, hasLength(1));

      activeOwner = 'account-a';
      ownerChanges.add('account-a');
      expect(
        (await repositories.conversations.listConversations()).map(
          (row) => row.displayName,
        ),
        ['Peer A'],
      );
    },
  );

  test(
    'stale account cannot write or mutate another account conversation',
    () async {
      final database = AppDatabase.memory();
      addTearDown(database.close);
      var activeOwner = 'account-a';
      final repositories = RelioRepositories(
        database,
        ownerUserIdProvider: () => activeOwner,
      );
      final conversation = await repositories.conversations.ensureConversation(
        id: 'shared-peer',
        participantId: 'shared-peer',
        displayName: 'Peer',
        participantStatus: DeviceStatus.offline,
      );
      final original = await repositories.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: 'account-a',
        senderDeviceId: 'device-local',
        text: 'A message',
      );
      final attachment = await repositories.attachments.createPending(
        id: 'account-a-attachment',
        conversationId: conversation.id,
        messageId: original.id,
        transferId: 'account-a-transfer',
        mediaType: MediaType.image,
        fileName: 'private.png',
        mimeType: 'image/png',
        localPath: 'private.png',
        byteSize: 12,
      );

      activeOwner = 'account-b';
      await expectLater(
        repositories.messages.createOutgoingText(
          conversationId: conversation.id,
          senderId: 'account-b',
          senderDeviceId: 'device-local',
          text: 'must not be inserted',
        ),
        throwsA(isA<StateError>()),
      );
      await repositories.messages.updateDeliveryStatus(
        original.id,
        DeliveryStatus.failed,
      );
      await expectLater(
        repositories.attachments.createPending(
          id: 'forbidden-account-b-attachment',
          conversationId: conversation.id,
          messageId: original.id,
          transferId: 'forbidden-transfer',
          mediaType: MediaType.image,
          fileName: 'private.png',
          mimeType: 'image/png',
          localPath: 'private.png',
          byteSize: 12,
        ),
        throwsA(isA<StateError>()),
      );
      await repositories.attachments.markFailed(
        attachment.id,
        'stale-account-write',
      );
      expect(await repositories.attachments.getById(attachment.id), isNull);
      expect(await repositories.attachments.listAll(), isEmpty);
      expect(
        await repositories.conversations.getConversation(conversation.id),
        isNull,
      );
      expect(
        await repositories.messages.listMessages(conversation.id),
        isEmpty,
      );
      expect(await repositories.messages.getMessage(original.id), isNull);
      final stored = await (database.select(
        database.messages,
      )..where((row) => row.conversationId.equals(conversation.id))).get();
      expect(stored, hasLength(1));
      expect(stored.single.content, 'A message');
      expect(stored.single.deliveryStatus, DeliveryStatus.pending.name);
      final storedAttachment = await (database.select(
        database.attachments,
      )..where((row) => row.id.equals(attachment.id))).getSingle();
      expect(storedAttachment.transferStatus, MediaTransferState.pending.name);
    },
  );

  test('new empty conversation is emitted by the reactive chat list', () async {
    final database = AppDatabase.memory();
    addTearDown(database.close);
    final repositories = RelioRepositories(database);
    final appeared = repositories.conversations.watchConversations().firstWhere(
      (rows) => rows.isNotEmpty,
    );

    final conversation = await repositories.conversations.ensureConversation(
      id: 'verified-peer-device',
      participantId: 'verified-peer-device',
      displayName: 'Verified Peer',
      participantStatus: DeviceStatus.normal,
    );

    final rows = await appeared;
    expect(rows.single.id, conversation.id);
    expect(rows.single.lastMessageText, isNull);
    expect(await repositories.messages.listMessages(conversation.id), isEmpty);
  });

  late AppDatabase database;
  late RelioRepositories repositories;

  setUp(() {
    database = createTestDatabase();
    repositories = RelioRepositories(database);
    addTearDown(database.close);
  });

  test(
    'outgoing message is persisted as pending and updates conversation',
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
        senderDeviceId: 'device-1',
        text: 'offline hello',
      );

      expect(message.status, DeliveryStatus.pending);
      final stored = await repositories.messages.listMessages('peer-1');
      expect(stored.single.text, 'offline hello');
      expect(stored.single.id, message.id);
      expect(await repositories.syncQueue.pendingCount(), 2);
      expect(
        (await repositories.syncQueue.listPending()).where(
          (item) => item.operation == SyncOperation.messageUpsert.value,
        ),
        hasLength(1),
      );
      expect(
        (await repositories.conversations.listConversations())
            .single
            .lastMessageAt,
        isNotNull,
      );

      await repositories.messages.updateDeliveryStatus(
        message.id,
        DeliveryStatus.nearbySent,
      );
      expect(
        (await repositories.messages.listMessages('peer-1')).single.status,
        DeliveryStatus.nearbySent,
      );

      final reopenedRepository = DriftMessageRepository(
        database,
        repositories.conversations,
        repositories.syncQueue,
      );
      expect(
        (await reopenedRepository.listMessages('peer-1')).single.text,
        'offline hello',
      );
    },
  );

  test(
    'Nearby incoming messages for the same peer resolve per account',
    () async {
      final database = AppDatabase.memory();
      addTearDown(database.close);
      var activeOwner = 'account-a';
      final repositories = RelioRepositories(
        database,
        ownerUserIdProvider: () => activeOwner,
      );
      final accountA = await repositories.conversations.ensureConversation(
        id: 'peer-device',
        participantId: 'peer-device',
        displayName: 'Peer',
        participantStatus: DeviceStatus.normal,
      );
      await repositories.messages.createIncomingText(
        conversationId: accountA.id,
        senderId: 'peer-user',
        senderDeviceId: 'peer-device',
        messageId: 'a-nearby-message',
        text: 'A history',
        createdAt: DateTime.utc(2026, 10, 9),
      );

      activeOwner = 'account-b';
      final accountB = await repositories.conversations.ensureConversation(
        id: 'peer-device',
        participantId: 'peer-device',
        displayName: 'Peer',
        participantStatus: DeviceStatus.normal,
      );
      expect(accountB.id, isNot(accountA.id));
      expect(
        (await repositories.conversations.listConversations()).map(
          (conversation) => conversation.id,
        ),
        [accountB.id],
      );
      expect(await repositories.messages.listMessages(accountA.id), isEmpty);
      expect(await repositories.messages.listMessages(accountB.id), isEmpty);
      await repositories.messages.createIncomingText(
        conversationId: accountB.id,
        senderId: 'peer-user',
        senderDeviceId: 'peer-device',
        messageId: 'b-nearby-message',
        text: 'B history',
        createdAt: DateTime.utc(2026, 10, 9, 0, 1),
      );
      expect(
        (await repositories.messages.listMessages(
          accountB.id,
        )).map((message) => message.text),
        ['B history'],
      );
      expect(
        await repositories.messages.getMessage('a-nearby-message'),
        isNull,
      );

      activeOwner = 'account-a';
      expect(
        (await repositories.messages.listMessages(accountA.id)).single.text,
        'A history',
      );
      expect(
        await repositories.messages.getMessage('b-nearby-message'),
        isNull,
      );
      activeOwner = 'account-b';
      final reconnectedB = await repositories.conversations.ensureConversation(
        id: accountB.id,
        participantId: 'peer-device',
        displayName: 'Peer',
        participantStatus: DeviceStatus.normal,
      );
      expect(reconnectedB.id, accountB.id);
    },
  );

  test(
    'Week 3 delete removes only the disposable message and its pending queue row',
    () async {
      await repositories.conversations.ensureConversation(
        id: 'week3-delete-peer',
        participantId: 'week3-delete-peer',
        displayName: 'Week 3 peer',
        participantStatus: DeviceStatus.offline,
      );
      final message = await repositories.messages.createOutgoingText(
        conversationId: 'week3-delete-peer',
        senderId: 'account-a',
        senderDeviceId: 'device-a',
        text: 'WEEK3 DELETE TEST',
      );

      expect(
        await repositories.messages.deleteWeek3DemoMessage(message.id),
        isTrue,
      );
      expect(await repositories.messages.getMessage(message.id), isNull);
      expect(
        (await repositories.syncQueue.listAll()).where(
          (item) => item.entityId == message.id,
        ),
        isEmpty,
      );
    },
  );

  test('Week 3 delete accepts the ASCII presentation token', () async {
    await repositories.conversations.ensureConversation(
      id: 'week3-delete-ascii',
      participantId: 'week3-delete-ascii',
      displayName: 'Week 3 peer',
      participantStatus: DeviceStatus.offline,
    );
    final message = await repositories.messages.createOutgoingText(
      conversationId: 'week3-delete-ascii',
      senderId: 'account-a',
      senderDeviceId: 'device-a',
      text: 'W3DELETETEST',
    );

    expect(
      await repositories.messages.deleteWeek3DemoMessage(message.id),
      isTrue,
    );
    expect(await repositories.messages.getMessage(message.id), isNull);
    expect(
      (await repositories.syncQueue.listAll()).where(
        (item) => item.entityId == message.id,
      ),
      isEmpty,
    );
  });

  test(
    'Week 3 delete rejects ordinary messages and messages that started syncing',
    () async {
      await repositories.conversations.ensureConversation(
        id: 'week3-delete-guard',
        participantId: 'week3-delete-guard',
        displayName: 'Week 3 peer',
        participantStatus: DeviceStatus.offline,
      );
      final ordinary = await repositories.messages.createOutgoingText(
        conversationId: 'week3-delete-guard',
        senderId: 'account-a',
        senderDeviceId: 'device-a',
        text: 'ordinary message',
      );
      final demo = await repositories.messages.createOutgoingText(
        conversationId: 'week3-delete-guard',
        senderId: 'account-a',
        senderDeviceId: 'device-a',
        text: 'WEEK3 DELETE TEST',
      );
      final demoQueue = (await repositories.syncQueue.listPending())
          .singleWhere((item) => item.entityId == demo.id);
      await repositories.syncQueue.markProcessing(demoQueue.id);

      expect(
        await repositories.messages.deleteWeek3DemoMessage(ordinary.id),
        isFalse,
      );
      expect(
        await repositories.messages.deleteWeek3DemoMessage(demo.id),
        isFalse,
      );
      expect(await repositories.messages.getMessage(ordinary.id), isNotNull);
      expect(await repositories.messages.getMessage(demo.id), isNotNull);
    },
  );

  test(
    'incoming messages retain unread state until the conversation is read',
    () async {
      await repositories.conversations.ensureConversation(
        id: 'peer-read',
        participantId: 'peer-read',
        displayName: 'Peer Read',
        participantStatus: DeviceStatus.normal,
      );
      await repositories.messages.createIncomingText(
        conversationId: 'peer-read',
        senderId: 'peer-user',
        senderDeviceId: 'peer-device',
        messageId: 'incoming-1',
        text: 'hello',
        createdAt: DateTime.now(),
      );

      expect(
        (await repositories.conversations.getConversation(
          'peer-read',
        ))?.unreadCount,
        1,
      );
      expect(await repositories.messages.markConversationRead('peer-read'), [
        'incoming-1',
      ]);
      expect(
        (await repositories.conversations.getConversation(
          'peer-read',
        ))?.unreadCount,
        0,
      );
      expect(
        (await repositories.messages.getMessage('incoming-1'))?.readAt,
        isNotNull,
      );
    },
  );

  test(
    'concurrent duplicate incoming text increments unread only once',
    () async {
      await repositories.conversations.ensureConversation(
        id: 'peer-concurrent-duplicate',
        participantId: 'peer-concurrent-duplicate',
        displayName: 'Peer',
        participantStatus: DeviceStatus.normal,
      );
      final receivedAt = DateTime.utc(2026, 10, 4, 8);

      final results = await Future.wait([
        repositories.messages.createIncomingText(
          conversationId: 'peer-concurrent-duplicate',
          senderId: 'peer-user',
          senderDeviceId: 'peer-device',
          messageId: 'duplicate-message',
          text: 'one logical message',
          createdAt: receivedAt,
        ),
        repositories.messages.createIncomingText(
          conversationId: 'peer-concurrent-duplicate',
          senderId: 'peer-user',
          senderDeviceId: 'peer-device',
          messageId: 'duplicate-message',
          text: 'one logical message',
          createdAt: receivedAt,
        ),
      ]);

      expect(results.map((message) => message.id).toSet(), {
        'duplicate-message',
      });
      expect(
        await repositories.messages.listMessages('peer-concurrent-duplicate'),
        hasLength(1),
      );
      expect(
        (await repositories.conversations.getConversation(
          'peer-concurrent-duplicate',
        ))?.unreadCount,
        1,
      );
    },
  );

  test(
    'concurrent duplicate incoming media creates one local message',
    () async {
      await repositories.conversations.ensureConversation(
        id: 'peer-concurrent-media',
        participantId: 'peer-concurrent-media',
        displayName: 'Peer',
        participantStatus: DeviceStatus.normal,
      );

      await Future.wait([
        repositories.messages.createIncomingMedia(
          conversationId: 'peer-concurrent-media',
          senderId: 'peer-user',
          senderDeviceId: 'peer-device',
          messageId: 'duplicate-image',
          type: MessageType.image,
          fileName: 'photo.png',
          localPath: 'managed/photo.png',
        ),
        repositories.messages.createIncomingMedia(
          conversationId: 'peer-concurrent-media',
          senderId: 'peer-user',
          senderDeviceId: 'peer-device',
          messageId: 'duplicate-image',
          type: MessageType.image,
          fileName: 'photo.png',
          localPath: 'managed/photo.png',
        ),
      ]);

      expect(
        await repositories.messages.listMessages('peer-concurrent-media'),
        hasLength(1),
      );
      expect(
        (await repositories.conversations.getConversation(
          'peer-concurrent-media',
        ))?.unreadCount,
        1,
      );
    },
  );

  test('incoming location retains coordinates and deduplicates', () async {
    await repositories.conversations.ensureConversation(
      id: 'peer-location',
      participantId: 'peer-location',
      displayName: 'Peer',
      participantStatus: DeviceStatus.normal,
    );
    final location = LocationData(
      latitude: 13.7563,
      longitude: 100.5018,
      capturedAt: DateTime.utc(2026, 10, 4, 9),
      accuracyMeters: 12.5,
    );

    final first = await repositories.messages.createIncomingLocation(
      conversationId: 'peer-location',
      senderId: 'peer-user',
      senderDeviceId: 'peer-device',
      messageId: 'location-message',
      location: location,
    );
    final duplicate = await repositories.messages.createIncomingLocation(
      conversationId: 'peer-location',
      senderId: 'peer-user',
      senderDeviceId: 'peer-device',
      messageId: 'location-message',
      location: location,
    );

    expect(first.latitude, 13.7563);
    expect(first.longitude, 100.5018);
    expect(duplicate.id, first.id);
    expect(
      (await repositories.conversations.getConversation(
        'peer-location',
      ))?.unreadCount,
      1,
    );
  });

  test(
    'Cloud read receipt merge keeps read state and earliest timestamp',
    () async {
      await repositories.conversations.ensureConversation(
        id: 'cloud-read-merge',
        participantId: 'cloud-peer',
        displayName: 'Cloud Peer',
        participantStatus: DeviceStatus.offline,
      );
      final message = await repositories.messages.createOutgoingText(
        conversationId: 'cloud-read-merge',
        senderId: 'account-a',
        senderDeviceId: 'device-a',
        text: 'receipt test',
      );
      final firstReadAt = DateTime.utc(2026, 10, 1, 10);

      await repositories.messages.mergeCloudReadReceipt(
        messageId: message.id,
        readAt: firstReadAt,
      );
      await repositories.messages.mergeCloudReadReceipt(
        messageId: message.id,
        readAt: firstReadAt.add(const Duration(minutes: 5)),
      );

      expect(
        (await repositories.messages.getMessage(message.id))?.readAt?.toUtc(),
        firstReadAt,
      );
    },
  );

  test(
    'Nearby and Cloud copies merge by UUID and reject mismatched content',
    () async {
      await repositories.conversations.ensureConversation(
        id: 'nearby-cloud-merge',
        participantId: 'peer-device',
        displayName: 'Peer',
        participantStatus: DeviceStatus.normal,
      );
      final createdAt = DateTime.utc(2026, 10, 1, 9);
      await repositories.messages.createIncomingText(
        conversationId: 'nearby-cloud-merge',
        senderId: 'peer-account',
        senderDeviceId: 'peer-device',
        messageId: 'shared-message-uuid',
        text: 'same payload',
        createdAt: createdAt,
      );

      final inserted = await repositories.messages.mergeCloudText(
        conversationId: 'nearby-cloud-merge',
        messageId: 'shared-message-uuid',
        senderUserId: 'peer-account',
        senderDeviceId: 'peer-device',
        text: 'same payload',
        createdAt: createdAt,
        updatedAt: createdAt,
        currentUserId: 'local-account',
      );
      expect(inserted, isFalse);
      expect(
        (await repositories.conversations.getConversation(
          'nearby-cloud-merge',
        ))?.unreadCount,
        1,
      );

      await expectLater(
        repositories.messages.mergeCloudText(
          conversationId: 'nearby-cloud-merge',
          messageId: 'shared-message-uuid',
          senderUserId: 'peer-account',
          senderDeviceId: 'peer-device',
          text: 'different payload',
          createdAt: createdAt,
          updatedAt: createdAt,
          currentUserId: 'local-account',
        ),
        throwsA(isA<CloudException>()),
      );
      expect(
        (await repositories.messages.getMessage('shared-message-uuid'))?.text,
        'same payload',
      );
    },
  );

  test('conversation ordering follows local last activity', () async {
    await repositories.conversations.ensureConversation(
      id: 'older',
      participantId: 'older',
      displayName: 'Older',
      participantStatus: DeviceStatus.normal,
    );
    await repositories.conversations.ensureConversation(
      id: 'newer',
      participantId: 'newer',
      displayName: 'Newer',
      participantStatus: DeviceStatus.rescue,
    );

    await repositories.messages.createOutgoingText(
      conversationId: 'older',
      senderId: 'minnie',
      senderDeviceId: 'device-1',
      text: 'first',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await repositories.messages.createOutgoingText(
      conversationId: 'newer',
      senderId: 'minnie',
      senderDeviceId: 'device-1',
      text: 'second',
    );
    await repositories.conversations.updateLastActivity(
      'newer',
      DateTime.now().add(const Duration(seconds: 1)),
    );

    final conversations = await repositories.conversations.listConversations();
    expect(conversations.map((item) => item.id).take(2), ['newer', 'older']);
    expect(conversations.first.lastMessageText, 'second');
  });

  test('SOS active state and sync queue transitions are local', () async {
    final signedInRepositories = RelioRepositories(
      database,
      ownerUserIdProvider: () => 'user-1',
    );
    final sos = await signedInRepositories.sos.createAndActivate(
      ownerDeviceId: 'device-1',
      ownerUserId: 'user-1',
      message: 'need help',
      latitude: 13.7,
      longitude: 100.5,
    );

    expect((await signedInRepositories.sos.readActive())?.id, sos.id);
    expect(await signedInRepositories.syncQueue.pendingCount(), 1);
    final queueItem =
        (await signedInRepositories.syncQueue.listPending()).single;
    expect(queueItem.ownerUserId, 'user-1');
    await signedInRepositories.syncQueue.markProcessing(queueItem.id);
    await signedInRepositories.syncQueue.markCompleted(queueItem.id);
    expect(await signedInRepositories.syncQueue.pendingCount(), 0);

    await signedInRepositories.sos.deactivate(sos.id);
    expect(await signedInRepositories.sos.readActive(), isNull);
  });

  test(
    'guest SOS stays local and is never assigned to a later account',
    () async {
      final sos = await repositories.sos.createAndActivate(
        ownerDeviceId: 'device-guest',
        ownerUserId: '',
        message: 'SOS offline',
      );

      expect((await repositories.sos.readActive())?.id, sos.id);
      expect(await repositories.syncQueue.pendingCount(), 0);

      final laterSignedInRepositories = RelioRepositories(
        database,
        ownerUserIdProvider: () => 'user-later',
      );
      await laterSignedInRepositories.sos.deactivate(sos.id);
      expect(await laterSignedInRepositories.syncQueue.pendingCount(), 0);
    },
  );

  test('prototype seed data is written once and remains queryable', () async {
    await repositories.seedPrototypeData();
    final first = await repositories.conversations.listConversations();
    final messages = await repositories.messages.listMessages('somchai');
    await repositories.seedPrototypeData();
    final second = await repositories.conversations.listConversations();

    expect(first.length, 3);
    expect(second.length, first.length);
    expect(messages, isNotEmpty);
  });

  test('local boolean settings survive repository reads', () async {
    await repositories.settings.setBool('rescue_mode', true);

    expect(
      await repositories.settings.getBool('rescue_mode', defaultValue: false),
      isTrue,
    );
  });

  test(
    'local device name can be changed and survives repository reads',
    () async {
      final identity = RelioDeviceIdentityRepository(database);
      await identity.setDisplayName('Rescue Team');

      expect(await identity.getDisplayName(), 'Rescue Team');
    },
  );

  test('default device name is numbered and stable across reads', () async {
    final identity = RelioDeviceIdentityRepository(database);
    final first = await identity.getDisplayName();

    expect(first, matches(RegExp(r'^ผู้ใช้ RELIO \d{4}$')));
    expect(await identity.getDisplayName(), first);
    expect(await identity.isUsingDefaultDisplayName(), isTrue);

    await identity.setDisplayName('  ชื่อทดสอบ RELIO  ');
    expect(await identity.getDisplayName(), 'ชื่อทดสอบ RELIO');
    expect(await identity.isUsingDefaultDisplayName(), isFalse);
    await expectLater(identity.setDisplayName('x' * 41), throwsArgumentError);
    await expectLater(identity.setDisplayName('   '), throwsArgumentError);
    expect(await identity.getDisplayName(), 'ชื่อทดสอบ RELIO');

    await identity.setDisplayName(first);
    expect(await identity.isUsingDefaultDisplayName(), isTrue);
  });

  test(
    'legacy custom device name is preserved during default migration',
    () async {
      await database
          .into(database.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'display_name',
              value: 'ทีมกู้ภัยเดิม',
              updatedAt: DateTime(2025),
            ),
          );
      final identity = RelioDeviceIdentityRepository(database);

      expect(await identity.getDisplayName(), 'ทีมกู้ภัยเดิม');
      expect(await identity.isUsingDefaultDisplayName(), isFalse);
    },
  );

  test('trusted Nearby identity requires a persisted public-key pin', () async {
    await repositories.nearbyDevices.upsert(
      deviceId: 'peer-device-25',
      displayName: 'Peer',
      status: DeviceStatus.normal,
    );
    await repositories.nearbyDevices.setTrusted('peer-device-25', true);
    expect(
      (await repositories.nearbyDevices.getDevice(
        'peer-device-25',
      ))!.autoReconnectEnabled,
      isFalse,
    );

    const publicKey = 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtest-public-key';
    final fingerprint = List.filled(64, 'a').join();
    await repositories.nearbyDevices.setTrustedIdentity(
      deviceId: 'peer-device-25',
      publicIdentityKey: publicKey,
      fingerprint: fingerprint,
    );
    var saved = (await repositories.nearbyDevices.getDevice('peer-device-25'))!;
    expect(saved.isTrusted, isTrue);
    expect(saved.publicIdentityKey, publicKey);
    expect(saved.publicIdentityFingerprint, fingerprint);
    expect(saved.autoReconnectEnabled, isTrue);

    await repositories.nearbyDevices.setTrusted('peer-device-25', false);
    saved = (await repositories.nearbyDevices.getDevice('peer-device-25'))!;
    expect(saved.isTrusted, isFalse);
    expect(saved.autoReconnectEnabled, isFalse);
    expect(saved.publicIdentityFingerprint, fingerprint);

    await repositories.nearbyDevices.setBlocked('peer-device-25', true);
    expect(
      (await repositories.nearbyDevices.getDevice(
        'peer-device-25',
      ))!.autoReconnectEnabled,
      isFalse,
    );
    await expectLater(
      repositories.nearbyDevices.setTrustedIdentity(
        deviceId: 'peer-device-25',
        publicIdentityKey: publicKey,
        fingerprint: fingerprint,
      ),
      throwsStateError,
    );
  });

  test(
    'removing trust clears one identity pin and preserves local chat data',
    () async {
      for (final deviceId in ['trust-peer-a', 'trust-peer-b']) {
        await repositories.nearbyDevices.upsert(
          deviceId: deviceId,
          displayName: 'Same demo name',
          status: DeviceStatus.normal,
        );
        await repositories.nearbyDevices.setTrustedIdentity(
          deviceId: deviceId,
          publicIdentityKey: 'public-key-$deviceId',
          fingerprint: deviceId.endsWith('a')
              ? List.filled(64, 'a').join()
              : List.filled(64, 'b').join(),
        );
      }
      final conversation = await repositories.conversations.ensureConversation(
        id: 'trust-peer-a',
        participantId: 'trust-peer-a',
        displayName: 'Same demo name',
        participantStatus: DeviceStatus.normal,
      );
      final message = await repositories.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: 'local-user',
        senderDeviceId: 'local-device',
        text: 'Keep this conversation',
      );

      await repositories.nearbyDevices.removeTrustedPeer('trust-peer-a');

      final removed = (await repositories.nearbyDevices.getDevice(
        'trust-peer-a',
      ))!;
      expect(removed.isTrusted, isFalse);
      expect(removed.autoReconnectEnabled, isFalse);
      expect(removed.publicIdentityKey, isNull);
      expect(removed.publicIdentityFingerprint, isNull);
      final untouched = (await repositories.nearbyDevices.getDevice(
        'trust-peer-b',
      ))!;
      expect(untouched.isTrusted, isTrue);
      expect(untouched.autoReconnectEnabled, isTrue);
      expect(untouched.publicIdentityFingerprint, List.filled(64, 'b').join());
      expect(
        (await repositories.messages.listMessages(conversation.id)).single.id,
        message.id,
      );
    },
  );

  test('dependency bootstrap completes in the Flutter test runtime', () async {
    final dependencies = RelioDependencies(database: createTestDatabase());
    addTearDown(dependencies.dispose);

    await dependencies.initialize();

    expect(
      await dependencies.repositories.conversations.listConversations(),
      isNotEmpty,
    );
  });

  test(
    'schema v6 upgrades to cloud links without losing conversations',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'relio-schema-v6',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}relio.db');
      final previous = AppDatabase.withExecutor(NativeDatabase(file));
      final previousRepositories = RelioRepositories(previous);
      await previousRepositories.conversations.ensureConversation(
        id: 'preserved-local-chat',
        participantId: 'peer-device',
        displayName: 'Peer',
        participantStatus: DeviceStatus.offline,
      );
      for (final column in [
        'battery_level',
        'is_charging',
        'battery_updated_at',
        'peer_latitude',
        'peer_longitude',
        'peer_location_accuracy',
        'peer_location_captured_at',
        'peer_device_model',
      ]) {
        await previous.customStatement(
          'ALTER TABLE nearby_devices DROP COLUMN $column',
        );
      }
      await previous.customStatement('PRAGMA user_version = 6');
      await previous.customStatement('DROP TABLE cloud_conversation_links');
      await previous.close();

      final upgraded = AppDatabase.withExecutor(NativeDatabase(file));
      final upgradedRepositories = RelioRepositories(upgraded);
      expect(
        await upgradedRepositories.conversations.getConversation(
          'preserved-local-chat',
        ),
        isNotNull,
      );
      expect(
        await upgradedRepositories.cloudLinks.listForOwner('account-a'),
        isEmpty,
      );
      expect(upgraded.schemaVersion, 9);
      await upgraded.close();
    },
  );

  test(
    'reopening the current database preserves local state and completed work',
    () async {
      final directory = await Directory.systemTemp.createTemp('relio-reopen-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}relio.db');
      final firstDatabase = AppDatabase.withExecutor(NativeDatabase(file));
      final firstRepositories = RelioRepositories(
        firstDatabase,
        ownerUserIdProvider: () => 'account-a',
      );
      final persistentConversation = await firstRepositories.conversations
          .ensureConversation(
            id: 'persistent-peer',
            participantId: 'persistent-peer',
            displayName: 'Persistent Peer',
            participantStatus: DeviceStatus.offline,
          );
      await firstRepositories.messages.createIncomingText(
        conversationId: persistentConversation.id,
        senderId: 'peer-user',
        senderDeviceId: 'peer-device',
        messageId: 'persistent-message',
        text: 'keep this locally',
        createdAt: DateTime.utc(2026, 10, 4, 10),
      );
      await firstRepositories.nearbyDevices.upsert(
        deviceId: 'trusted-peer',
        displayName: 'Trusted Peer',
        status: DeviceStatus.normal,
        batteryLevel: 64,
        isCharging: true,
        batteryUpdatedAt: DateTime.utc(2026, 10, 12, 8),
        peerLatitude: 10.25,
        peerLongitude: 101.5,
        peerLocationAccuracy: 12,
        peerLocationCapturedAt: DateTime.utc(2026, 10, 12, 8),
        peerDeviceModel: 'QA Phone',
      );
      await firstRepositories.nearbyDevices.setTrustedIdentity(
        deviceId: 'trusted-peer',
        publicIdentityKey: 'pinned-public-key',
        fingerprint: List.filled(64, 'b').join(),
      );
      await firstRepositories.attachments.createPending(
        id: 'persistent-attachment',
        conversationId: persistentConversation.id,
        messageId: 'persistent-message',
        transferId: 'persistent-transfer',
        mediaType: MediaType.image,
        fileName: 'photo.png',
        mimeType: 'image/png',
        localPath: 'managed/photo.png',
        byteSize: 100,
      );
      await firstRepositories.settings.setBool('rescue_mode', true);
      final completed = await firstRepositories.syncQueue.enqueue(
        entityType: 'message',
        entityId: 'already-synced',
        operation: 'messageUpsert',
        ownerUserId: 'account-a',
      );
      await firstRepositories.syncQueue.markCompleted(completed.id);
      await firstDatabase.close();

      final reopened = AppDatabase.withExecutor(NativeDatabase(file));
      addTearDown(reopened.close);
      final reopenedRepositories = RelioRepositories(
        reopened,
        ownerUserIdProvider: () => 'account-a',
      );

      expect(
        (await reopenedRepositories.conversations.getConversation(
          persistentConversation.id,
        ))?.unreadCount,
        1,
      );
      expect(
        (await reopenedRepositories.messages.getMessage(
          'persistent-message',
        ))?.text,
        'keep this locally',
      );
      expect(
        (await reopenedRepositories.nearbyDevices.getDevice(
          'trusted-peer',
        ))?.publicIdentityFingerprint,
        List.filled(64, 'b').join(),
      );
      final savedPeer = await reopenedRepositories.nearbyDevices.getDevice(
        'trusted-peer',
      );
      expect(savedPeer?.isTrusted, isTrue);
      expect(savedPeer?.autoReconnectEnabled, isTrue);
      expect(savedPeer?.publicIdentityKey, 'pinned-public-key');
      expect(savedPeer?.batteryLevel, 64);
      expect(savedPeer?.isCharging, isTrue);
      expect(savedPeer?.peerLatitude, 10.25);
      expect(savedPeer?.peerLongitude, 101.5);
      expect(savedPeer?.peerLocationAccuracy, 12);
      expect(savedPeer?.peerDeviceModel, 'QA Phone');
      expect(
        await reopenedRepositories.attachments.getById('persistent-attachment'),
        isNotNull,
      );
      expect(
        await reopenedRepositories.settings.getBool(
          'rescue_mode',
          defaultValue: false,
        ),
        isTrue,
      );
      expect(
        (await reopenedRepositories.syncQueue.listAll())
            .singleWhere((item) => item.id == completed.id)
            .status,
        SyncQueueStatus.completed.value,
      );
    },
  );
}
