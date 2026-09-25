import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/core/sync/sync_types.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  late AppDatabase database;
  late RelioRepositories repositories;

  setUp(() {
    database = AppDatabase.memory();
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
    final sos = await repositories.sos.createAndActivate(
      ownerDeviceId: 'device-1',
      ownerUserId: 'minnie',
      message: 'need help',
      latitude: 13.7,
      longitude: 100.5,
    );

    expect((await repositories.sos.readActive())?.id, sos.id);
    expect(await repositories.syncQueue.pendingCount(), 1);
    final queueItem = (await repositories.syncQueue.listPending()).single;
    await repositories.syncQueue.markProcessing(queueItem.id);
    await repositories.syncQueue.markCompleted(queueItem.id);
    expect(await repositories.syncQueue.pendingCount(), 0);

    await repositories.sos.deactivate(sos.id);
    expect(await repositories.sos.readActive(), isNull);
  });

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

  test('dependency bootstrap completes in the Flutter test runtime', () async {
    final dependencies = RelioDependencies(database: AppDatabase.memory());
    addTearDown(dependencies.dispose);

    await dependencies.initialize();

    expect(
      await dependencies.repositories.conversations.listConversations(),
      isNotEmpty,
    );
  });
}
