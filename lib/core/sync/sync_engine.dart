import 'dart:async';

import '../cloud/cloud_data_source.dart';
import '../cloud/cloud_models.dart';
import '../cloud/cloud_storage_policy.dart';
import '../domain/relio_entities.dart';
import '../media/media_storage_service.dart';
import '../notifications/local_notification_service.dart';
import '../notifications/notification_preview.dart';
import '../repositories/local_repositories.dart';
import '../../data/models/prototype_models.dart' show DeviceStatus;
import 'sync_types.dart';

abstract interface class SyncClock {
  DateTime now();
}

class SystemSyncClock implements SyncClock {
  const SystemSyncClock();

  @override
  DateTime now() => DateTime.now();
}

class SyncRetryPolicy {
  const SyncRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 15),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;

  Duration delayForAttempt(int attempt) {
    final exponent = attempt <= 1 ? 0 : attempt - 1;
    final seconds = baseDelay.inSeconds * (1 << exponent);
    return Duration(seconds: seconds).compareTo(maxDelay) > 0
        ? maxDelay
        : Duration(seconds: seconds);
  }
}

enum SyncEngineState {
  idle,
  waitingForCloud,
  waitingForOwnership,
  running,
  completed,
  error,
}

class SyncOwnershipException implements Exception {
  const SyncOwnershipException(this.message);

  final String message;
}

class SyncEngineSnapshot {
  const SyncEngineSnapshot({
    required this.state,
    required this.cloudState,
    required this.authState,
    required this.queueSummary,
    this.currentItem,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastError,
    this.nextRetryAt,
  });

  const SyncEngineSnapshot.initial()
    : state = SyncEngineState.idle,
      cloudState = CloudState.notConfigured,
      authState = AuthState.guest,
      queueSummary = const SyncQueueSummary.empty(),
      currentItem = null,
      lastSuccessAt = null,
      lastFailureAt = null,
      lastError = null,
      nextRetryAt = null;

  final SyncEngineState state;
  final CloudState cloudState;
  final AuthState authState;
  final SyncQueueSummary queueSummary;
  final RelioQueueItem? currentItem;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String? lastError;
  final DateTime? nextRetryAt;
}

class SyncEngine {
  SyncEngine({
    required this.repositories,
    required this.cloud,
    required this.identity,
    required this.mediaStorage,
    this.localNotifications,
    this.isConversationActive,
    SyncClock? clock,
    SyncRetryPolicy? retryPolicy,
    this.staleProcessingAge = const Duration(minutes: 10),
  }) : clock = clock ?? const SystemSyncClock(),
       retryPolicy = retryPolicy ?? const SyncRetryPolicy();

  final RelioRepositories repositories;
  final CloudDataSource cloud;
  final RelioDeviceIdentityRepository identity;
  final MediaStorageService mediaStorage;
  final LocalNotificationSink? localNotifications;
  final bool Function(String conversationId)? isConversationActive;
  final SyncClock clock;
  final SyncRetryPolicy retryPolicy;
  final Duration staleProcessingAge;

  final _stateController = StreamController<SyncEngineSnapshot>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  SyncEngineSnapshot _snapshot = const SyncEngineSnapshot.initial();
  Future<void>? _runOperation;
  Timer? _queueRetryTimer;
  Timer? _pullRetryTimer;
  int _pullRetryCount = 0;
  bool _started = false;
  bool _disposed = false;

  SyncEngineSnapshot get snapshot => _snapshot;

  Stream<SyncEngineSnapshot> watchState() => _stateController.stream;

  Future<void> initialize() async {
    if (_started) return;
    await repositories.syncQueue.recoverStaleProcessing(
      clock.now().subtract(staleProcessingAge),
    );
    _started = true;
    _subscriptions.add(cloud.watchCloudState().listen((_) => _scheduleRun()));
    _subscriptions.add(cloud.watchAuthState().listen((_) => _scheduleRun()));
    _subscriptions.add(
      repositories.syncQueue.watchSummary().listen((_) => _scheduleRun()),
    );
    await _refreshSnapshot();
  }

  Future<void> run({bool adoptUnownedItems = false}) {
    if (_runOperation != null) return _runOperation!;
    final operation = _run(adoptUnownedItems: adoptUnownedItems);
    _runOperation = operation;
    return operation.whenComplete(() => _runOperation = null);
  }

  Future<void> retryFailed(String id) async {
    await repositories.syncQueue.retry(id);
    await run();
  }

  Future<void> adoptGuestItemsAndRun() async {
    final currentIdentity = cloud.currentIdentity;
    if (currentIdentity == null || cloud.authState != AuthState.authenticated) {
      await _setWaitingForCloud();
      return;
    }
    await repositories.syncQueue.adoptUnowned(currentIdentity.userId);
    await repositories.conversations.adoptUnowned(currentIdentity.userId);
    await run();
  }

  Future<CloudConversationBinding> linkConversationToCloud({
    required String localConversationId,
    required String peerUserId,
  }) async {
    final owner = cloud.currentIdentity;
    if (!_isCloudReady || owner == null) {
      throw const CloudException(
        'กรุณาเข้าสู่ระบบก่อนเชื่อม Cloud',
        code: 'signedOut',
      );
    }
    if (peerUserId.trim().isEmpty || peerUserId == owner.userId) {
      throw const CloudException(
        'บัญชีปลายทางไม่ถูกต้อง',
        code: 'invalidInput',
      );
    }
    final conversation = await repositories.conversations.getConversation(
      localConversationId,
    );
    if (conversation == null) {
      throw const CloudException('ไม่พบบทสนทนาในเครื่อง', code: 'notFound');
    }
    final remote = await cloud.createOrGetDirectConversation(
      peerUserId: peerUserId.trim(),
    );
    final link = CloudConversationBinding(
      localConversationId: localConversationId,
      cloudConversationId: remote.id,
      ownerUserId: owner.userId,
      peerUserId: remote.participantId,
    );
    await repositories.cloudLinks.save(link);
    await run();
    return link;
  }

  Future<void> queueReadReceipts({
    required String localConversationId,
    required List<String> messageIds,
  }) async {
    final owner = cloud.currentIdentity;
    if (!_isCloudReady ||
        owner == null ||
        await repositories.cloudLinks.get(
              localConversationId: localConversationId,
              ownerUserId: owner.userId,
            ) ==
            null) {
      return;
    }
    for (final id in messageIds) {
      final message = await repositories.messages.getMessage(id);
      if (message == null ||
          message.outgoing ||
          message.readAt == null ||
          message.conversationId != localConversationId) {
        continue;
      }
      await repositories.syncQueue.enqueue(
        entityType: SyncEntityType.message.value,
        entityId: id,
        operation: SyncOperation.readReceiptUpsert.value,
        ownerUserId: owner.userId,
      );
    }
    if (_runOperation == null) await run();
  }

  Future<void> _run({required bool adoptUnownedItems}) async {
    if (_disposed) return;
    if (!_isCloudReady) {
      await _setWaitingForCloud();
      return;
    }
    final currentIdentity = cloud.currentIdentity!;
    if (adoptUnownedItems) {
      await repositories.syncQueue.adoptUnowned(currentIdentity.userId);
      await repositories.conversations.adoptUnowned(currentIdentity.userId);
    }

    await _emit(
      state: SyncEngineState.running,
      currentItem: null,
      lastError: null,
    );
    var hadFailure = false;
    var hadOwnershipBlock = false;
    try {
      await _importAndPull(currentIdentity.userId);
      _pullRetryCount = 0;
      _pullRetryTimer?.cancel();
      _pullRetryTimer = null;
    } on Object catch (error) {
      hadFailure = true;
      _schedulePullRetry();
      final code = error is CloudException ? error.code : 'pull_failed';
      await _emit(
        state: SyncEngineState.running,
        lastFailureAt: clock.now(),
        lastError: code,
      );
    }
    while (!_disposed) {
      if (!_isCloudReady ||
          cloud.currentIdentity?.userId != currentIdentity.userId) {
        break;
      }
      final candidates = await repositories.syncQueue.listEligible(clock.now());
      var claimedAny = false;
      for (final candidate in candidates) {
        if (candidate.ownerUserId != currentIdentity.userId) {
          hadOwnershipBlock = true;
          continue;
        }
        if (!await _dependenciesReady(candidate, currentIdentity.userId)) {
          continue;
        }
        final item = await repositories.syncQueue.claim(
          candidate.id,
          clock.now(),
        );
        if (item == null) continue;
        claimedAny = true;
        await _markLocalSyncing(item);
        await _emit(state: SyncEngineState.running, currentItem: item);
        try {
          await _process(item, currentIdentity.userId);
          if (!_isCloudReady ||
              cloud.currentIdentity?.userId != currentIdentity.userId) {
            throw const SyncOwnershipException('waiting_for_ownership');
          }
          await repositories.syncQueue.markCompleted(item.id);
          await _markLocalSuccess(item);
          await _emit(
            state: SyncEngineState.running,
            currentItem: null,
            lastSuccessAt: clock.now(),
          );
        } on Object catch (error) {
          if (error is SyncOwnershipException) {
            hadOwnershipBlock = true;
            await repositories.syncQueue.markWaiting(item.id, error.message);
            continue;
          }
          hadFailure = true;
          await _handleFailure(item, error);
        }
      }
      if (!claimedAny) break;
    }
    await _refreshSnapshot(
      state: hadOwnershipBlock
          ? SyncEngineState.waitingForOwnership
          : hadFailure
          ? SyncEngineState.error
          : SyncEngineState.completed,
    );
  }

  Future<bool> _dependenciesReady(
    RelioQueueItem item,
    String currentUserId,
  ) async {
    final all = await repositories.syncQueue.listAll();
    bool completed(String entityId, String operation) => all.any(
      (queued) =>
          queued.entityId == entityId &&
          queued.operation == operation &&
          queued.status == SyncQueueStatus.completed.value,
    );
    bool queued(String entityId, String operation) => all.any(
      (queued) => queued.entityId == entityId && queued.operation == operation,
    );

    switch (SyncOperation.parse(item.operation)) {
      case SyncOperation.messageUpsert:
        final message = await repositories.messages.getMessage(item.entityId);
        if (message == null) return true;
        if (message.type.name != 'text' || message.conversationId == null) {
          return false;
        }
        final link = await repositories.cloudLinks.get(
          localConversationId: message.conversationId!,
          ownerUserId: currentUserId,
        );
        if (link == null) return false;
        return !queued(
              message.conversationId ?? '',
              SyncOperation.conversationUpsert.value,
            ) ||
            completed(
              message.conversationId!,
              SyncOperation.conversationUpsert.value,
            );
      case SyncOperation.attachmentMetadataUpsert:
        final attachment = await repositories.attachments.getById(
          item.entityId,
        );
        if (attachment == null) return true;
        final parentQueue = all.where(
          (queued) =>
              queued.entityId == attachment.messageId &&
              queued.operation == SyncOperation.messageUpsert.value,
        );
        if (parentQueue.isEmpty ||
            parentQueue.any((queued) => queued.ownerUserId != currentUserId)) {
          return false;
        }
        return !queued(
              attachment.messageId,
              SyncOperation.messageUpsert.value,
            ) ||
            completed(attachment.messageId, SyncOperation.messageUpsert.value);
      case SyncOperation.attachmentUpload:
        final attachmentQueue = all.where(
          (queued) =>
              queued.entityId == item.entityId &&
              queued.operation == SyncOperation.attachmentMetadataUpsert.value,
        );
        if (attachmentQueue.any(
          (queued) => queued.ownerUserId != currentUserId,
        )) {
          return false;
        }
        return completed(
          item.entityId,
          SyncOperation.attachmentMetadataUpsert.value,
        );
      case SyncOperation.profileUpsert || SyncOperation.sosUpsert || null:
        return true;
      case SyncOperation.conversationUpsert:
        return await repositories.cloudLinks.get(
              localConversationId: item.entityId,
              ownerUserId: currentUserId,
            ) !=
            null;
      case SyncOperation.readReceiptUpsert:
        final message = await repositories.messages.getMessage(item.entityId);
        if (message?.readAt == null || message?.conversationId == null) {
          return false;
        }
        return await repositories.cloudLinks.get(
              localConversationId: message!.conversationId!,
              ownerUserId: currentUserId,
            ) !=
            null;
    }
  }

  Future<void> _importAndPull(String userId) async {
    if (!_isCloudReady || cloud.currentIdentity?.userId != userId) return;
    final remoteConversations = await cloud.listMyDirectConversations();
    var links = await repositories.cloudLinks.listForOwner(userId);
    for (final remote in remoteConversations) {
      if (remote.id.isEmpty ||
          remote.participantId.isEmpty ||
          remote.participantId == userId) {
        throw const CloudException(
          'ข้อมูลสมาชิกบทสนทนาไม่ถูกต้อง',
          code: 'invalidLocalData',
        );
      }
      final existing = links.where(
        (link) => link.cloudConversationId == remote.id,
      );
      if (existing.isNotEmpty) continue;
      final localConversation = await repositories.conversations
          .ensureConversation(
            id: remote.id,
            participantId: remote.participantId,
            displayName: remote.displayName.isEmpty
                ? 'ผู้ใช้ RELIO'
                : remote.displayName,
            participantStatus: DeviceStatus.offline,
          );
      final link = CloudConversationBinding(
        localConversationId: localConversation.id,
        cloudConversationId: remote.id,
        ownerUserId: userId,
        peerUserId: remote.participantId,
      );
      await repositories.cloudLinks.save(link);
      links = [...links, link];
    }

    for (var link in links) {
      if (!_isCloudReady || cloud.currentIdentity?.userId != userId) return;
      while (true) {
        final page = await cloud.fetchMessagesPage(
          conversationId: link.cloudConversationId,
          cursor: link.messageCursor,
        );
        if (page.messages.isEmpty) break;
        for (final remote in page.messages) {
          if (remote.conversationId != link.cloudConversationId ||
              (remote.senderId != userId &&
                  remote.senderId != link.peerUserId)) {
            throw const CloudException(
              'ข้อความ Cloud ไม่ตรงกับสมาชิกที่อนุญาต',
              code: 'permissionDenied',
            );
          }
          if (remote.messageType == 'text' &&
              remote.content != null &&
              remote.content!.length <= 10000) {
            final inserted = await repositories.messages.mergeCloudText(
              conversationId: link.localConversationId,
              messageId: remote.id,
              senderUserId: remote.senderId,
              senderDeviceId: remote.senderDeviceId,
              text: remote.content!,
              createdAt: remote.createdAt,
              updatedAt: remote.updatedAt,
              currentUserId: userId,
            );
            if (inserted && remote.senderId != userId) {
              await _notifyCloudMessage(link, remote);
            }
          }
          final cursor = CloudMessageCursor(
            createdAt: remote.createdAt,
            id: remote.id,
          );
          await repositories.cloudLinks.updateMessageCursor(link, cursor);
          link = CloudConversationBinding(
            localConversationId: link.localConversationId,
            cloudConversationId: link.cloudConversationId,
            ownerUserId: link.ownerUserId,
            peerUserId: link.peerUserId,
            messageCursor: cursor,
            receiptCursorAt: link.receiptCursorAt,
            receiptCursorMessageId: link.receiptCursorMessageId,
            receiptCursorReaderId: link.receiptCursorReaderId,
          );
        }
        if (!page.hasMore) break;
      }

      while (true) {
        final receipts = await cloud.fetchReadReceipts(
          conversationId: link.cloudConversationId,
          afterReadAt: link.receiptCursorAt,
          afterMessageId: link.receiptCursorMessageId,
          afterReaderId: link.receiptCursorReaderId,
        );
        if (receipts.isEmpty) break;
        for (final receipt in receipts) {
          if (receipt.readerId != userId &&
              receipt.readerId != link.peerUserId) {
            throw const CloudException(
              'ใบตอบรับมาจากบัญชีที่ไม่ได้เป็นสมาชิก',
              code: 'permissionDenied',
            );
          }
          if (receipt.readerId == link.peerUserId) {
            await repositories.messages.mergeCloudReadReceipt(
              messageId: receipt.messageId,
              readAt: receipt.readAt,
            );
          }
          await repositories.cloudLinks.updateReceiptCursor(link, receipt);
          link = CloudConversationBinding(
            localConversationId: link.localConversationId,
            cloudConversationId: link.cloudConversationId,
            ownerUserId: link.ownerUserId,
            peerUserId: link.peerUserId,
            messageCursor: link.messageCursor,
            receiptCursorAt: receipt.readAt,
            receiptCursorMessageId: receipt.messageId,
            receiptCursorReaderId: receipt.readerId,
          );
        }
        if (receipts.length < 100) break;
      }
    }
  }

  Future<void> _notifyCloudMessage(
    CloudConversationBinding link,
    CloudMessageDto message,
  ) async {
    if (isConversationActive?.call(link.localConversationId) ?? false) {
      final ids = await repositories.messages.markConversationRead(
        link.localConversationId,
      );
      await queueReadReceipts(
        localConversationId: link.localConversationId,
        messageIds: ids,
      );
      return;
    }
    final notifications = localNotifications;
    if (notifications == null ||
        !await repositories.settings.getBool(
          'notifications_enabled',
          defaultValue: true,
        ) ||
        !await notifications.notificationsAllowed) {
      return;
    }
    final showPreview = await repositories.settings.getBool(
      'notification_preview',
      defaultValue: false,
    );
    await notifications.show(
      id: message.id,
      title:
          (await repositories.conversations.getConversation(
            link.localConversationId,
          ))?.displayName ??
          'ข้อความใหม่',
      body: notificationPreviewBody(
        enabled: showPreview,
        content: message.content,
        fallback: 'คุณมีข้อความใหม่',
      ),
      route: '/chat/${link.localConversationId}',
      urgent: false,
    );
  }

  Future<void> _process(RelioQueueItem item, String userId) async {
    if (cloud.currentIdentity?.userId != userId || !_isCloudReady) {
      throw const SyncOwnershipException('waiting_for_ownership');
    }
    final operation = SyncOperation.parse(item.operation);
    if (operation == null) {
      throw const CloudException(
        'ไม่รู้จักประเภทงานซิงก์',
        code: 'unsupportedOperation',
      );
    }
    switch (operation) {
      case SyncOperation.profileUpsert:
        await cloud.upsertProfile(displayName: await identity.getDisplayName());
      case SyncOperation.conversationUpsert:
        final conversation = await repositories.conversations.getConversation(
          item.entityId,
        );
        if (conversation == null) {
          throw const CloudException(
            'ไม่พบบทสนทนาในเครื่อง',
            code: 'invalidLocalData',
          );
        }
        final link = await repositories.cloudLinks.get(
          localConversationId: conversation.id,
          ownerUserId: userId,
        );
        if (link == null) {
          throw const CloudException(
            'บทสนทนายังไม่ได้เชื่อมกับบัญชี Cloud ของคู่สนทนา',
            code: 'unlinkedConversation',
          );
        }
        if (await cloud.fetchConversation(link.cloudConversationId) == null) {
          throw const CloudException(
            'ไม่พบบทสนทนา Cloud ที่เชื่อมไว้',
            code: 'notFound',
          );
        }
      case SyncOperation.messageUpsert:
        final message = await repositories.messages.getMessage(item.entityId);
        if (message == null) {
          throw const CloudException(
            'ไม่พบข้อความในเครื่อง',
            code: 'invalidLocalData',
          );
        }
        final link = message.conversationId == null
            ? null
            : await repositories.cloudLinks.get(
                localConversationId: message.conversationId!,
                ownerUserId: userId,
              );
        if (link == null || message.type.name != 'text') {
          throw const CloudException(
            'ข้อความยังไม่มีช่องทาง Cloud ที่อนุมัติ',
            code: 'unlinkedConversation',
          );
        }
        await cloud.upsertMessage(
          CloudMessageDto(
            id: message.id,
            conversationId: link.cloudConversationId,
            // Supabase RLS binds outgoing messages to auth.uid. Local
            // prototype/device sender labels are not Cloud ownership IDs.
            senderId: userId,
            senderDeviceId: message.senderDeviceId ?? '',
            messageType: message.type.name,
            content: message.text,
            createdAt: message.createdAt ?? clock.now(),
            updatedAt: message.createdAt ?? clock.now(),
            deliveryStatus: message.status?.name ?? 'pending',
            isOutgoing: message.outgoing,
          ),
        );
      case SyncOperation.sosUpsert:
        final sos = await repositories.sos.getById(item.entityId);
        if (sos == null) {
          throw const CloudException(
            'ไม่พบ SOS ในเครื่อง',
            code: 'invalidLocalData',
          );
        }
        await cloud.upsertSos(
          CloudSosDto(
            id: sos.id,
            ownerDeviceId: sos.ownerDeviceId,
            message: sos.message,
            latitude: sos.latitude,
            longitude: sos.longitude,
            createdAt: sos.createdAt,
            isActive: sos.isActive,
          ),
        );
      case SyncOperation.attachmentMetadataUpsert:
        final attachment = await repositories.attachments.getById(
          item.entityId,
        );
        if (attachment == null) {
          throw const CloudException(
            'ไม่พบไฟล์แนบในเครื่อง',
            code: 'invalidLocalData',
          );
        }
        await cloud.upsertAttachment(_attachmentDto(attachment, userId));
      case SyncOperation.attachmentUpload:
        final attachment = await repositories.attachments.getById(
          item.entityId,
        );
        if (attachment == null) {
          throw const CloudException(
            'ไม่พบไฟล์แนบในเครื่อง',
            code: 'invalidLocalData',
          );
        }
        if (!await mediaStorage.isManagedFile(attachment.localPath)) {
          throw const CloudException(
            'ไม่พบไฟล์สื่อในเครื่อง',
            code: 'missingLocalFile',
          );
        }
        await cloud.uploadAttachment(
          localPath: attachment.localPath,
          storagePath: _storagePath(attachment, userId),
        );
      case SyncOperation.readReceiptUpsert:
        final message = await repositories.messages.getMessage(item.entityId);
        if (message?.readAt == null || message?.conversationId == null) {
          throw const CloudException(
            'ไม่พบเวลาอ่านของข้อความ',
            code: 'invalidLocalData',
          );
        }
        final link = await repositories.cloudLinks.get(
          localConversationId: message!.conversationId!,
          ownerUserId: userId,
        );
        if (link == null) {
          throw const CloudException(
            'บทสนทนายังไม่ได้เชื่อม Cloud',
            code: 'unlinkedConversation',
          );
        }
        await cloud.upsertReadReceipt(
          CloudReadReceipt(
            messageId: message.id,
            readerId: userId,
            readAt: message.readAt!,
          ),
        );
    }
  }

  CloudAttachmentDto _attachmentDto(
    RelioMediaAttachment attachment,
    String userId,
  ) => CloudAttachmentDto(
    id: attachment.id,
    messageId: attachment.messageId,
    storagePath: _storagePath(attachment, userId),
    mediaType: attachment.mediaType.name,
    mimeType: attachment.mimeType,
    fileName: attachment.fileName,
    byteSize: attachment.byteSize,
    transferStatus: attachment.transferStatus.name,
  );

  String _storagePath(RelioMediaAttachment attachment, String userId) =>
      CloudStoragePathPolicy.forAttachment(
        userId: userId,
        messageId: attachment.messageId,
        attachmentId: attachment.id,
        fileName: attachment.fileName,
      );

  Future<void> _markLocalSuccess(RelioQueueItem item) async {
    switch (SyncOperation.parse(item.operation)) {
      case SyncOperation.messageUpsert:
        await repositories.messages.updateCloudSyncStatus(
          item.entityId,
          CloudSyncStatus.synced.value,
        );
      case SyncOperation.attachmentMetadataUpsert:
        await repositories.attachments.updateCloudMetadataStatus(
          item.entityId,
          CloudSyncStatus.synced.value,
        );
      case SyncOperation.attachmentUpload:
        await repositories.attachments.updateCloudFileStatus(
          item.entityId,
          CloudSyncStatus.synced.value,
        );
      case SyncOperation.profileUpsert ||
          SyncOperation.conversationUpsert ||
          SyncOperation.sosUpsert ||
          null:
        break;
      case SyncOperation.readReceiptUpsert:
        break;
    }
  }

  Future<void> _markLocalSyncing(RelioQueueItem item) async {
    switch (SyncOperation.parse(item.operation)) {
      case SyncOperation.messageUpsert:
        await repositories.messages.updateCloudSyncStatus(
          item.entityId,
          CloudSyncStatus.syncing.value,
        );
      case SyncOperation.attachmentMetadataUpsert:
        await repositories.attachments.updateCloudMetadataStatus(
          item.entityId,
          CloudSyncStatus.syncing.value,
        );
      case SyncOperation.attachmentUpload:
        await repositories.attachments.updateCloudFileStatus(
          item.entityId,
          CloudSyncStatus.syncing.value,
        );
      case SyncOperation.profileUpsert ||
          SyncOperation.conversationUpsert ||
          SyncOperation.sosUpsert ||
          null:
        break;
      case SyncOperation.readReceiptUpsert:
        break;
    }
  }

  Future<void> _markLocalFailure(RelioQueueItem item) async {
    switch (SyncOperation.parse(item.operation)) {
      case SyncOperation.messageUpsert:
        await repositories.messages.updateCloudSyncStatus(
          item.entityId,
          CloudSyncStatus.failed.value,
        );
      case SyncOperation.attachmentMetadataUpsert:
        await repositories.attachments.updateCloudMetadataStatus(
          item.entityId,
          CloudSyncStatus.failed.value,
        );
      case SyncOperation.attachmentUpload:
        await repositories.attachments.updateCloudFileStatus(
          item.entityId,
          CloudSyncStatus.failed.value,
        );
      case SyncOperation.profileUpsert ||
          SyncOperation.conversationUpsert ||
          SyncOperation.sosUpsert ||
          null:
        break;
      case SyncOperation.readReceiptUpsert:
        break;
    }
  }

  Future<void> _handleFailure(RelioQueueItem item, Object error) async {
    // Keep queue diagnostics safe: backend text must not echo SOS coordinates,
    // message content, tokens, or other sensitive payload details.
    final message = error is CloudException ? error.code : 'local_sync_error';
    final permanent =
        _isPermanent(error) || item.attemptCount >= retryPolicy.maxAttempts;
    if (permanent) {
      await repositories.syncQueue.markFailed(item.id, message);
      await _markLocalFailure(item);
    } else {
      final next = clock.now().add(
        retryPolicy.delayForAttempt(item.attemptCount),
      );
      _queueRetryTimer?.cancel();
      _queueRetryTimer = Timer(next.difference(clock.now()), () {
        if (!_disposed && _isCloudReady) unawaited(run());
      });
      await repositories.syncQueue.markRetryable(
        item.id,
        error: message,
        nextAttemptAt: next,
      );
    }
    await _emit(
      state: SyncEngineState.running,
      currentItem: null,
      lastFailureAt: clock.now(),
      lastError: message,
      nextRetryAt: permanent
          ? null
          : clock.now().add(retryPolicy.delayForAttempt(item.attemptCount)),
    );
  }

  void _schedulePullRetry() {
    _pullRetryTimer?.cancel();
    final delay = Duration(seconds: 15 + (5 * _pullRetryCount.clamp(0, 9)));
    _pullRetryCount++;
    _pullRetryTimer = Timer(delay, () {
      if (!_disposed && _isCloudReady) unawaited(run());
    });
  }

  bool _isPermanent(Object error) {
    if (error is! CloudException) return true;
    return const {
      'notConfigured',
      'signedOut',
      'auth',
      'permissionDenied',
      'invalidPath',
      'invalidLocalData',
      'missingLocalFile',
      'unsupportedOperation',
      'notFound',
    }.contains(error.code);
  }

  bool get _isCloudReady =>
      cloud.cloudState == CloudState.ready &&
      cloud.authState == AuthState.authenticated &&
      cloud.currentIdentity != null;

  void _scheduleRun() {
    if (!_started || _disposed || _runOperation != null) return;
    unawaited(run());
  }

  Future<void> _setWaitingForCloud() async {
    await _refreshSnapshot(state: SyncEngineState.waitingForCloud);
  }

  Future<void> _refreshSnapshot({SyncEngineState? state}) async {
    final rows = await repositories.syncQueue.listAll();
    final summary = _summary(rows);
    final nextRetry = rows
        .where(
          (item) =>
              item.status == SyncQueueStatus.pending.value &&
              item.nextAttemptAt != null,
        )
        .map((item) => item.nextAttemptAt!)
        .fold<DateTime?>(null, (current, value) {
          if (current == null || value.isBefore(current)) return value;
          return current;
        });
    await _emit(
      state: state ?? _snapshot.state,
      queueSummary: summary,
      nextRetryAt: nextRetry,
    );
  }

  SyncQueueSummary _summary(List<RelioQueueItem> rows) {
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

  Future<void> _emit({
    required SyncEngineState state,
    RelioQueueItem? currentItem,
    SyncQueueSummary? queueSummary,
    DateTime? lastSuccessAt,
    DateTime? lastFailureAt,
    String? lastError,
    DateTime? nextRetryAt,
  }) async {
    _snapshot = SyncEngineSnapshot(
      state: state,
      cloudState: cloud.cloudState,
      authState: cloud.authState,
      queueSummary: queueSummary ?? _snapshot.queueSummary,
      currentItem: currentItem,
      lastSuccessAt: lastSuccessAt ?? _snapshot.lastSuccessAt,
      lastFailureAt: lastFailureAt ?? _snapshot.lastFailureAt,
      lastError: lastError,
      nextRetryAt: nextRetryAt ?? _snapshot.nextRetryAt,
    );
    if (!_disposed) _stateController.add(_snapshot);
  }

  Future<void> dispose() async {
    _disposed = true;
    _queueRetryTimer?.cancel();
    _pullRetryTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _stateController.close();
  }
}
