import 'dart:async';

import '../cloud/cloud_data_source.dart';
import '../cloud/cloud_models.dart';
import '../domain/relio_entities.dart';
import '../media/media_storage_service.dart';
import '../repositories/local_repositories.dart';
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
    SyncClock? clock,
    SyncRetryPolicy? retryPolicy,
    this.staleProcessingAge = const Duration(minutes: 10),
  }) : clock = clock ?? const SystemSyncClock(),
       retryPolicy = retryPolicy ?? const SyncRetryPolicy();

  final RelioRepositories repositories;
  final CloudDataSource cloud;
  final RelioDeviceIdentityRepository identity;
  final MediaStorageService mediaStorage;
  final SyncClock clock;
  final SyncRetryPolicy retryPolicy;
  final Duration staleProcessingAge;

  final _stateController = StreamController<SyncEngineSnapshot>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  SyncEngineSnapshot _snapshot = const SyncEngineSnapshot.initial();
  Future<void>? _runOperation;
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
    await run();
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
    }

    await _emit(
      state: SyncEngineState.running,
      currentItem: null,
      lastError: null,
    );
    var hadFailure = false;
    var hadOwnershipBlock = false;
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
      case SyncOperation.profileUpsert ||
          SyncOperation.conversationUpsert ||
          SyncOperation.sosUpsert ||
          null:
        return true;
    }
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
        await cloud.upsertConversation(
          CloudConversationDto(
            id: conversation.id,
            participantId: conversation.participantId,
            displayName: conversation.displayName,
            updatedAt: conversation.updatedAt,
          ),
        );
      case SyncOperation.messageUpsert:
        final message = await repositories.messages.getMessage(item.entityId);
        if (message == null) {
          throw const CloudException(
            'ไม่พบข้อความในเครื่อง',
            code: 'invalidLocalData',
          );
        }
        await cloud.upsertMessage(
          CloudMessageDto(
            id: message.id,
            conversationId: message.conversationId ?? '',
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
        if (!await mediaStorage.fileExists(attachment.localPath)) {
          throw const CloudException(
            'ไม่พบไฟล์สื่อในเครื่อง',
            code: 'missingLocalFile',
          );
        }
        await cloud.uploadAttachment(
          localPath: attachment.localPath,
          storagePath: _storagePath(attachment, userId),
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

  String _storagePath(RelioMediaAttachment attachment, String userId) {
    final safeName = attachment.fileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    return 'users/$userId/messages/${attachment.messageId}/${attachment.id}-$safeName';
  }

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
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _stateController.close();
  }
}
