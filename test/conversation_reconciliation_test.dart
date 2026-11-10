import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/core/repositories/principal_profile_repository.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

final _start = DateTime(2025);

Future<void> _seedConversation(
  AppDatabase db,
  String id, {
  String local = 'account:owner',
  String remote = 'account:peer',
  String device = 'device',
  String? scope = 'owner',
  int count = 0,
  int offset = 0,
}) async {
  await db
      .into(db.conversations)
      .insert(
        ConversationsCompanion.insert(
          id: id,
          participantId: device,
          displayName: 'ชื่อเดียวกัน',
          participantStatus: 'normal',
          unreadCount: Value(count),
          createdAt: _start.add(Duration(seconds: offset)),
          updatedAt: _start,
        ),
      );
  await db.customStatement(
    'INSERT INTO conversation_principals VALUES (?,?,?,?,?)',
    [id, local, remote, device, 'active'],
  );
  if (scope != null) {
    await db.customStatement('INSERT INTO conversation_scopes VALUES (?,?,?)', [
      id,
      scope,
      id,
    ]);
  }
  for (var index = 0; index < count; index++) {
    final time = _start.add(Duration(seconds: offset + index));
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: '$id-$index',
            conversationId: id,
            senderId: 'peer',
            messageType: 'text',
            content: 'fixture $id-$index',
            createdAt: time,
            updatedAt: time,
            deliveryStatus: DeliveryStatus.delivered.name,
            isOutgoing: false,
          ),
        );
  }
}

Future<Map<String, List<Map<String, Object?>>>> _references(
  AppDatabase db,
) async {
  return {
    for (final table in [
      'messages',
      'attachments',
      'sync_queue',
      'queue_principals',
      'cloud_conversation_links',
      'relay_packets',
      'relay_forward_history',
    ])
      table: (await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
          .map((row) => row.data)
          .toList(),
  };
}

Future<File> _databaseFile() async {
  final directory = await Directory.systemTemp.createTemp(
    'relio-conversations-',
  );
  addTearDown(() => directory.delete(recursive: true));
  return File('${directory.path}/legacy.sqlite');
}

void main() {
  test(
    'v13 upgrade and restart preserve 28 IDs, links, ACKs and queue rows',
    () async {
      final file = await _databaseFile();
      final legacy = AppDatabase.withExecutor(NativeDatabase(file));
      await _seedConversation(legacy, 'canonical', count: 24);
      await _seedConversation(legacy, 'secondary', count: 4, offset: 30);
      await legacy.customStatement(
        'UPDATE messages SET read_at=?, local_file_path=? WHERE id=?',
        [
          _start.millisecondsSinceEpoch ~/ 1000,
          '/fixture/attachment',
          'secondary-0',
        ],
      );
      await legacy.customStatement(
        "UPDATE conversations SET unread_count=3 WHERE id='secondary'",
      );
      await legacy
          .into(legacy.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: 'attachment',
              messageId: 'secondary-0',
              transferId: 'transfer',
              mediaType: 'image',
              fileName: 'fixture.jpg',
              mimeType: 'image/jpeg',
              localPath: '/fixture/attachment',
              byteSize: 10,
              transferStatus: 'completed',
              createdAt: _start,
              updatedAt: _start,
            ),
          );
      await legacy
          .into(legacy.cloudConversationLinks)
          .insert(
            CloudConversationLinksCompanion.insert(
              localConversationId: 'canonical',
              cloudConversationId: 'cloud',
              ownerUserId: 'owner',
              peerUserId: 'peer',
              receiptCursorAt: Value(_start),
              receiptCursorMessageId: const Value('canonical-0'),
              receiptCursorReaderId: const Value('peer'),
              updatedAt: _start,
            ),
          );
      await legacy
          .into(legacy.syncQueue)
          .insert(
            SyncQueueCompanion.insert(
              id: 'queued',
              entityType: 'attachment',
              entityId: 'attachment',
              operation: 'attachmentUpload',
              status: 'pending',
              ownerUserId: const Value('owner'),
              createdAt: _start,
              updatedAt: _start,
            ),
          );
      await legacy.customStatement(
        "INSERT INTO queue_principals VALUES ('queued','account:owner')",
      );
      await legacy
          .into(legacy.relayPackets)
          .insert(
            RelayPacketsCompanion.insert(
              packetId: 'ack-packet',
              originDeviceId: 'device',
              destinationDeviceId: 'local-device',
              payloadType: 'ack',
              payloadId: 'secondary-1',
              createdAt: _start,
              expiresAt: _start.add(const Duration(days: 1)),
              hopCount: 1,
              maxHops: 2,
              priority: 1,
              protocol: 'fixture',
              payloadJson: '{}',
              state: 'delivered',
              storedAt: _start,
            ),
          );
      final before = await _references(legacy);
      await legacy.customStatement('DROP TABLE conversation_aliases');
      await legacy.customStatement('PRAGMA user_version=13');
      await legacy.close();

      for (var open = 0; open < 2; open++) {
        final db = AppDatabase.withExecutor(NativeDatabase(file));
        final repo = RelioRepositories(db, ownerUserIdProvider: () => 'owner');
        try {
          expect(await _references(db), before);
          final list = await repo.conversations.listConversations();
          expect(list.map((row) => row.id), ['canonical']);
          expect(list.single.unreadCount, 27);
          expect(list.single.lastMessageText, 'fixture secondary-3');
          expect(
            list.single.lastMessageAt,
            _start.add(const Duration(seconds: 33)),
          );
          expect(
            (await repo.conversations.resolveRouteTarget('secondary')).id,
            'canonical',
          );
          final history = await repo.messages.listMessages('canonical');
          expect(history.map((row) => row.id).toSet(), {
            for (var i = 0; i < 24; i++) 'canonical-$i',
            for (var i = 0; i < 4; i++) 'secondary-$i',
          });
          expect(await repo.messages.listMessages('secondary'), hasLength(28));
          expect(
            (await repo.attachments.getById('attachment'))?.messageId,
            'secondary-0',
          );
          expect(
            await db.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
          await db.transaction(() => db.reconcileConversationDuplicates());
          expect(await _references(db), before);
          expect(
            await db.customSelect('SELECT * FROM conversation_aliases').get(),
            hasLength(1),
          );
          if (open == 1) {
            final repeated = await repo.messages.createIncomingText(
              conversationId: 'canonical',
              senderId: 'peer',
              senderDeviceId: 'device',
              messageId: 'secondary-1',
              text: 'fixture secondary-1',
              createdAt: _start,
            );
            expect(repeated.id, 'secondary-1');
            expect(
              await repo.messages.listMessages('canonical'),
              hasLength(28),
            );
            expect(
              await repo.messages.markConversationRead('canonical'),
              hasLength(27),
            );
            expect(
              (await repo.conversations.listConversations()).single.unreadCount,
              0,
            );
          }
        } finally {
          await db.close();
        }
      }
    },
  );

  test(
    'keeps missing scope, distinct principals, devices and Guest histories separate',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      String? owner = 'owner';
      final repo = RelioRepositories(db, ownerUserIdProvider: () => owner);
      final guest = await PrincipalProfileRepository.guestPrincipalFor(db);
      await _seedConversation(db, 'scoped');
      await _seedConversation(db, 'missing', scope: null);
      await _seedConversation(db, 'different-peer', remote: 'account:other');
      await _seedConversation(db, 'different-device', device: 'other-device');
      await _seedConversation(
        db,
        'different-owner',
        local: 'account:other',
        scope: 'other',
      );
      await _seedConversation(db, 'guest', local: guest, scope: null);
      await db.transaction(() => db.reconcileConversationDuplicates());
      expect(
        (await repo.conversations.listConversations())
            .map((row) => row.id)
            .toSet(),
        {'scoped', 'missing', 'different-peer', 'different-device'},
      );
      owner = 'other';
      expect(
        (await repo.conversations.listConversations()).single.id,
        'different-owner',
      );
      owner = null;
      expect((await repo.conversations.listConversations()).single.id, 'guest');
    },
  );

  test(
    'authorized adoption reconciles verified collision and adopts unique peer',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      String? owner;
      final repo = RelioRepositories(db, ownerUserIdProvider: () => owner);
      final guest = await PrincipalProfileRepository.guestPrincipalFor(db);
      await _seedConversation(db, 'account', count: 1);
      await _seedConversation(
        db,
        'guest-collision',
        local: guest,
        scope: null,
        count: 2,
        offset: 10,
      );
      await _seedConversation(
        db,
        'guest-unique',
        local: guest,
        scope: null,
        remote: 'account:unique',
      );
      await _seedConversation(
        db,
        'uncertain-account',
        remote: 'account:uncertain',
        scope: null,
      );
      await _seedConversation(
        db,
        'guest-blocked',
        local: guest,
        scope: null,
        remote: 'account:uncertain',
      );
      final pending = await repo.messages.createOutgoingText(
        conversationId: 'guest-blocked',
        senderId: 'local',
        senderDeviceId: 'local-device',
        text: 'fixture',
      );
      owner = 'owner';
      await repo.conversations.adoptUnowned('owner');
      await repo.syncQueue.adoptUnowned('owner');
      await repo.conversations.adoptUnowned('owner');
      expect(
        (await repo.conversations.listConversations())
            .map((row) => row.id)
            .toSet(),
        {'account', 'guest-unique', 'uncertain-account'},
      );
      expect(await repo.messages.listMessages('account'), hasLength(3));
      expect(
        (await repo.syncQueue.listAll())
            .singleWhere((item) => item.entityId == pending.id)
            .ownerUserId,
        isNull,
      );
      owner = null;
      expect(
        (await repo.conversations.listConversations()).single.id,
        'guest-blocked',
      );
      expect(await repo.messages.getMessage(pending.id), isNotNull);
    },
  );

  test('matching Cloud binding corroborates an absent account scope', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final repo = RelioRepositories(db, ownerUserIdProvider: () => 'owner');
    await _seedConversation(db, 'scoped', count: 4);
    await _seedConversation(db, 'corroborated', scope: null, count: 24);
    await _seedConversation(db, 'foreign-link', scope: null);
    for (final (id, owner) in [
      ('corroborated', 'owner'),
      ('foreign-link', 'other'),
    ]) {
      await db
          .into(db.cloudConversationLinks)
          .insert(
            CloudConversationLinksCompanion.insert(
              localConversationId: id,
              cloudConversationId: 'cloud-$owner',
              ownerUserId: owner,
              peerUserId: 'peer',
              updatedAt: _start,
            ),
          );
    }
    await db.transaction(() => db.reconcileConversationDuplicates());
    expect(
      (await repo.conversations.listConversations())
          .map((row) => row.id)
          .toSet(),
      {'corroborated', 'foreign-link'},
    );
    expect(await repo.messages.listMessages('corroborated'), hasLength(28));
    expect(await repo.messages.listMessages('foreign-link'), isEmpty);
  });

  test(
    'concurrent creation and repeated verified discovery reuse one row',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final repo = RelioRepositories(db, ownerUserIdProvider: () => 'owner');
      final conversations = repo.conversations as DriftConversationRepository;
      await conversations.rememberRemotePrincipal(
        'device',
        'account:peer',
        'ชื่อเดียวกัน',
        1,
      );
      final results = await Future.wait(
        List.generate(
          12,
          (index) => conversations.ensureConversation(
            id: 'attempt-$index',
            participantId: 'device',
            displayName: 'ชื่อเดียวกัน',
            participantStatus: DeviceStatus.normal,
          ),
        ),
      );
      expect(results.map((row) => row.id).toSet(), hasLength(1));
      await conversations.rememberRemotePrincipal(
        'device',
        'account:peer',
        'ชื่อเดิม',
        2,
      );
      final route = await conversations.resolveRouteTarget('device');
      expect(route.id, results.first.id);
      expect(await conversations.listConversations(), hasLength(1));
    },
  );

  test(
    'reconciliation failure rolls back aliases and leaves all source rows',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await _seedConversation(db, 'a', count: 1);
      await _seedConversation(db, 'b', count: 1);
      await _seedConversation(db, 'c', count: 1);
      final before = await _references(db);
      await db.customStatement('''
      CREATE TRIGGER fail_alias BEFORE INSERT ON conversation_aliases
      WHEN NEW.conversation_id='c'
      BEGIN SELECT RAISE(ABORT, 'fixture failure'); END
    ''');
      await expectLater(
        db.transaction(() => db.reconcileConversationDuplicates()),
        throwsA(isA<Exception>()),
      );
      expect(
        await db.customSelect('SELECT * FROM conversation_aliases').get(),
        isEmpty,
      );
      expect(await _references(db), before);
    },
  );
}
