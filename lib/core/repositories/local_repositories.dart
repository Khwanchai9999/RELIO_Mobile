import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/mock_data.dart';
import '../../data/models/prototype_models.dart';
import '../database/app_database.dart';
import '../domain/relio_entities.dart';
import '../sync/sync_types.dart';

abstract interface class ConversationRepository {
  Stream<List<RelioConversation>> watchConversations();
  Future<List<RelioConversation>> listConversations();
  Future<RelioConversation?> getConversation(String id);
  Future<RelioConversation> ensureConversation({
    required String id,
    required String participantId,
    required String displayName,
    required DeviceStatus participantStatus,
  });
  Future<void> updateLastActivity(String conversationId, DateTime time);
  Future<void> updateParticipantStatus(
    String participantId,
    DeviceStatus status,
  );
}

abstract interface class MessageRepository {
  Stream<List<RelioMessage>> watchMessages(String conversationId);
  Future<List<RelioMessage>> listMessages(String conversationId);
  Future<RelioMessage?> getMessage(String messageId);
  Future<RelioMessage> createOutgoingText({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required String text,
  });
  Future<RelioMessage> createIncomingText({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required String messageId,
    required String text,
    required DateTime createdAt,
  });
  Future<RelioMessage> createOutgoingLocation({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required LocationData location,
  });
  Future<RelioMessage> createIncomingLocation({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required String messageId,
    required LocationData location,
  });
  Future<RelioMessage> createOutgoingMedia({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required MessageType type,
    required String fileName,
    required String localPath,
    required String attachmentId,
    String? messageId,
  });
  Future<RelioMessage> createIncomingMedia({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required String messageId,
    required MessageType type,
    required String fileName,
    required String localPath,
  });
  Future<void> updateDeliveryStatus(String messageId, DeliveryStatus status);
  Future<List<String>> markConversationRead(String conversationId);
  Future<void> markMessageRead(String messageId);
  Future<void> updateCloudSyncStatus(String messageId, String status);
  Future<void> markFailed(String messageId, String error);
}

abstract interface class AttachmentRepository {
  Stream<List<RelioMediaAttachment>> watchForMessage(String messageId);
  Future<RelioMediaAttachment?> getById(String id);
  Future<RelioMediaAttachment?> getByTransferId(String transferId);
  Future<List<RelioMediaAttachment>> listAll();
  Future<RelioMediaAttachment> createPending({
    required String id,
    required String messageId,
    required String transferId,
    required MediaType mediaType,
    required String fileName,
    required String mimeType,
    required String localPath,
    required int byteSize,
    String? remoteFileName,
  });
  Future<void> updateProgress(
    String id, {
    required MediaTransferState status,
    required int bytesTransferred,
    String? errorCode,
  });
  Future<void> markCompleted(String id, {String? localPath});
  Future<void> markFailed(String id, String errorCode);
  Future<void> updateCloudMetadataStatus(String id, String status);
  Future<void> updateCloudFileStatus(String id, String status);
  Future<List<RelioMediaAttachment>> listStaleTransfers();
}

abstract interface class SOSRepository {
  Stream<RelioSosEvent?> watchActive({String? ownerDeviceId});
  Future<RelioSosEvent?> readActive({String? ownerDeviceId});
  Future<RelioSosEvent> createAndActivate({
    required String ownerDeviceId,
    required String ownerUserId,
    String? message,
    double? latitude,
    double? longitude,
    double? locationAccuracy,
    DateTime? locationCapturedAt,
  });
  Future<RelioSosEvent> createIncoming({
    required String id,
    required String ownerDeviceId,
    required String ownerUserId,
    String? message,
    double? latitude,
    double? longitude,
    double? locationAccuracy,
    DateTime? locationCapturedAt,
    required DateTime createdAt,
    required bool isActive,
  });
  Future<RelioSosEvent?> getById(String id);
  Future<void> deactivate(String id);
}

abstract interface class SyncQueueRepository {
  Stream<int> watchPendingCount();
  Stream<SyncQueueSummary> watchSummary();
  Future<int> pendingCount();
  Future<RelioQueueItem> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    String? ownerUserId,
  });
  Future<List<RelioQueueItem>> listAll();
  Future<List<RelioQueueItem>> listEligible(DateTime now);
  Future<bool> hasCompleted({
    required String entityId,
    required String operation,
  });
  Future<RelioQueueItem?> claim(String id, DateTime now);
  Future<List<RelioQueueItem>> listPending();
  Future<void> markProcessing(String id);
  Future<void> markCompleted(String id);
  Future<void> markFailed(String id, String error);
  Future<void> markRetryable(
    String id, {
    required String error,
    required DateTime nextAttemptAt,
  });
  Future<void> markWaiting(String id, String reason);
  Future<void> incrementAttempt(String id, {String? error});
  Future<void> recoverStaleProcessing(DateTime cutoff);
  Future<void> retry(String id);
  Future<void> adoptUnowned(String ownerUserId);
}

abstract interface class NearbyDeviceRepository {
  Stream<List<RelioNearbyDevice>> watchDevices();
  Future<List<RelioNearbyDevice>> listDevices();
  Future<RelioNearbyDevice?> getDevice(String deviceId);
  Future<void> upsert({
    required String deviceId,
    required String displayName,
    required DeviceStatus status,
    int? signalQuality,
    int? approxDistance,
  });
  Future<void> updateStatus(String deviceId, DeviceStatus status);
  Future<void> setTrusted(String deviceId, bool trusted);
  Future<void> setTrustedIdentity({
    required String deviceId,
    required String publicIdentityKey,
    required String fingerprint,
  });
  Future<void> setBlocked(String deviceId, bool blocked);
  Future<void> rename(String deviceId, String displayName);
}

class DriftConversationRepository implements ConversationRepository {
  DriftConversationRepository(this.db);
  final AppDatabase db;
  final _conversationController =
      StreamController<List<RelioConversation>>.broadcast();
  StreamSubscription<List<RelioConversation>>? _conversationSubscription;
  List<RelioConversation>? _latestConversations;

  @override
  Stream<List<RelioConversation>> watchConversations() {
    _conversationSubscription ??=
        (db.select(db.conversations).join([
              leftOuterJoin(
                db.messages,
                db.messages.conversationId.equalsExp(db.conversations.id),
              ),
            ])..orderBy([
              OrderingTerm.desc(db.conversations.lastMessageAt),
              OrderingTerm.desc(db.conversations.updatedAt),
              OrderingTerm.desc(db.messages.createdAt),
            ]))
            .watch()
            .map(_mapJoinedRows)
            .listen((conversations) {
              _latestConversations = conversations;
              _conversationController.add(conversations);
            });
    return Stream<List<RelioConversation>>.multi((controller) {
      final latest = _latestConversations;
      if (latest != null) controller.add(latest);
      final subscription = _conversationController.stream.listen(
        controller.add,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<RelioConversation>> listConversations() async {
    final rows =
        await (db.select(db.conversations).join([
              leftOuterJoin(
                db.messages,
                db.messages.conversationId.equalsExp(db.conversations.id),
              ),
            ])..orderBy([
              OrderingTerm.desc(db.conversations.lastMessageAt),
              OrderingTerm.desc(db.conversations.updatedAt),
              OrderingTerm.desc(db.messages.createdAt),
            ]))
            .get();
    return _mapJoinedRows(rows);
  }

  @override
  Future<RelioConversation?> getConversation(String id) async {
    final row = await (db.select(
      db.conversations,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<RelioConversation> ensureConversation({
    required String id,
    required String participantId,
    required String displayName,
    required DeviceStatus participantStatus,
  }) async {
    final existing = await (db.select(
      db.conversations,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (existing != null) return _map(existing);
    final now = DateTime.now();
    await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            id: id,
            participantId: participantId,
            displayName: displayName,
            participantStatus: participantStatus.name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return RelioConversation(
      id: id,
      participantId: participantId,
      displayName: displayName,
      participantStatus: participantStatus,
      lastMessageText: null,
      lastMessageAt: null,
      createdAt: now,
      updatedAt: now,
      unreadCount: 0,
    );
  }

  @override
  Future<void> updateLastActivity(String conversationId, DateTime time) async {
    await (db.update(
      db.conversations,
    )..where((row) => row.id.equals(conversationId))).write(
      ConversationsCompanion(
        lastMessageAt: Value(time),
        updatedAt: Value(time),
      ),
    );
  }

  @override
  Future<void> updateParticipantStatus(
    String participantId,
    DeviceStatus status,
  ) async {
    await (db.update(
      db.conversations,
    )..where((row) => row.participantId.equals(participantId))).write(
      ConversationsCompanion(
        participantStatus: Value(status.name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  List<RelioConversation> _mapJoinedRows(List<TypedResult> rows) {
    final grouped = <String, RelioConversation>{};
    for (final result in rows) {
      final conversation = result.readTable(db.conversations);
      final message = result.readTableOrNull(db.messages);
      final current = grouped[conversation.id];
      if (current != null &&
          (current.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(
                    message?.createdAt ??
                        DateTime.fromMillisecondsSinceEpoch(0),
                  ) >=
              0) {
        continue;
      }
      grouped[conversation.id] = _map(
        conversation,
        lastMessageText: message?.content,
      );
    }
    return grouped.values.toList(growable: false)..sort((a, b) {
      final aTime = a.lastMessageAt ?? a.updatedAt;
      final bTime = b.lastMessageAt ?? b.updatedAt;
      return bTime.compareTo(aTime);
    });
  }

  RelioConversation _map(Conversation row, {String? lastMessageText}) =>
      RelioConversation(
        id: row.id,
        participantId: row.participantId,
        displayName: row.displayName,
        participantStatus: _deviceStatus(row.participantStatus),
        lastMessageText: lastMessageText,
        lastMessageAt: row.lastMessageAt,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        unreadCount: row.unreadCount,
      );
}

class DriftMessageRepository implements MessageRepository {
  DriftMessageRepository(this.db, this.conversations, this.queue);
  final AppDatabase db;
  final ConversationRepository conversations;
  final SyncQueueRepository queue;
  final Map<String, StreamController<List<RelioMessage>>> _messageControllers =
      {};
  final Map<String, StreamSubscription<List<RelioMessage>>>
  _messageSubscriptions = {};

  @override
  Stream<List<RelioMessage>> watchMessages(String conversationId) {
    final controller = _messageControllers.putIfAbsent(
      conversationId,
      () => StreamController<List<RelioMessage>>.broadcast(),
    );
    _messageSubscriptions.putIfAbsent(
      conversationId,
      () =>
          (db.select(db.messages)
                ..where((row) => row.conversationId.equals(conversationId))
                ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
              .watch()
              .map((rows) => rows.map(_map).toList(growable: false))
              .listen(controller.add, onError: controller.addError),
    );
    return controller.stream;
  }

  @override
  Future<List<RelioMessage>> listMessages(String conversationId) async =>
      (await (db.select(db.messages)
                ..where((row) => row.conversationId.equals(conversationId))
                ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
              .get())
          .map(_map)
          .toList(growable: false);

  @override
  Future<RelioMessage?> getMessage(String messageId) async {
    final row = await (db.select(
      db.messages,
    )..where((item) => item.id.equals(messageId))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<RelioMessage> createOutgoingText({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required String text,
  }) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    await db.transaction(() async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: id,
              conversationId: conversationId,
              senderId: senderId,
              senderDeviceId: Value(senderDeviceId),
              messageType: MessageType.text.name,
              content: text,
              createdAt: now,
              updatedAt: now,
              deliveryStatus: DeliveryStatus.pending.name,
              cloudSyncStatus: const Value('pending'),
              isOutgoing: true,
            ),
          );
      await conversations.updateLastActivity(conversationId, now);
      await queue.enqueue(
        entityType: SyncEntityType.conversation.value,
        entityId: conversationId,
        operation: SyncOperation.conversationUpsert.value,
      );
      await queue.enqueue(
        entityType: SyncEntityType.message.value,
        entityId: id,
        operation: SyncOperation.messageUpsert.value,
      );
    });
    return RelioMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderDeviceId: senderDeviceId,
      text: text,
      time: _formatTime(now),
      createdAt: now,
      outgoing: true,
      type: MessageType.text,
      status: DeliveryStatus.pending,
    );
  }

  @override
  Future<RelioMessage> createIncomingText({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required String messageId,
    required String text,
    required DateTime createdAt,
  }) async {
    final exists = await (db.select(
      db.messages,
    )..where((row) => row.id.equals(messageId))).getSingleOrNull();
    if (exists != null) return _map(exists);
    final now = DateTime.now();
    await db.transaction(() async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: messageId,
              conversationId: conversationId,
              senderId: senderId,
              senderDeviceId: Value(senderDeviceId),
              messageType: MessageType.text.name,
              content: text,
              createdAt: createdAt,
              updatedAt: now,
              deliveryStatus: DeliveryStatus.delivered.name,
              isOutgoing: false,
            ),
          );
      await conversations.updateLastActivity(conversationId, createdAt);
      await (db.update(
        db.conversations,
      )..where((row) => row.id.equals(conversationId))).write(
        ConversationsCompanion(
          unreadCount: Value(
            (await (db.select(db.conversations)
                          ..where((row) => row.id.equals(conversationId)))
                        .getSingle())
                    .unreadCount +
                1,
          ),
        ),
      );
    });
    return RelioMessage(
      id: messageId,
      conversationId: conversationId,
      senderId: senderId,
      senderDeviceId: senderDeviceId,
      text: text,
      time: _formatTime(createdAt),
      createdAt: createdAt,
      outgoing: false,
      type: MessageType.text,
      status: DeliveryStatus.delivered,
    );
  }

  @override
  Future<RelioMessage> createOutgoingLocation({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required LocationData location,
  }) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    await db.transaction(() async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: id,
              conversationId: conversationId,
              senderId: senderId,
              senderDeviceId: Value(senderDeviceId),
              messageType: MessageType.location.name,
              content: 'ตำแหน่งที่แชร์',
              createdAt: now,
              updatedAt: now,
              deliveryStatus: DeliveryStatus.pending.name,
              cloudSyncStatus: const Value('pending'),
              isOutgoing: true,
              latitude: Value(location.latitude),
              longitude: Value(location.longitude),
            ),
          );
      await conversations.updateLastActivity(conversationId, now);
      await queue.enqueue(
        entityType: SyncEntityType.conversation.value,
        entityId: conversationId,
        operation: SyncOperation.conversationUpsert.value,
      );
      await queue.enqueue(
        entityType: SyncEntityType.message.value,
        entityId: id,
        operation: SyncOperation.messageUpsert.value,
      );
    });
    return (await getMessage(id))!;
  }

  @override
  Future<RelioMessage> createIncomingLocation({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required String messageId,
    required LocationData location,
  }) async {
    final exists = await getMessage(messageId);
    if (exists != null) return exists;
    final now = DateTime.now();
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: messageId,
            conversationId: conversationId,
            senderId: senderId,
            senderDeviceId: Value(senderDeviceId),
            messageType: MessageType.location.name,
            content: 'ตำแหน่งที่แชร์',
            createdAt: location.capturedAt,
            updatedAt: now,
            deliveryStatus: DeliveryStatus.delivered.name,
            isOutgoing: false,
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
          ),
        );
    await conversations.updateLastActivity(conversationId, location.capturedAt);
    await _incrementUnread(conversationId);
    return (await getMessage(messageId))!;
  }

  @override
  Future<RelioMessage> createOutgoingMedia({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required MessageType type,
    required String fileName,
    required String localPath,
    required String attachmentId,
    String? messageId,
  }) async {
    final now = DateTime.now();
    final id = messageId ?? const Uuid().v4();
    await db.transaction(() async {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: id,
              conversationId: conversationId,
              senderId: senderId,
              senderDeviceId: Value(senderDeviceId),
              messageType: type.name,
              content: fileName,
              createdAt: now,
              updatedAt: now,
              deliveryStatus: DeliveryStatus.pending.name,
              cloudSyncStatus: const Value('pending'),
              isOutgoing: true,
              localFilePath: Value(localPath),
              nearbyMessageId: Value(attachmentId),
            ),
          );
      await conversations.updateLastActivity(conversationId, now);
      await queue.enqueue(
        entityType: SyncEntityType.conversation.value,
        entityId: conversationId,
        operation: SyncOperation.conversationUpsert.value,
      );
      await queue.enqueue(
        entityType: SyncEntityType.message.value,
        entityId: id,
        operation: SyncOperation.messageUpsert.value,
      );
      await queue.enqueue(
        entityType: SyncEntityType.attachment.value,
        entityId: attachmentId,
        operation: SyncOperation.attachmentMetadataUpsert.value,
      );
      await queue.enqueue(
        entityType: SyncEntityType.attachment.value,
        entityId: attachmentId,
        operation: SyncOperation.attachmentUpload.value,
      );
    });
    return (await getMessage(id))!;
  }

  @override
  Future<RelioMessage> createIncomingMedia({
    required String conversationId,
    required String senderId,
    required String senderDeviceId,
    required String messageId,
    required MessageType type,
    required String fileName,
    required String localPath,
  }) async {
    final exists = await getMessage(messageId);
    if (exists != null) return exists;
    final now = DateTime.now();
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: messageId,
            conversationId: conversationId,
            senderId: senderId,
            senderDeviceId: Value(senderDeviceId),
            messageType: type.name,
            content: fileName,
            createdAt: now,
            updatedAt: now,
            deliveryStatus: DeliveryStatus.delivered.name,
            isOutgoing: false,
            localFilePath: Value(localPath),
          ),
        );
    await conversations.updateLastActivity(conversationId, now);
    await _incrementUnread(conversationId);
    return (await getMessage(messageId))!;
  }

  @override
  Future<void> updateDeliveryStatus(
    String messageId,
    DeliveryStatus status,
  ) async {
    await (db.update(
      db.messages,
    )..where((row) => row.id.equals(messageId))).write(
      MessagesCompanion(
        deliveryStatus: Value(status.name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _incrementUnread(String conversationId) async {
    final row = await (db.select(
      db.conversations,
    )..where((item) => item.id.equals(conversationId))).getSingleOrNull();
    if (row == null) return;
    await (db.update(db.conversations)
          ..where((item) => item.id.equals(conversationId)))
        .write(ConversationsCompanion(unreadCount: Value(row.unreadCount + 1)));
  }

  @override
  Future<void> updateCloudSyncStatus(String messageId, String status) async {
    await (db.update(
      db.messages,
    )..where((row) => row.id.equals(messageId))).write(
      MessagesCompanion(
        cloudSyncStatus: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<List<String>> markConversationRead(String conversationId) async {
    final unread =
        await (db.select(db.messages)..where(
              (row) =>
                  row.conversationId.equals(conversationId) &
                  row.isOutgoing.equals(false) &
                  row.readAt.isNull(),
            ))
            .get();
    if (unread.isEmpty) return const [];
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.messages)..where(
            (row) =>
                row.conversationId.equals(conversationId) &
                row.isOutgoing.equals(false) &
                row.readAt.isNull(),
          ))
          .write(MessagesCompanion(readAt: Value(now), updatedAt: Value(now)));
      await (db.update(db.conversations)
            ..where((row) => row.id.equals(conversationId)))
          .write(const ConversationsCompanion(unreadCount: Value(0)));
    });
    return unread.map((message) => message.id).toList(growable: false);
  }

  @override
  Future<void> markMessageRead(String messageId) async {
    final now = DateTime.now();
    await (db.update(db.messages)..where(
          (row) =>
              row.id.equals(messageId) &
              row.isOutgoing.equals(true) &
              row.readAt.isNull(),
        ))
        .write(MessagesCompanion(readAt: Value(now), updatedAt: Value(now)));
  }

  @override
  Future<void> markFailed(String messageId, String error) async {
    await updateDeliveryStatus(messageId, DeliveryStatus.failed);
  }

  RelioMessage _map(Message row) => RelioMessage(
    id: row.id,
    conversationId: row.conversationId,
    senderId: row.senderId,
    senderDeviceId: row.senderDeviceId,
    text: row.content,
    time: _formatTime(row.createdAt),
    createdAt: row.createdAt,
    outgoing: row.isOutgoing,
    type: _messageType(row.messageType),
    status: _deliveryStatus(row.deliveryStatus),
    cloudSyncStatus: row.cloudSyncStatus,
    localFilePath: row.localFilePath,
    latitude: row.latitude,
    longitude: row.longitude,
    nearbyMessageId: row.nearbyMessageId,
    readAt: row.readAt,
  );
}

class DriftAttachmentRepository implements AttachmentRepository {
  DriftAttachmentRepository(this.db);
  final AppDatabase db;

  @override
  Stream<List<RelioMediaAttachment>> watchForMessage(String messageId) =>
      (db.select(db.attachments)
            ..where((row) => row.messageId.equals(messageId))
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .watch()
          .map((rows) => rows.map(_map).toList(growable: false));

  @override
  Future<RelioMediaAttachment?> getById(String id) async =>
      _read(db.select(db.attachments)..where((row) => row.id.equals(id)));

  @override
  Future<RelioMediaAttachment?> getByTransferId(String transferId) async =>
      _read(
        db.select(db.attachments)
          ..where((row) => row.transferId.equals(transferId)),
      );

  @override
  Future<List<RelioMediaAttachment>> listAll() async =>
      (await (db.select(
            db.attachments,
          )..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])).get())
          .map(_map)
          .toList(growable: false);

  @override
  Future<RelioMediaAttachment> createPending({
    required String id,
    required String messageId,
    required String transferId,
    required MediaType mediaType,
    required String fileName,
    required String mimeType,
    required String localPath,
    required int byteSize,
    String? remoteFileName,
  }) async {
    final now = DateTime.now();
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: id,
            messageId: messageId,
            transferId: transferId,
            mediaType: mediaType.name,
            fileName: fileName,
            mimeType: mimeType,
            localPath: localPath,
            remoteFileName: Value(remoteFileName),
            byteSize: byteSize,
            transferStatus: MediaTransferState.pending.name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await getById(id))!;
  }

  @override
  Future<void> updateProgress(
    String id, {
    required MediaTransferState status,
    required int bytesTransferred,
    String? errorCode,
  }) async {
    await (db.update(db.attachments)..where((row) => row.id.equals(id))).write(
      AttachmentsCompanion(
        bytesTransferred: Value(bytesTransferred),
        transferStatus: Value(status.name),
        errorCode: Value(errorCode),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> markCompleted(String id, {String? localPath}) async {
    await (db.update(db.attachments)..where((row) => row.id.equals(id))).write(
      AttachmentsCompanion(
        localPath: localPath == null ? const Value.absent() : Value(localPath),
        transferStatus: Value(MediaTransferState.completed.name),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> updateCloudMetadataStatus(String id, String status) async {
    await (db.update(db.attachments)..where((row) => row.id.equals(id))).write(
      AttachmentsCompanion(
        cloudMetadataStatus: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> updateCloudFileStatus(String id, String status) async {
    await (db.update(db.attachments)..where((row) => row.id.equals(id))).write(
      AttachmentsCompanion(
        cloudFileStatus: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> markFailed(String id, String errorCode) => updateProgress(
    id,
    status: MediaTransferState.failed,
    bytesTransferred: 0,
    errorCode: errorCode,
  );

  @override
  Future<List<RelioMediaAttachment>> listStaleTransfers() async =>
      (await (db.select(db.attachments)..where(
                (row) => row.transferStatus.equals(
                  MediaTransferState.transferring.name,
                ),
              ))
              .get())
          .map(_map)
          .toList(growable: false);

  Future<RelioMediaAttachment?> _read(
    SimpleSelectStatement<$AttachmentsTable, Attachment> query,
  ) async {
    final row = await query.getSingleOrNull();
    return row == null ? null : _map(row);
  }

  RelioMediaAttachment _map(Attachment row) => RelioMediaAttachment(
    id: row.id,
    messageId: row.messageId,
    transferId: row.transferId,
    mediaType: _mediaType(row.mediaType),
    fileName: row.fileName,
    mimeType: row.mimeType,
    localPath: row.localPath,
    remoteFileName: row.remoteFileName,
    byteSize: row.byteSize,
    bytesTransferred: row.bytesTransferred,
    transferStatus: _mediaTransferState(row.transferStatus),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    width: row.width,
    height: row.height,
    durationMs: row.durationMs,
    errorCode: row.errorCode,
    checksumSha256: row.checksumSha256,
    cloudMetadataStatus: row.cloudMetadataStatus,
    cloudFileStatus: row.cloudFileStatus,
  );
}

class DriftSosRepository implements SOSRepository {
  DriftSosRepository(this.db, this.queue, {this.ownerUserIdProvider});
  final AppDatabase db;
  final SyncQueueRepository queue;
  final String? Function()? ownerUserIdProvider;

  @override
  Stream<RelioSosEvent?> watchActive({String? ownerDeviceId}) =>
      (db.select(db.sosEvents)
            ..where(
              (row) =>
                  row.isActive.equals(true) &
                  (ownerDeviceId == null
                      ? const Constant(true)
                      : row.ownerDeviceId.equals(ownerDeviceId)),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .watch()
          .map((rows) => rows.isEmpty ? null : _map(rows.first));

  @override
  Future<RelioSosEvent?> readActive({String? ownerDeviceId}) async {
    final row =
        await (db.select(db.sosEvents)
              ..where(
                (item) =>
                    item.isActive.equals(true) &
                    (ownerDeviceId == null
                        ? const Constant(true)
                        : item.ownerDeviceId.equals(ownerDeviceId)),
              )
              ..orderBy([(item) => OrderingTerm.desc(item.updatedAt)]))
            .getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<RelioSosEvent> createIncoming({
    required String id,
    required String ownerDeviceId,
    required String ownerUserId,
    String? message,
    double? latitude,
    double? longitude,
    double? locationAccuracy,
    DateTime? locationCapturedAt,
    required DateTime createdAt,
    required bool isActive,
  }) async {
    final now = DateTime.now();
    await db
        .into(db.sosEvents)
        .insertOnConflictUpdate(
          SosEventsCompanion.insert(
            id: id,
            ownerDeviceId: ownerDeviceId,
            ownerUserId: ownerUserId,
            message: Value(message),
            latitude: Value(latitude),
            longitude: Value(longitude),
            locationAccuracy: Value(locationAccuracy),
            locationCapturedAt: Value(locationCapturedAt),
            createdAt: createdAt,
            updatedAt: now,
            isActive: isActive,
            deliveryStatus: DeliveryStatus.delivered.name,
          ),
        );
    final row = await (db.select(
      db.sosEvents,
    )..where((item) => item.id.equals(id))).getSingle();
    return _map(row);
  }

  @override
  Future<RelioSosEvent?> getById(String id) async {
    final row = await (db.select(
      db.sosEvents,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<RelioSosEvent> createAndActivate({
    required String ownerDeviceId,
    required String ownerUserId,
    String? message,
    double? latitude,
    double? longitude,
    double? locationAccuracy,
    DateTime? locationCapturedAt,
  }) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    await db.transaction(() async {
      await (db.update(db.sosEvents)..where((row) => row.isActive.equals(true)))
          .write(const SosEventsCompanion(isActive: Value(false)));
      await db
          .into(db.sosEvents)
          .insert(
            SosEventsCompanion.insert(
              id: id,
              ownerDeviceId: ownerDeviceId,
              ownerUserId: ownerUserId,
              message: Value(message),
              latitude: Value(latitude),
              longitude: Value(longitude),
              locationAccuracy: Value(locationAccuracy),
              locationCapturedAt: Value(locationCapturedAt),
              createdAt: now,
              updatedAt: now,
              isActive: true,
              deliveryStatus: DeliveryStatus.pending.name,
            ),
          );
      // Guest SOS ต้องอยู่ในเครื่อง ไม่ผูกกับ Cloud identity ที่อาจเปลี่ยนภายหลัง
      final currentOwner = ownerUserIdProvider?.call();
      if (ownerUserId.isNotEmpty && currentOwner == ownerUserId) {
        await queue.enqueue(
          entityType: SyncEntityType.sosEvent.value,
          entityId: id,
          operation: SyncOperation.sosUpsert.value,
          ownerUserId: ownerUserId,
        );
      }
    });
    return RelioSosEvent(
      id: id,
      ownerDeviceId: ownerDeviceId,
      ownerUserId: ownerUserId,
      message: message,
      latitude: latitude,
      longitude: longitude,
      locationAccuracy: locationAccuracy,
      locationCapturedAt: locationCapturedAt,
      createdAt: now,
      updatedAt: now,
      isActive: true,
      deliveryStatus: DeliveryStatus.pending,
    );
  }

  @override
  Future<void> deactivate(String id) async {
    await db.transaction(() async {
      final event = await (db.select(
        db.sosEvents,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      await (db.update(db.sosEvents)..where((row) => row.id.equals(id))).write(
        SosEventsCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
      final currentOwner = ownerUserIdProvider?.call();
      if (event != null &&
          event.ownerUserId.isNotEmpty &&
          event.ownerUserId == currentOwner) {
        await queue.enqueue(
          entityType: SyncEntityType.sosEvent.value,
          entityId: id,
          operation: SyncOperation.sosUpsert.value,
          ownerUserId: event.ownerUserId,
        );
      }
    });
  }

  RelioSosEvent _map(SosEvent row) => RelioSosEvent(
    id: row.id,
    ownerDeviceId: row.ownerDeviceId,
    ownerUserId: row.ownerUserId,
    message: row.message,
    latitude: row.latitude,
    longitude: row.longitude,
    locationAccuracy: row.locationAccuracy,
    locationCapturedAt: row.locationCapturedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    isActive: row.isActive,
    deliveryStatus: _deliveryStatus(row.deliveryStatus),
  );
}

class DriftSyncQueueRepository implements SyncQueueRepository {
  DriftSyncQueueRepository(this.db, {this.ownerUserIdProvider});

  final AppDatabase db;
  final String? Function()? ownerUserIdProvider;

  @override
  Stream<int> watchPendingCount() =>
      watchSummary().map((summary) => summary.pending);

  @override
  Stream<SyncQueueSummary> watchSummary() =>
      (db.select(db.syncQueue)
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .watch()
          .map(_summarize);

  @override
  Future<int> pendingCount() async => (await listAll())
      .where((item) => item.status == SyncQueueStatus.pending.value)
      .length;

  @override
  Future<RelioQueueItem> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    String? ownerUserId,
  }) async {
    if (SyncOperation.parse(operation) == null) {
      throw ArgumentError.value(
        operation,
        'operation',
        'Unsupported sync operation',
      );
    }
    final effectiveOwnerUserId = ownerUserId ?? ownerUserIdProvider?.call();
    final now = DateTime.now();
    final existing =
        await (db.select(db.syncQueue)
              ..where(
                (row) =>
                    row.entityType.equals(entityType) &
                    row.entityId.equals(entityId) &
                    row.operation.equals(operation) &
                    row.status.equals(SyncQueueStatus.completed.value).not(),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      // Coalesce repeated local edits, but never change an existing owner's scope.
      await (db.update(
        db.syncQueue,
      )..where((row) => row.id.equals(existing.id))).write(
        SyncQueueCompanion(
          status: Value(SyncQueueStatus.pending.value),
          attemptCount: const Value(0),
          lastError: const Value<String?>(null),
          nextAttemptAt: const Value<DateTime?>(null),
          // An existing Guest row stays unowned until explicit adoption.
          ownerUserId: const Value.absent(),
          updatedAt: Value(now),
        ),
      );
      return _map(
        existing.copyWith(
          status: SyncQueueStatus.pending.value,
          attemptCount: 0,
          lastError: const Value<String?>(null),
          nextAttemptAt: const Value<DateTime?>(null),
          ownerUserId: Value<String?>(existing.ownerUserId),
          updatedAt: now,
        ),
      );
    }

    final id = const Uuid().v4();
    await db
        .into(db.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            id: id,
            entityType: entityType,
            entityId: entityId,
            operation: operation,
            status: SyncQueueStatus.pending.value,
            ownerUserId: Value<String?>(effectiveOwnerUserId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return RelioQueueItem(
      id: id,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      status: SyncQueueStatus.pending.value,
      ownerUserId: effectiveOwnerUserId,
      attemptCount: 0,
      lastError: null,
      createdAt: now,
      updatedAt: now,
      nextAttemptAt: null,
    );
  }

  @override
  Future<List<RelioQueueItem>> listAll() async =>
      (await (db.select(
            db.syncQueue,
          )..orderBy([(row) => OrderingTerm.asc(row.createdAt)])).get())
          .map(_map)
          .toList(growable: false);

  @override
  Future<List<RelioQueueItem>> listEligible(DateTime now) async =>
      (await (db.select(db.syncQueue)
                ..where(
                  (row) =>
                      row.status.equals(SyncQueueStatus.pending.value) &
                      (row.nextAttemptAt.isNull() |
                          row.nextAttemptAt.isSmallerOrEqualValue(now)),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
              .get())
          .map(_map)
          .toList(growable: false);

  @override
  Future<bool> hasCompleted({
    required String entityId,
    required String operation,
  }) async =>
      (await (db.select(db.syncQueue)
            ..where(
              (row) =>
                  row.entityId.equals(entityId) &
                  row.operation.equals(operation) &
                  row.status.equals(SyncQueueStatus.completed.value),
            )
            ..limit(1))
          .getSingleOrNull()) !=
      null;

  @override
  Future<RelioQueueItem?> claim(String id, DateTime now) async {
    final row =
        await (db.select(db.syncQueue)..where(
              (item) =>
                  item.id.equals(id) &
                  item.status.equals(SyncQueueStatus.pending.value) &
                  (item.nextAttemptAt.isNull() |
                      item.nextAttemptAt.isSmallerOrEqualValue(now)),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    await (db.update(db.syncQueue)..where((item) => item.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(SyncQueueStatus.processing.value),
        attemptCount: Value(row.attemptCount + 1),
        updatedAt: Value(now),
      ),
    );
    return _map(
      row.copyWith(
        status: SyncQueueStatus.processing.value,
        attemptCount: row.attemptCount + 1,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<List<RelioQueueItem>> listPending() => listEligible(DateTime.now());

  @override
  Future<void> markProcessing(String id) =>
      _writeStatus(id, SyncQueueStatus.processing.value);

  @override
  Future<void> markCompleted(String id) async {
    await (db.update(db.syncQueue)..where((row) => row.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(SyncQueueStatus.completed.value),
        lastError: const Value<String?>(null),
        nextAttemptAt: const Value<DateTime?>(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> markFailed(String id, String error) async {
    await (db.update(db.syncQueue)..where((row) => row.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(SyncQueueStatus.failed.value),
        lastError: Value(error),
        nextAttemptAt: const Value<DateTime?>(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> markRetryable(
    String id, {
    required String error,
    required DateTime nextAttemptAt,
  }) async {
    await (db.update(db.syncQueue)..where((row) => row.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(SyncQueueStatus.pending.value),
        lastError: Value(error),
        nextAttemptAt: Value(nextAttemptAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> markWaiting(String id, String reason) async {
    await (db.update(db.syncQueue)..where((row) => row.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(SyncQueueStatus.pending.value),
        lastError: Value(reason),
        nextAttemptAt: const Value<DateTime?>(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> incrementAttempt(String id, {String? error}) async {
    final row = await (db.select(
      db.syncQueue,
    )..where((item) => item.id.equals(id))).getSingle();
    await (db.update(db.syncQueue)..where((item) => item.id.equals(id))).write(
      SyncQueueCompanion(
        attemptCount: Value(row.attemptCount + 1),
        lastError: Value(error),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> recoverStaleProcessing(DateTime cutoff) async {
    // คืนงานที่ค้าง processing จาก process ก่อนหน้าให้เริ่มใหม่ได้
    await (db.update(db.syncQueue)..where(
          (row) =>
              row.status.equals(SyncQueueStatus.processing.value) &
              row.updatedAt.isSmallerThanValue(cutoff),
        ))
        .write(
          SyncQueueCompanion(
            status: Value(SyncQueueStatus.pending.value),
            lastError: const Value('recovered_stale_processing'),
            nextAttemptAt: const Value<DateTime?>(null),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<void> retry(String id) async {
    await (db.update(db.syncQueue)..where((row) => row.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(SyncQueueStatus.pending.value),
        attemptCount: const Value(0),
        lastError: const Value<String?>(null),
        nextAttemptAt: const Value<DateTime?>(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> adoptUnowned(String ownerUserId) async {
    await (db.update(db.syncQueue)..where(
          (row) =>
              row.ownerUserId.isNull() &
              row.status.isIn([
                SyncQueueStatus.pending.value,
                SyncQueueStatus.failed.value,
              ]),
        ))
        .write(
          SyncQueueCompanion(
            ownerUserId: Value<String?>(ownerUserId),
            status: Value(SyncQueueStatus.pending.value),
            attemptCount: const Value(0),
            lastError: const Value<String?>(null),
            nextAttemptAt: const Value<DateTime?>(null),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> _writeStatus(String id, String status) async {
    await (db.update(db.syncQueue)..where((row) => row.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  SyncQueueSummary _summarize(List<SyncQueueData> rows) {
    var pending = 0;
    var processing = 0;
    var completed = 0;
    var failed = 0;
    for (final row in rows) {
      switch (row.status) {
        case 'pending':
          pending++;
        case 'processing':
          processing++;
        case 'completed':
          completed++;
        case 'failed':
          failed++;
      }
    }
    return SyncQueueSummary(
      pending: pending,
      processing: processing,
      completed: completed,
      failed: failed,
    );
  }

  RelioQueueItem _map(SyncQueueData row) => RelioQueueItem(
    id: row.id,
    entityType: row.entityType,
    entityId: row.entityId,
    operation: row.operation,
    status: row.status,
    ownerUserId: row.ownerUserId,
    attemptCount: row.attemptCount,
    lastError: row.lastError,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    nextAttemptAt: row.nextAttemptAt,
  );
}

class DriftNearbyDeviceRepository implements NearbyDeviceRepository {
  DriftNearbyDeviceRepository(this.db);
  final AppDatabase db;

  @override
  Stream<List<RelioNearbyDevice>> watchDevices() =>
      (db.select(db.nearbyDevices)
            ..orderBy([(row) => OrderingTerm.desc(row.lastSeenAt)]))
          .watch()
          .map((rows) => rows.map(_map).toList(growable: false));

  @override
  Future<List<RelioNearbyDevice>> listDevices() async =>
      (await (db.select(
            db.nearbyDevices,
          )..orderBy([(row) => OrderingTerm.desc(row.lastSeenAt)])).get())
          .map(_map)
          .toList(growable: false);

  @override
  Future<RelioNearbyDevice?> getDevice(String deviceId) async {
    final row = await (db.select(
      db.nearbyDevices,
    )..where((item) => item.deviceId.equals(deviceId))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<void> upsert({
    required String deviceId,
    required String displayName,
    required DeviceStatus status,
    int? signalQuality,
    int? approxDistance,
  }) async {
    final existing = await (db.select(
      db.nearbyDevices,
    )..where((row) => row.deviceId.equals(deviceId))).getSingleOrNull();
    final companion = NearbyDevicesCompanion.insert(
      deviceId: deviceId,
      displayName: displayName,
      status: status.name,
      lastSeenAt: DateTime.now(),
      signalQuality: Value(signalQuality),
      approxDistance: Value(approxDistance),
      isTrusted: Value(existing?.isTrusted ?? false),
      isBlocked: Value(existing?.isBlocked ?? false),
      autoReconnectEnabled: Value(existing?.autoReconnectEnabled ?? false),
      publicIdentityKey: Value(existing?.publicIdentityKey),
      publicIdentityFingerprint: Value(existing?.publicIdentityFingerprint),
    );
    await db.into(db.nearbyDevices).insertOnConflictUpdate(companion);
  }

  @override
  Future<void> updateStatus(String deviceId, DeviceStatus status) async {
    await (db.update(
      db.nearbyDevices,
    )..where((row) => row.deviceId.equals(deviceId))).write(
      NearbyDevicesCompanion(
        status: Value(status.name),
        lastSeenAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> setTrusted(String deviceId, bool trusted) async {
    final saved = await getDevice(deviceId);
    final mayReconnect =
        trusted &&
        saved?.publicIdentityKey != null &&
        saved?.publicIdentityFingerprint != null &&
        saved?.isBlocked != true;
    await (db.update(
      db.nearbyDevices,
    )..where((row) => row.deviceId.equals(deviceId))).write(
      NearbyDevicesCompanion(
        isTrusted: Value(trusted),
        autoReconnectEnabled: Value(mayReconnect),
      ),
    );
  }

  @override
  Future<void> setTrustedIdentity({
    required String deviceId,
    required String publicIdentityKey,
    required String fingerprint,
  }) async {
    if (publicIdentityKey.isEmpty ||
        publicIdentityKey.length > 2048 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw ArgumentError('Invalid peer identity material.');
    }
    final saved = await getDevice(deviceId);
    if (saved?.isBlocked == true) {
      throw StateError('Blocked peers cannot be trusted.');
    }
    await (db.update(
      db.nearbyDevices,
    )..where((row) => row.deviceId.equals(deviceId))).write(
      NearbyDevicesCompanion(
        isTrusted: const Value(true),
        autoReconnectEnabled: const Value(true),
        publicIdentityKey: Value(publicIdentityKey),
        publicIdentityFingerprint: Value(fingerprint),
      ),
    );
  }

  @override
  Future<void> setBlocked(String deviceId, bool blocked) async {
    final saved = await getDevice(deviceId);
    final reconnect =
        !blocked &&
        saved?.isTrusted == true &&
        saved?.publicIdentityKey != null &&
        saved?.publicIdentityFingerprint != null;
    await (db.update(
      db.nearbyDevices,
    )..where((row) => row.deviceId.equals(deviceId))).write(
      NearbyDevicesCompanion(
        isBlocked: Value(blocked),
        autoReconnectEnabled: Value(reconnect),
      ),
    );
  }

  @override
  Future<void> rename(String deviceId, String displayName) async {
    final name = displayName.trim();
    if (name.isEmpty || name.length > 60) {
      throw ArgumentError.value(displayName, 'displayName');
    }
    await (db.update(db.nearbyDevices)
          ..where((row) => row.deviceId.equals(deviceId)))
        .write(NearbyDevicesCompanion(displayName: Value(name)));
  }

  RelioNearbyDevice _map(NearbyDevice row) => RelioNearbyDevice(
    deviceId: row.deviceId,
    displayName: row.displayName,
    status: _deviceStatus(row.status),
    lastSeenAt: row.lastSeenAt,
    signalQuality: row.signalQuality,
    approxDistance: row.approxDistance,
    isTrusted: row.isTrusted,
    isBlocked: row.isBlocked,
    autoReconnectEnabled: row.autoReconnectEnabled,
    publicIdentityKey: row.publicIdentityKey,
    publicIdentityFingerprint: row.publicIdentityFingerprint,
  );
}

class RelioDeviceIdentityRepository {
  RelioDeviceIdentityRepository(this.db);
  final AppDatabase db;

  Future<String> getDeviceId() async {
    final saved = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals('device_id'))).getSingleOrNull();
    if (saved != null && saved.value.isNotEmpty) return saved.value;
    final id = const Uuid().v4();
    await _write('device_id', id);
    return id;
  }

  Future<String> getDisplayName() async {
    final saved = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals('display_name'))).getSingleOrNull();
    if (saved != null && saved.value.isNotEmpty) return saved.value;
    await _write('display_name', 'ผู้ใช้ RELIO');
    return 'ผู้ใช้ RELIO';
  }

  Future<void> setDisplayName(String displayName) async {
    final normalized = displayName.trim();
    if (normalized.isEmpty || normalized.length > 60) {
      throw ArgumentError.value(displayName, 'displayName');
    }
    await _write('display_name', normalized);
  }

  Future<void> _write(String key, String value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: DateTime.now(),
          ),
        );
  }
}

class RelioSettingsRepository {
  RelioSettingsRepository(this.db);
  final AppDatabase db;

  Future<bool> getBool(String key, {required bool defaultValue}) async {
    final saved = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    if (saved == null) return defaultValue;
    return saved.value == 'true';
  }

  Future<void> setBool(String key, bool value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: key,
            value: value.toString(),
            updatedAt: DateTime.now(),
          ),
        );
  }
}

class RelioRepositories {
  RelioRepositories(this.database, {String? Function()? ownerUserIdProvider})
    : syncQueue = DriftSyncQueueRepository(
        database,
        ownerUserIdProvider: ownerUserIdProvider,
      ),
      conversations = DriftConversationRepository(database),
      nearbyDevices = DriftNearbyDeviceRepository(database),
      settings = RelioSettingsRepository(database),
      attachments = DriftAttachmentRepository(database) {
    messages = DriftMessageRepository(database, conversations, syncQueue);
    sos = DriftSosRepository(
      database,
      syncQueue,
      ownerUserIdProvider: ownerUserIdProvider,
    );
  }

  final AppDatabase database;
  late final MessageRepository messages;
  late final ConversationRepository conversations;
  late final SOSRepository sos;
  final SyncQueueRepository syncQueue;
  final NearbyDeviceRepository nearbyDevices;
  final RelioSettingsRepository settings;
  final AttachmentRepository attachments;

  Future<void> seedPrototypeData() async {
    final existing = await conversations.listConversations();
    if (existing.isNotEmpty) return;
    for (final chat in RelioMockData.chats) {
      await conversations.ensureConversation(
        id: chat.id,
        participantId: chat.id,
        displayName: chat.name,
        participantStatus: chat.status,
      );
    }
    for (final device in RelioMockData.devices) {
      await nearbyDevices.upsert(
        deviceId: device.id,
        displayName: device.name,
        status: device.status,
        signalQuality: device.signalQuality,
        approxDistance: device.distanceMetersApprox,
      );
    }
    final somchai = await conversations.ensureConversation(
      id: 'somchai',
      participantId: 'somchai',
      displayName: 'สมชาย ใจดี',
      participantStatus: DeviceStatus.sos,
    );
    for (final message in RelioMockData.initialMessages) {
      final createdAt = DateTime.now().subtract(
        Duration(minutes: RelioMockData.initialMessages.length),
      );
      final existingMessage = await (database.select(
        database.messages,
      )..where((row) => row.id.equals(message.id))).getSingleOrNull();
      if (existingMessage != null) continue;
      await database
          .into(database.messages)
          .insert(
            MessagesCompanion.insert(
              id: message.id,
              conversationId: somchai.id,
              senderId: message.outgoing ? 'minnie' : 'somchai',
              messageType: message.type.name,
              content: message.text,
              createdAt: createdAt,
              updatedAt: createdAt,
              deliveryStatus: (message.status ?? DeliveryStatus.delivered).name,
              isOutgoing: message.outgoing,
            ),
          );
    }
    await conversations.updateLastActivity('somchai', DateTime.now());
  }
}

DeviceStatus _deviceStatus(String value) => DeviceStatus.values.firstWhere(
  (item) => item.name == value,
  orElse: () => DeviceStatus.offline,
);

DeliveryStatus _deliveryStatus(String value) =>
    DeliveryStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => DeliveryStatus.failed,
    );

MessageType _messageType(String value) => MessageType.values.firstWhere(
  (item) => item.name == value,
  orElse: () => MessageType.text,
);

MediaType _mediaType(String value) => MediaType.values.firstWhere(
  (item) => item.name == value,
  orElse: () => MediaType.image,
);

MediaTransferState _mediaTransferState(String value) =>
    MediaTransferState.values.firstWhere(
      (item) => item.name == value,
      orElse: () => MediaTransferState.failed,
    );

String _formatTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
