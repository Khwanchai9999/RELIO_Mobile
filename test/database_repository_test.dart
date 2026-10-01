import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/core/sync/sync_types.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

import 'test_database.dart';

void main() {
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
      expect(upgraded.schemaVersion, 7);
      await upgraded.close();
    },
  );
}
