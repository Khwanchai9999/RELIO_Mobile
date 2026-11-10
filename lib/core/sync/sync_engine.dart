import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import '../identity/owner_context.dart';

import '../diagnostics/diagnostics_log_service.dart';
import '../cloud/cloud_data_source.dart';
import '../cloud/cloud_models.dart';
import '../cloud/cloud_storage_policy.dart';
import '../connectivity/qa_internet_simulator.dart';
import '../database/app_database.dart';
import '../domain/relio_entities.dart';
import '../media/media_storage_service.dart';
import '../notifications/local_notification_service.dart';
import '../notifications/notification_preview.dart';
import '../repositories/local_repositories.dart';
import '../../data/models/prototype_models.dart'
    show DeliveryStatus, DeviceStatus, MessageType;
import '../../data/mock_data.dart';
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
  waitingForBinding,
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

// ประมวลผลคิว Cloud ที่บันทึกใน SQLite พร้อมตรวจ session และ owner ก่อนส่ง
// งาน offline จะคงอยู่ในเครื่อง ส่วน retry และ pull/merge ทำผ่าน repository ที่กำหนดไว้
class SyncEngine {
  SyncEngine({
    required this.repositories,
    required this.cloud,
    required this.identity,
    required this.mediaStorage,
    this.localNotifications,
    this.diagnostics,
    this.isConversationActive,
    this.isGuestBackupSession,
    this.privateBackupEnabled,
    QaInternetSimulator? internetSimulator,
    SyncClock? clock,
    SyncRetryPolicy? retryPolicy,
    this.staleProcessingAge = const Duration(minutes: 10),
  }) : clock = clock ?? const SystemSyncClock(),
       retryPolicy = retryPolicy ?? const SyncRetryPolicy(),
       _internetSimulator = internetSimulator ?? QaInternetSimulator();

  final RelioRepositories repositories;
  final CloudDataSource cloud;
  final RelioDeviceIdentityRepository identity;
  final MediaStorageService mediaStorage;
  final LocalNotificationSink? localNotifications;
  final DiagnosticsLogService? diagnostics;
  final bool Function(String conversationId)? isConversationActive;
  final bool Function()? isGuestBackupSession;
  final Future<bool> Function({required bool guestMode})? privateBackupEnabled;
  final SyncClock clock;
  final SyncRetryPolicy retryPolicy;
  final QaInternetSimulator _internetSimulator;
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
  bool _runAgainForOwner = false;
  bool _runAgain = false;

  SyncEngineSnapshot get snapshot => _snapshot;

  Stream<SyncEngineSnapshot> watchState() => _stateController.stream;

  Future<void> initialize() async {
    if (_started) return;
    await repositories.syncQueue.recoverStaleProcessing(
      clock.now().subtract(staleProcessingAge),
    );
    _started = true;
    _internetSimulator.addListener(_onInternetSimulatorChanged);
    _subscriptions.add(cloud.watchCloudState().listen((_) => _scheduleRun()));
    _subscriptions.add(cloud.watchAuthState().listen((_) => _scheduleRun()));
    _subscriptions.add(
      repositories.syncQueue.watchSummary().listen((_) => _scheduleRun()),
    );
    await _refreshSnapshot();
  }

  Future<void> run({bool adoptUnownedItems = false}) {
    final active = _runOperation;
    if (active != null) {
      _runAgain = true;
      return active;
    }
    final operation = _run(adoptUnownedItems: adoptUnownedItems);
    late final Future<void> drained;
    drained = operation
        .whenComplete(() {
          _runOperation = null;
        })
        .then((_) async {
          final rerun = _runAgain || _runAgainForOwner;
          _runAgain = false;
          _runAgainForOwner = false;
          if (rerun && _started && !_disposed) await run();
        });
    _runOperation = drained;
    return drained;
  }

  Future<void> retryFailed(String id) async {
    await repositories.syncQueue.retry(id);
    await run();
  }

  Future<int> restorePrivateBackup() async {
    final identity = cloud.currentIdentity;
    if (!_isCloudReady || identity == null) {
      throw const CloudException(
        'กรุณาเข้าสู่ระบบและเชื่อมต่ออินเทอร์เน็ต',
        code: 'signedOut',
      );
    }
    final epoch = repositories.ownerContext.capture();
    final guestMode = isGuestBackupSession?.call() ?? false;
    if (guestMode ? epoch.userId != null : epoch.userId != identity.userId) {
      throw const CloudException(
        'บัญชีในเครื่องไม่ตรงกับ Cloud',
        code: 'permissionDenied',
      );
    }
    String? cursor;
    final conversations = <String, Map<String, dynamic>>{};
    do {
      final page = await cloud.fetchPrivateBackupRecords(
        recordType: 'conversation',
        afterSourceId: cursor,
        limit: 100,
      );
      repositories.ownerContext.requireCurrent(epoch);
      for (final record in page) {
        conversations[record.sourceId] = record.payload;
        cursor = record.sourceId;
      }
      if (page.length < 100) break;
    } while (true);
    for (final entry in conversations.entries) {
      final payload = entry.value;
      final peerDeviceId = payload['peerDeviceId'];
      final displayName = payload['displayName'];
      if (peerDeviceId is! String ||
          peerDeviceId.isEmpty ||
          displayName is! String) {
        continue;
      }
      final remotePrincipal =
          payload['remotePrincipal'] as String? ??
          'restored-device:$peerDeviceId';
      await repositories.conversations.ensureConversation(
        id: entry.key,
        participantId: peerDeviceId,
        displayName: displayName,
        participantStatus: DeviceStatus.normal,
        remotePrincipalId: remotePrincipal,
      );
      repositories.ownerContext.requireCurrent(epoch);
    }
    cursor = null;
    var restored = 0;
    do {
      final page = await cloud.fetchPrivateBackupRecords(
        recordType: 'message',
        afterSourceId: cursor,
        limit: 100,
      );
      repositories.ownerContext.requireCurrent(epoch);
      for (final record in page) {
        cursor = record.sourceId;
        final payload = record.payload;
        final sourceConversation = payload['localConversationId'];
        final conversationPayload = sourceConversation is String
            ? conversations[sourceConversation]
            : null;
        if (conversationPayload == null) continue;
        final localConversation = await repositories.conversations
            .ensureConversation(
              id: sourceConversation as String,
              participantId: conversationPayload['peerDeviceId'] as String,
              displayName:
                  conversationPayload['displayName'] as String? ??
                  'อุปกรณ์ RELIO',
              participantStatus: DeviceStatus.normal,
              remotePrincipalId:
                  conversationPayload['remotePrincipal'] as String?,
            );
        final typeName = payload['messageType'];
        final type = MessageType.values
            .where((value) => value.name == typeName)
            .firstOrNull;
        final sender = payload['senderIdentity'];
        final created = DateTime.tryParse(
          payload['createdAt'] as String? ?? '',
        );
        if (type == null || created == null || sender is! String) continue;
        String? localPath;
        final attachmentList = payload['attachments'];
        if (attachmentList is List && attachmentList.isNotEmpty) {
          final meta = Map<String, dynamic>.from(attachmentList.first as Map);
          final attachmentId = meta['id'] as String;
          final fileName = meta['fileName'] as String;
          final mimeType = meta['mimeType'] as String;
          final byteSize = meta['byteSize'] as int;
          final storagePath = meta['storagePath'] as String;
          final digest = meta['sha256'] as String?;
          final existingAttachment = await repositories.attachments.getById(
            attachmentId,
          );
          var existingIsValid = false;
          if (existingAttachment != null) {
            if (existingAttachment.messageId !=
                    (payload['localMessageId'] as String? ?? record.sourceId) ||
                existingAttachment.byteSize != byteSize ||
                existingAttachment.mimeType != mimeType) {
              throw const CloudException(
                'ไฟล์แนบในเครื่องขัดแย้งกับข้อมูลสำรอง',
                code: 'invalidLocalData',
              );
            }
            if (await mediaStorage.isManagedFile(
              existingAttachment.localPath,
            )) {
              final validation = await mediaStorage.validateFile(
                existingAttachment.localPath,
              );
              existingIsValid =
                  validation.mimeType == mimeType &&
                  validation.byteSize == byteSize &&
                  (digest == null ||
                      await mediaStorage.sha256ForFile(
                            existingAttachment.localPath,
                          ) ==
                          digest);
              if (existingIsValid) localPath = existingAttachment.localPath;
            }
          }
          if (!existingIsValid) {
            localPath = await cloud.downloadAttachment(
              storagePath: storagePath,
              ownerUserId: identity.userId,
              mediaStorage: mediaStorage,
              fileName: fileName,
              mimeType: mimeType,
              expectedByteSize: byteSize,
              expectedSha256: digest,
            );
          }
          repositories.ownerContext.requireCurrent(epoch);
        }
        final messageId =
            payload['localMessageId'] as String? ?? record.sourceId;
        final content = payload['content'] as String? ?? '';
        final outgoing = payload['isOutgoing'] as bool? ?? false;
        final delivery = DeliveryStatus.values.firstWhere(
          (value) => value.name == payload['deliveryStatus'],
          orElse: () => DeliveryStatus.pending,
        );
        final before = await repositories.messages.getMessage(messageId);
        await repositories.messages.restorePrivateBackupMessage(
          conversationId: localConversation.id,
          messageId: messageId,
          senderId: sender,
          senderDeviceId: payload['senderDeviceId'] as String? ?? '',
          messageType: type,
          content: content,
          createdAt: created,
          deliveryStatus: delivery,
          isOutgoing: outgoing,
          localFilePath: localPath,
          readAt: DateTime.tryParse(payload['readAt'] as String? ?? ''),
        );
        if (attachmentList is List && attachmentList.isNotEmpty) {
          final meta = Map<String, dynamic>.from(attachmentList.first as Map);
          final attachmentId = meta['id'] as String;
          if (await repositories.attachments.getById(attachmentId) == null &&
              localPath != null) {
            await repositories.attachments.createPending(
              id: attachmentId,
              conversationId: localConversation.id,
              messageId: messageId,
              transferId: meta['transferId'] as String? ?? attachmentId,
              mediaType: meta['mediaType'] == 'video'
                  ? MediaType.video
                  : MediaType.image,
              fileName: meta['fileName'] as String,
              mimeType: meta['mimeType'] as String,
              localPath: localPath,
              byteSize: meta['byteSize'] as int,
              remoteFileName: meta['storagePath'] as String,
              checksumSha256: meta['sha256'] as String?,
            );
            await repositories.attachments.markCompleted(
              attachmentId,
              localPath: localPath,
            );
          } else if (localPath != null) {
            final prior = await repositories.attachments.getById(attachmentId);
            if (prior != null && prior.localPath != localPath) {
              await repositories.messages.updateCloudMediaPath(
                messageId,
                localPath,
              );
              await repositories.attachments.markCompleted(
                attachmentId,
                localPath: localPath,
              );
            }
          }
        }
        if (before == null) restored++;
        repositories.ownerContext.requireCurrent(epoch);
      }
      if (page.length < 100) break;
    } while (true);
    return restored;
  }

  Future<void> adoptGuestItemsAndRun() async {
    final currentIdentity = cloud.currentIdentity;
    if ((isGuestBackupSession?.call() ?? false) ||
        currentIdentity?.isAnonymous == true) {
      throw const CloudException(
        'ข้อมูล Guest จะยังอยู่ในเครื่องจนกว่าจะเข้าสู่ระบบบัญชีสมาชิก',
        code: 'permissionDenied',
      );
    }
    if (currentIdentity == null || cloud.authState != AuthState.authenticated) {
      await _setWaitingForCloud();
      return;
    }
    await _adoptGuestItems(currentIdentity.userId);
    await run();
  }

  Future<void> _adoptGuestItems(String userId) => repositories.ownerContext.run(
    () => repositories.database.transaction(() async {
      final owner = repositories.ownerContext.capture();
      await repositories.conversations.adoptUnowned(userId);
      await repositories.syncQueue.adoptUnowned(userId);
      repositories.ownerContext.requireCurrent(owner);
    }),
  );

  Future<CloudConversationBinding> linkConversationToCloud({
    required String localConversationId,
    required String peerUserId,
  }) async {
    final epoch = repositories.ownerContext.capture();
    final owner = cloud.currentIdentity;
    if (!_isCloudReady ||
        owner == null ||
        (isGuestBackupSession?.call() ?? false) ||
        owner.isAnonymous) {
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
    repositories.ownerContext.requireCurrent(epoch);
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
        (isGuestBackupSession?.call() ?? false) ||
        owner == null) {
      return;
    }
    for (final id in messageIds) {
      final message = await repositories.messages.getMessage(id);
      final sourceId = message?.conversationId;
      if (message == null ||
          message.outgoing ||
          message.readAt == null ||
          sourceId == null ||
          !await repositories.database.sameLogicalConversation(
            sourceId,
            localConversationId,
          ) ||
          await repositories.cloudLinks.get(
                localConversationId: sourceId,
                ownerUserId: owner.userId,
              ) ==
              null) {
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
    try {
      await repositories.ownerContext.run(
        () => _runOwned(adoptUnownedItems: adoptUnownedItems),
      );
    } on OwnerChangedException {
      _runAgainForOwner = true;
      _pullRetryTimer?.cancel();
      _pullRetryTimer = null;
      await _setWaitingForCloud();
    }
  }

  // ตรวจ Cloud session และขอบเขต owner ก่อนประมวลผล โดยยังเคารพการยินยอมสำรองข้อมูล
  Future<void> _runOwned({required bool adoptUnownedItems}) async {
    if (_disposed) return;
    if (!_internetSimulator.internetAvailable || !_isCloudReady) {
      await _setWaitingForCloud();
      return;
    }
    final currentIdentity = cloud.currentIdentity!;
    final guestMode = isGuestBackupSession?.call() ?? false;
    final owner = repositories.ownerContext.capture();
    if ((currentIdentity.isAnonymous && !guestMode) ||
        (guestMode && owner.userId != null) ||
        (!guestMode && owner.userId != currentIdentity.userId)) {
      await _emit(state: SyncEngineState.waitingForOwnership);
      return;
    }
    final backupEnabled = await _privateBackupIsEnabled(guestMode: guestMode);
    if (adoptUnownedItems) {
      if (guestMode) {
        throw const CloudException(
          'Guest ไม่สามารถนำข้อมูลไปผูกบัญชีโดยอัตโนมัติได้',
          code: 'permissionDenied',
        );
      }
      await _adoptGuestItems(currentIdentity.userId);
    }

    if (backupEnabled) {
      await _enqueuePrivateBackupBackfill(
        currentIdentity.userId,
        guestMode: guestMode,
      );
    }

    await _emit(
      state: SyncEngineState.running,
      currentItem: null,
      lastError: null,
    );
    var hadFailure = false;
    var hadOwnershipBlock = false;
    var hadBindingBlock = false;
    if (!guestMode) {
      try {
        await _importAndPull(currentIdentity.userId);
        _pullRetryCount = 0;
        _pullRetryTimer?.cancel();
        _pullRetryTimer = null;
      } on OwnerChangedException {
        rethrow;
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
      await _reconcileCloudMediaDownloads(currentIdentity.userId);
    }
    while (!_disposed) {
      if (!_isCloudReady ||
          cloud.currentIdentity?.userId != currentIdentity.userId) {
        break;
      }
      final candidates = await repositories.syncQueue.listEligible(clock.now());
      var claimedAny = false;
      for (final candidate in candidates) {
        final operation = SyncOperation.parse(candidate.operation);
        if (guestMode && operation != SyncOperation.privateBackupUpsert) {
          continue;
        }
        if (operation == SyncOperation.privateBackupUpsert && !backupEnabled) {
          continue;
        }
        if (candidate.ownerUserId != currentIdentity.userId) {
          hadOwnershipBlock = true;
          await _recordQueueDecision(
            candidate,
            currentIdentity.userId,
            selected: false,
            reason: 'owner_mismatch',
          );
          continue;
        }
        final localPrincipal = await repositories.syncQueue
            .localPrincipalForItem(candidate.id);
        final expectedPrincipal = guestMode
            ? (await repositories.profiles.current()).principalId
            : 'account:${currentIdentity.userId}';
        if (localPrincipal != expectedPrincipal) {
          hadOwnershipBlock = true;
          await _recordQueueDecision(
            candidate,
            currentIdentity.userId,
            selected: false,
            reason: 'local_principal_mismatch',
          );
          continue;
        }
        final terminalReason = await _permanentDependencyFailure(candidate);
        if (terminalReason != null) {
          hadFailure = true;
          await repositories.syncQueue.markFailed(candidate.id, terminalReason);
          await _markLocalFailure(candidate);
          await _recordQueueDecision(
            candidate,
            currentIdentity.userId,
            selected: false,
            reason: 'terminal:$terminalReason',
          );
          continue;
        }
        if (!await _dependenciesReady(candidate, currentIdentity.userId)) {
          final reason = await _dependencySkipReason(
            candidate,
            currentIdentity.userId,
          );
          if (reason == 'conversation_binding_missing') {
            hadBindingBlock = true;
          }
          await _recordQueueDecision(
            candidate,
            currentIdentity.userId,
            selected: false,
            reason: reason,
          );
          continue;
        }
        final item = await repositories.syncQueue.claim(
          candidate.id,
          clock.now(),
        );
        if (item == null) continue;
        claimedAny = true;
        await _recordQueueDecision(
          item,
          currentIdentity.userId,
          selected: true,
          reason: 'claimed',
        );
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
          await _recordQueueDecision(
            item,
            currentIdentity.userId,
            selected: true,
            reason: 'completed',
          );
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
          final transitionedRows = (await repositories.syncQueue.listAll())
              .where((queued) => queued.id == item.id)
              .toList(growable: false);
          if (transitionedRows.isNotEmpty) {
            await _recordQueueDecision(
              transitionedRows.first,
              currentIdentity.userId,
              selected: true,
              reason: 'transition:${transitionedRows.first.status}',
            );
          }
        }
      }
      if (!claimedAny) break;
    }
    await _refreshSnapshot(
      state: hadOwnershipBlock
          ? SyncEngineState.waitingForOwnership
          : hadBindingBlock
          ? SyncEngineState.waitingForBinding
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
    switch (SyncOperation.parse(item.operation)) {
      case SyncOperation.messageUpsert:
        final message = await repositories.messages.getMessage(item.entityId);
        if (message == null) return true;
        final link = await repositories.cloudLinks.get(
          localConversationId: message.conversationId!,
          ownerUserId: currentUserId,
        );
        if (link == null) return false;
        // แถวบทสนทนาของ Guest หรือบัญชีอื่นต้องไม่ขวางข้อความที่มี owner แยกต่างหาก
        // เมื่อบัญชีปัจจุบันมี Cloud link ของตนเองแล้ว        // Old Guest or other-account conversation rows must not hold up a
        // separately owned message once this account already has its Cloud link.
        final hasOwnedIncompleteConversationWrite = all.any(
          (queued) =>
              queued.entityId == message.conversationId &&
              queued.operation == SyncOperation.conversationUpsert.value &&
              queued.ownerUserId == currentUserId &&
              queued.status != SyncQueueStatus.completed.value,
        );
        return !hasOwnedIncompleteConversationWrite;
      case SyncOperation.attachmentMetadataUpsert:
        final attachment = await repositories.attachments.getById(
          item.entityId,
        );
        if (attachment == null) return true;
        final parentMessage = await repositories.messages.getMessage(
          attachment.messageId,
        );
        final parentQueue = all.where(
          (queued) =>
              queued.entityId == attachment.messageId &&
              queued.operation == SyncOperation.messageUpsert.value,
        );
        if (parentQueue.any((queued) => queued.ownerUserId != currentUserId)) {
          return false;
        }
        return parentMessage?.cloudSyncStatus == CloudSyncStatus.synced.value ||
            completed(attachment.messageId, SyncOperation.messageUpsert.value);
      case SyncOperation.attachmentUpload:
        final attachment = await repositories.attachments.getById(
          item.entityId,
        );
        if (attachment == null) return true;
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
      case SyncOperation.attachmentDownload:
        final attachment = await repositories.attachments.getById(
          item.entityId,
        );
        if (attachment == null) return true;
        final parent = await repositories.messages.getMessage(
          attachment.messageId,
        );
        if (parent?.conversationId == null) return false;
        return await repositories.cloudLinks.get(
              localConversationId: parent!.conversationId!,
              ownerUserId: currentUserId,
            ) !=
            null;
      case SyncOperation.profileUpsert || SyncOperation.sosUpsert || null:
        return true;
      case SyncOperation.privateBackupUpsert:
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

  Future<String?> _permanentDependencyFailure(RelioQueueItem item) async {
    switch (SyncOperation.parse(item.operation)) {
      case SyncOperation.messageUpsert:
        final lookup = await repositories.messages.lookupQueuedMessage(
          item.entityId,
        );
        switch (lookup.status) {
          case QueuedMessageLookupStatus.missingMessage:
            return 'message_missing';
          case QueuedMessageLookupStatus.missingConversation:
            return 'conversation_id_missing';
          case QueuedMessageLookupStatus.conversationNotVisible:
            return 'conversation_scope_mismatch';
          case QueuedMessageLookupStatus.available:
            break;
        }
        final message = lookup.message!;
        if (message.conversationId == null ||
            message.conversationId!.trim().isEmpty) {
          return 'conversation_id_missing';
        }
        switch (message.type) {
          case MessageType.text:
            return null;
          case MessageType.image || MessageType.video:
            final attachments = await repositories.attachments.listAll();
            final attachment = attachments
                .where((row) => row.messageId == message.id)
                .firstOrNull;
            if (attachment == null) {
              return 'attachment_missing';
            }
            final queue = await repositories.syncQueue.listAll();
            for (final operation in [
              SyncOperation.attachmentMetadataUpsert,
              SyncOperation.attachmentUpload,
            ]) {
              if (!queue.any(
                (row) =>
                    row.entityId == attachment.id &&
                    row.operation == operation.value &&
                    row.ownerUserId == item.ownerUserId,
              )) {
                return 'attachment_sync_queue_missing';
              }
            }
            return null;
          case MessageType.location:
            // แถว Cloud message ไม่มีช่องพิกัด และการ merge ข้อความรองรับเฉพาะ text
            // หากส่งชนิดนี้จะทำให้รายงานสำเร็จทั้งที่ข้อมูลตำแหน่งสูญหาย            // Cloud message rows have no coordinate fields and the pull merge
            // is text-only; syncing this would falsely report a lossy success.
            return 'unsupported_location_cloud_sync';
          case MessageType.system:
            return 'unsupported_message_type_system';
        }
      case SyncOperation.attachmentMetadataUpsert:
        final attachment = await repositories.attachments.getById(
          item.entityId,
        );
        if (attachment == null) return 'attachment_missing';
        final parent = await repositories.messages.getMessage(
          attachment.messageId,
        );
        if (parent == null) return 'parent_message_missing';
        final rows = await repositories.syncQueue.listAll();
        final parentQueue = rows.where(
          (row) =>
              row.entityId == attachment.messageId &&
              row.operation == SyncOperation.messageUpsert.value,
        );
        if (parentQueue.any((row) => row.ownerUserId != item.ownerUserId)) {
          return 'parent_message_owner_mismatch';
        }
        if (parentQueue.any(
          (row) => row.status == SyncQueueStatus.failed.value,
        )) {
          return 'parent_message_sync_failed';
        }
        if (parentQueue.isEmpty &&
            parent.cloudSyncStatus != CloudSyncStatus.synced.value) {
          return 'parent_message_sync_missing';
        }
        return null;
      case SyncOperation.attachmentUpload:
        final attachment = await repositories.attachments.getById(
          item.entityId,
        );
        if (attachment == null) return 'attachment_missing';
        final rows = await repositories.syncQueue.listAll();
        final metadataRows = rows.where(
          (row) =>
              row.entityId == item.entityId &&
              row.operation == SyncOperation.attachmentMetadataUpsert.value,
        );
        if (metadataRows.any((row) => row.ownerUserId != item.ownerUserId)) {
          return 'attachment_metadata_owner_mismatch';
        }
        if (metadataRows.any(
          (row) => row.status == SyncQueueStatus.failed.value,
        )) {
          return 'attachment_metadata_failed';
        }
        if (metadataRows.isEmpty) return 'attachment_metadata_missing';
        return null;
      case SyncOperation.attachmentDownload:
        final attachment = await repositories.attachments.getById(
          item.entityId,
        );
        if (attachment == null) return 'attachment_missing';
        final parent = await repositories.messages.getMessage(
          attachment.messageId,
        );
        if (parent == null || parent.conversationId == null) {
          return 'attachment_message_missing';
        }
        if ((parent.type != MessageType.image &&
                parent.type != MessageType.video) ||
            attachment.mediaType.name != parent.type.name ||
            parent.senderId == null ||
            !CloudStoragePathPolicy.isOwnedBy(
              attachment.remoteFileName ?? '',
              parent.senderId!,
            ) ||
            attachment.byteSize <= 0 ||
            attachment.byteSize >
                mediaStorage.policy.maxFor(attachment.mediaType.name)) {
          return 'attachment_download_metadata_invalid';
        }
        final messageType = attachment.mediaType == MediaType.image
            ? MessageType.image
            : MessageType.video;
        if (!_matchesMediaMime(messageType, attachment.mimeType)) {
          return 'attachment_download_mime_invalid';
        }
        if (await repositories.cloudLinks.get(
              localConversationId: parent.conversationId!,
              ownerUserId: item.ownerUserId ?? '',
            ) ==
            null) {
          return 'attachment_conversation_unlinked';
        }
        return null;
      case SyncOperation.profileUpsert ||
          SyncOperation.conversationUpsert ||
          SyncOperation.sosUpsert ||
          SyncOperation.readReceiptUpsert ||
          null:
        return null;
      case SyncOperation.privateBackupUpsert:
        return null;
    }
  }

  Future<String> _dependencySkipReason(
    RelioQueueItem item,
    String currentUserId,
  ) async {
    if (SyncOperation.parse(item.operation) ==
            SyncOperation.conversationUpsert &&
        await repositories.cloudLinks.get(
              localConversationId: item.entityId,
              ownerUserId: currentUserId,
            ) ==
            null) {
      return 'conversation_binding_missing';
    }
    if (SyncOperation.parse(item.operation) == SyncOperation.messageUpsert) {
      final message = await repositories.messages.getMessage(item.entityId);
      if (message == null) return 'message_missing';
      if (message.type == MessageType.location) {
        return 'unsupported_location_cloud_sync';
      }
      if (message.type == MessageType.system) {
        return 'unsupported_message_type_system';
      }
      if (message.conversationId == null ||
          message.conversationId!.trim().isEmpty) {
        return 'conversation_id_missing';
      }
      final binding = await repositories.cloudLinks.get(
        localConversationId: message.conversationId!,
        ownerUserId: currentUserId,
      );
      if (binding == null) return 'conversation_binding_missing';
      final queue = await repositories.syncQueue.listAll();
      if (queue.any(
        (row) =>
            row.entityId == message.conversationId &&
            row.operation == SyncOperation.conversationUpsert.value &&
            row.ownerUserId == currentUserId &&
            row.status != SyncQueueStatus.completed.value,
      )) {
        return 'current_owner_conversation_write_incomplete';
      }
    }
    return 'dependency_not_ready';
  }

  Future<void> _recordQueueDecision(
    RelioQueueItem item,
    String currentUserId, {
    required bool selected,
    required String reason,
  }) async {
    final log = diagnostics;
    if (log == null) return;
    String? conversationId;
    CloudConversationBinding? binding;
    var dependencyPresent = false;
    if (SyncOperation.parse(item.operation) == SyncOperation.messageUpsert) {
      final message = await repositories.messages.getMessage(item.entityId);
      conversationId = message?.conversationId;
      if (conversationId != null) {
        binding = await repositories.cloudLinks.get(
          localConversationId: conversationId,
          ownerUserId: currentUserId,
        );
        final queue = await repositories.syncQueue.listAll();
        dependencyPresent = queue.any(
          (row) =>
              row.entityId == conversationId &&
              row.operation == SyncOperation.conversationUpsert.value,
        );
      }
    } else if (SyncOperation.parse(item.operation) ==
        SyncOperation.conversationUpsert) {
      conversationId = item.entityId;
      binding = await repositories.cloudLinks.get(
        localConversationId: item.entityId,
        ownerUserId: currentUserId,
      );
    }
    final ownerClass = item.ownerUserId == null || item.ownerUserId!.isEmpty
        ? 'unowned'
        : item.ownerUserId == currentUserId
        ? 'current'
        : 'foreign';
    // lastError มีเฉพาะ error code ที่ SyncEngine สร้างไว้ ไม่บันทึกข้อความ
    // จาก backend เพื่อกัน content, token หรือข้อมูลส่วนตัวหลุดเข้า diagnostics
    final failureCode = item.lastError;
    final safeFailureCode =
        failureCode != null &&
            failureCode.length <= 64 &&
            RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(failureCode)
        ? failureCode
        : null;
    final now = clock.now();
    log.record(
      'cloud_sync',
      selected ? 'sync_queue_selected' : 'sync_queue_skipped',
      operation: item.operation,
      stateTo: reason == 'claimed'
          ? 'processing'
          : reason == 'completed'
          ? 'completed'
          : reason.startsWith('terminal:')
          ? 'failed'
          : reason.startsWith('transition:')
          ? reason.substring('transition:'.length)
          : selected
          ? item.status
          : 'skipped',
      reason: reason,
      fields: {
        'itemKey': item.id.length <= 8
            ? item.id
            : item.id.substring(item.id.length - 8),
        'ownerClass': ownerClass,
        'conversationBindingPresent': binding != null,
        'dependencyPresent': dependencyPresent,
        'queueStatus': item.status,
        'ageSeconds': now.difference(item.createdAt).inSeconds,
        'entityType': item.entityType,
        'failureCode': ?safeFailureCode,
        if (conversationId != null)
          'conversationKey': conversationId.length <= 8
              ? conversationId
              : conversationId.substring(conversationId.length - 8),
      },
    );
  }

  Future<void> _importAndPull(String userId) =>
      repositories.ownerContext.run(() => _importAndPullOwned(userId));

  Future<void> _importAndPullOwned(String userId) async {
    final owner = repositories.ownerContext.capture();
    if (!_isCloudReady || cloud.currentIdentity?.userId != userId) return;
    final remoteConversations = await cloud.listMyDirectConversations();
    repositories.ownerContext.requireCurrent(owner);
    var links = await repositories.cloudLinks.listForOwner(userId);
    repositories.ownerContext.requireCurrent(owner);
    for (final remote in remoteConversations) {
      repositories.ownerContext.requireCurrent(owner);
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
            remotePrincipalId: 'account:${remote.participantId}',
            displayName: remote.displayName.isEmpty
                ? 'ผู้ใช้ RELIO'
                : remote.displayName,
            participantStatus: DeviceStatus.offline,
          );
      repositories.ownerContext.requireCurrent(owner);
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
        repositories.ownerContext.requireCurrent(owner);
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
            repositories.ownerContext.requireCurrent(owner);
            if (inserted && remote.senderId != userId) {
              await _notifyCloudMessage(link, remote);
            }
          } else if (remote.messageType == 'image' ||
              remote.messageType == 'video') {
            final displayName = _cloudMediaDisplayName(remote.content);
            final inserted = await repositories.messages.mergeCloudMediaMessage(
              conversationId: link.localConversationId,
              messageId: remote.id,
              senderUserId: remote.senderId,
              senderDeviceId: remote.senderDeviceId,
              type: remote.messageType == 'image'
                  ? MessageType.image
                  : MessageType.video,
              fileName: displayName,
              createdAt: remote.createdAt,
              updatedAt: remote.updatedAt,
              currentUserId: userId,
            );
            repositories.ownerContext.requireCurrent(owner);
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
        repositories.ownerContext.requireCurrent(owner);
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

      await _pullCloudAttachments(link, userId, owner);
    }
  }

  String _cloudMediaDisplayName(String? content) =>
      content != null && content.isNotEmpty && content.length <= 255
      ? content
      : 'ไฟล์สื่อ';

  String _cloudMediaCursorKey(String userId, String conversationId) =>
      'cloud_media_cursor:$userId:$conversationId';

  CloudAttachmentCursor? _decodeCloudAttachmentCursor(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      final id = decoded['id'] as String?;
      final createdAt = decoded['createdAt'] as String?;
      if (id == null ||
          !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) ||
          createdAt == null) {
        return null;
      }
      return CloudAttachmentCursor(
        createdAt: DateTime.parse(createdAt),
        id: id,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _pullCloudAttachments(
    CloudConversationBinding link,
    String userId,
    OwnerSnapshot owner,
  ) async {
    final cursorKey = _cloudMediaCursorKey(userId, link.cloudConversationId);
    var cursor = _decodeCloudAttachmentCursor(
      await repositories.settings.getValue(cursorKey),
    );
    repositories.ownerContext.requireCurrent(owner);

    while (_isCloudReady && cloud.currentIdentity?.userId == userId) {
      final page = await cloud.fetchConversationAttachmentsPage(
        conversationId: link.cloudConversationId,
        cursor: cursor,
        limit: 100,
      );
      repositories.ownerContext.requireCurrent(owner);
      if (page.attachments.isEmpty) break;

      for (final remoteAttachment in page.attachments) {
        repositories.ownerContext.requireCurrent(owner);
        final createdAt = remoteAttachment.createdAt;
        final storageOwner = remoteAttachment.ownerUserId;
        if (createdAt == null ||
            storageOwner == null ||
            storageOwner.isEmpty ||
            (remoteAttachment.sha256 != null &&
                !RegExp(
                  r'^[0-9a-f]{64}$',
                ).hasMatch(remoteAttachment.sha256!)) ||
            remoteAttachment.id.isEmpty ||
            remoteAttachment.byteSize <= 0 ||
            remoteAttachment.fileName.isEmpty ||
            remoteAttachment.fileName.length > 255 ||
            remoteAttachment.fileName.contains('/') ||
            remoteAttachment.fileName.contains('\\') ||
            remoteAttachment.fileName.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
            !CloudStoragePathPolicy.isOwnedBy(
              remoteAttachment.storagePath,
              storageOwner,
            )) {
          throw const CloudException(
            'metadata ไฟล์ Cloud ไม่ถูกต้อง',
            code: 'invalidLocalData',
          );
        }
        final remoteMessage = await cloud.fetchMessage(
          remoteAttachment.messageId,
        );
        repositories.ownerContext.requireCurrent(owner);
        if (remoteMessage == null ||
            remoteMessage.conversationId != link.cloudConversationId ||
            (remoteMessage.senderId != userId &&
                remoteMessage.senderId != link.peerUserId) ||
            remoteAttachment.ownerUserId != remoteMessage.senderId ||
            remoteAttachment.messageId != remoteMessage.id ||
            (remoteMessage.messageType != 'image' &&
                remoteMessage.messageType != 'video') ||
            remoteAttachment.mediaType != remoteMessage.messageType ||
            !CloudStoragePathPolicy.isOwnedBy(
              remoteAttachment.storagePath,
              remoteMessage.senderId,
            )) {
          throw const CloudException(
            'ไฟล์ Cloud ไม่ตรงกับข้อความและสมาชิกบทสนทนา',
            code: 'permissionDenied',
          );
        }
        final type = remoteMessage.messageType == 'image'
            ? MessageType.image
            : MessageType.video;
        final displayName = _cloudMediaDisplayName(remoteMessage.content);
        await repositories.messages.mergeCloudMediaMessage(
          conversationId: link.localConversationId,
          messageId: remoteMessage.id,
          senderUserId: remoteMessage.senderId,
          senderDeviceId: remoteMessage.senderDeviceId,
          type: type,
          fileName: displayName,
          createdAt: remoteMessage.createdAt,
          updatedAt: remoteMessage.updatedAt,
          currentUserId: userId,
        );
        repositories.ownerContext.requireCurrent(owner);

        final maxBytes = mediaStorage.policy.maxFor(type.name);
        if (remoteAttachment.byteSize > maxBytes ||
            !_matchesMediaMime(type, remoteAttachment.mimeType)) {
          throw const CloudException(
            'ชนิดหรือขนาดไฟล์ Cloud ไม่รองรับ',
            code: 'invalidLocalData',
          );
        }
        var local = await repositories.attachments.getById(remoteAttachment.id);
        repositories.ownerContext.requireCurrent(owner);
        if (local == null) {
          local = await repositories.attachments.createPending(
            id: remoteAttachment.id,
            conversationId: link.localConversationId,
            messageId: remoteMessage.id,
            transferId: 'cloud:${remoteAttachment.id}',
            mediaType: type == MessageType.image
                ? MediaType.image
                : MediaType.video,
            fileName: remoteAttachment.fileName,
            mimeType: remoteAttachment.mimeType,
            localPath: '',
            byteSize: remoteAttachment.byteSize,
            remoteFileName: remoteAttachment.storagePath,
            checksumSha256: remoteAttachment.sha256,
          );
          await repositories.attachments.updateCloudFileStatus(
            remoteAttachment.id,
            'downloadPending',
          );
        } else if (local.messageId != remoteMessage.id ||
            local.mediaType.name != remoteAttachment.mediaType ||
            local.fileName != remoteAttachment.fileName ||
            local.mimeType != remoteAttachment.mimeType ||
            local.byteSize != remoteAttachment.byteSize ||
            (local.checksumSha256 != null &&
                remoteAttachment.sha256 != null &&
                local.checksumSha256 != remoteAttachment.sha256) ||
            local.remoteFileName != remoteAttachment.storagePath) {
          throw const CloudException(
            'รหัสไฟล์ Cloud ซ้ำกับข้อมูลสื่อคนละรายการ',
            code: 'invalidLocalData',
          );
        }
        if (remoteAttachment.sha256 != null && local.checksumSha256 == null) {
          await repositories.attachments.updateChecksumSha256(
            remoteAttachment.id,
            remoteAttachment.sha256!,
          );
          local = (await repositories.attachments.getById(
            remoteAttachment.id,
          ))!;
        }
        repositories.ownerContext.requireCurrent(owner);

        final hasLocalFile = await mediaStorage.isManagedFile(local.localPath);
        if (!hasLocalFile &&
            local.cloudFileStatus != CloudSyncStatus.failed.value) {
          await repositories.attachments.updateCloudFileStatus(
            remoteAttachment.id,
            'downloadPending',
          );
          await _enqueueCloudAttachmentDownload(local, userId);
        }
        cursor = CloudAttachmentCursor(
          createdAt: createdAt,
          id: remoteAttachment.id,
        );
        await repositories.settings.setValue(
          cursorKey,
          jsonEncode({
            'createdAt': createdAt.toUtc().toIso8601String(),
            'id': remoteAttachment.id,
          }),
        );
        repositories.ownerContext.requireCurrent(owner);
      }
      if (!page.hasMore) break;
    }
  }

  bool _matchesMediaMime(MessageType type, String mimeType) =>
      type == MessageType.image
      ? const {'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType)
      : const {'video/mp4', 'video/quicktime'}.contains(mimeType);

  Future<void> _processCloudAttachmentDownload(
    RelioQueueItem item,
    String userId,
  ) async {
    final owner = repositories.ownerContext.capture();
    final attachment = await repositories.attachments.getById(item.entityId);
    repositories.ownerContext.requireCurrent(owner);
    if (attachment == null) {
      throw const CloudException(
        'ไม่พบไฟล์ในเครื่อง',
        code: 'invalidLocalData',
      );
    }
    final message = await repositories.messages.getMessage(
      attachment.messageId,
    );
    repositories.ownerContext.requireCurrent(owner);
    if (message == null ||
        message.conversationId == null ||
        message.senderId == null) {
      throw const CloudException(
        'ไม่พบข้อความต้นทางของไฟล์',
        code: 'invalidLocalData',
      );
    }
    final link = await repositories.cloudLinks.get(
      localConversationId: message.conversationId!,
      ownerUserId: userId,
    );
    repositories.ownerContext.requireCurrent(owner);
    if (link == null || cloud.currentIdentity?.userId != userId) {
      throw const SyncOwnershipException('waiting_for_ownership');
    }

    final remote = await cloud.fetchAttachment(attachment.id);
    repositories.ownerContext.requireCurrent(owner);
    if (remote == null ||
        remote.id != attachment.id ||
        remote.messageId != message.id ||
        remote.ownerUserId != message.senderId ||
        remote.storagePath != attachment.remoteFileName ||
        remote.mediaType != attachment.mediaType.name ||
        remote.fileName != attachment.fileName ||
        remote.mimeType != attachment.mimeType ||
        remote.byteSize != attachment.byteSize ||
        (remote.sha256 != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(remote.sha256!)) ||
        (attachment.checksumSha256 != null &&
            remote.sha256 != null &&
            attachment.checksumSha256 != remote.sha256) ||
        !CloudStoragePathPolicy.isOwnedBy(
          remote.storagePath,
          remote.ownerUserId ?? '',
        ) ||
        !_matchesMediaMime(message.type, remote.mimeType)) {
      throw const CloudException(
        'metadata ของไฟล์ไม่ตรงกับข้อความที่อนุญาต',
        code: 'permissionDenied',
      );
    }
    if (remote.ownerUserId != userId && remote.ownerUserId != link.peerUserId) {
      throw const CloudException(
        'เจ้าของไฟล์ไม่ใช่สมาชิกบทสนทนา',
        code: 'permissionDenied',
      );
    }

    Future<String?> verifiedLocalFile(String? candidate) async {
      if (candidate == null ||
          candidate.isEmpty ||
          !await mediaStorage.isManagedFile(candidate)) {
        return null;
      }
      try {
        final validation = await mediaStorage.validateFile(candidate);
        if (validation.mimeType == remote.mimeType &&
            validation.byteSize == remote.byteSize &&
            (remote.sha256 == null ||
                await mediaStorage.sha256ForFile(candidate) == remote.sha256)) {
          return candidate;
        }
      } on Object {
        // ไฟล์เก่าที่ไม่ตรงกับ metadata จะถูกแทนด้วยสำเนา Cloud ที่ตรวจแล้ว
      }
      return null;
    }

    final existingPath =
        await verifiedLocalFile(message.localFilePath) ??
        await verifiedLocalFile(attachment.localPath);
    repositories.ownerContext.requireCurrent(owner);
    final storedPath =
        existingPath ??
        await cloud.downloadAttachment(
          storagePath: remote.storagePath,
          ownerUserId: remote.ownerUserId!,
          mediaStorage: mediaStorage,
          fileName: remote.fileName,
          mimeType: remote.mimeType,
          expectedByteSize: remote.byteSize,
          expectedSha256: remote.sha256,
        );
    repositories.ownerContext.requireCurrent(owner);
    if (cloud.currentIdentity?.userId != userId) {
      throw const SyncOwnershipException('waiting_for_ownership');
    }
    await repositories.messages.updateCloudMediaPath(message.id, storedPath);
    repositories.ownerContext.requireCurrent(owner);
    final actualSha256 = await mediaStorage.sha256ForFile(storedPath);
    if (remote.sha256 != null && actualSha256 != remote.sha256) {
      throw const CloudException(
        'SHA-256 ของไฟล์ไม่ตรงกับ metadata',
        code: 'invalidLocalData',
      );
    }
    await repositories.attachments.updateChecksumSha256(
      attachment.id,
      actualSha256,
    );
    repositories.ownerContext.requireCurrent(owner);
    await repositories.attachments.markCompleted(
      attachment.id,
      localPath: storedPath,
    );
    await repositories.attachments.updateCloudFileStatus(
      attachment.id,
      CloudSyncStatus.synced.value,
    );
  }

  Future<void> _enqueueCloudAttachmentDownload(
    RelioMediaAttachment attachment,
    String userId,
  ) async {
    final queue = await repositories.syncQueue.listAll();
    final active = queue.any(
      (row) =>
          row.entityId == attachment.id &&
          row.operation == SyncOperation.attachmentDownload.value &&
          row.ownerUserId == userId &&
          row.status != SyncQueueStatus.completed.value &&
          row.status != SyncQueueStatus.failed.value,
    );
    if (active) return;
    await repositories.syncQueue.enqueue(
      entityType: SyncEntityType.attachment.value,
      entityId: attachment.id,
      operation: SyncOperation.attachmentDownload.value,
      ownerUserId: userId,
    );
  }

  Future<void> _reconcileCloudMediaDownloads(String userId) async {
    if (!_isCloudReady || cloud.currentIdentity?.userId != userId) return;
    final owner = repositories.ownerContext.capture();
    final attachments = await repositories.attachments.listAll();
    repositories.ownerContext.requireCurrent(owner);
    final queue = await repositories.syncQueue.listAll();
    repositories.ownerContext.requireCurrent(owner);
    for (final attachment in attachments) {
      final remotePath = attachment.remoteFileName;
      if (remotePath == null ||
          CloudStoragePathPolicy.ownerFor(remotePath) == null) {
        continue;
      }
      if (attachment.cloudFileStatus == CloudSyncStatus.failed.value) continue;
      final hasLocalFile = await mediaStorage.isManagedFile(
        attachment.localPath,
      );
      repositories.ownerContext.requireCurrent(owner);
      if (hasLocalFile) continue;
      await repositories.attachments.updateCloudFileStatus(
        attachment.id,
        'downloadPending',
      );
      repositories.ownerContext.requireCurrent(owner);
      final active = queue.any(
        (row) =>
            row.entityId == attachment.id &&
            row.operation == SyncOperation.attachmentDownload.value &&
            row.ownerUserId == userId &&
            row.status != SyncQueueStatus.completed.value &&
            row.status != SyncQueueStatus.failed.value,
      );
      if (!active) {
        await repositories.syncQueue.enqueue(
          entityType: SyncEntityType.attachment.value,
          entityId: attachment.id,
          operation: SyncOperation.attachmentDownload.value,
          ownerUserId: userId,
        );
        repositories.ownerContext.requireCurrent(owner);
      }
    }
  }

  Future<void> _notifyCloudMessage(
    CloudConversationBinding link,
    CloudMessageDto message,
  ) async {
    final logicalId = await repositories.database.logicalConversationId(
      link.localConversationId,
    );
    if (isConversationActive?.call(logicalId) ?? false) {
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
      defaultValue: true,
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
      soundEnabled: await repositories.settings.getBool(
        'notification_sound',
        defaultValue: true,
      ),
      vibrationEnabled: await repositories.settings.getBool(
        'notification_vibration',
        defaultValue: true,
      ),
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
        final epoch = repositories.ownerContext.capture();
        final row = await repositories.database
            .customSelect(
              'SELECT display_name FROM profile_sync_snapshots WHERE queue_id=? AND owner_user_id=?',
              variables: [
                Variable.withString(item.id),
                Variable.withString(userId),
              ],
            )
            .getSingleOrNull();
        repositories.ownerContext.requireCurrent(epoch);
        if (row == null || epoch.userId != userId) {
          throw const SyncOwnershipException('missing_profile_owner_snapshot');
        }
        final current = await repositories.profiles.forPrincipal(
          'account:$userId',
        );
        repositories.ownerContext.requireCurrent(epoch);
        if (current.displayName != row.read<String>('display_name')) return;
        await cloud.upsertProfile(
          displayName: row.read<String>('display_name'),
        );
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
        if (link == null ||
            (message.type != MessageType.text &&
                message.type != MessageType.image &&
                message.type != MessageType.video)) {
          throw const CloudException(
            'ข้อความยังไม่มีช่องทาง Cloud ที่อนุมัติ',
            code: 'unlinkedConversation',
          );
        }
        await cloud.upsertMessage(
          CloudMessageDto(
            id: message.id,
            conversationId: link.cloudConversationId,
            // Supabase RLS ผูกผู้ส่งกับ auth.uid; ชื่อ sender จาก prototype หรืออุปกรณ์
            // จึงใช้แทน Cloud owner ID ไม่ได้            // Supabase RLS binds outgoing messages to auth.uid. Local
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
        await cloud.upsertAttachment(await _attachmentDto(attachment, userId));
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
      case SyncOperation.attachmentDownload:
        await _processCloudAttachmentDownload(item, userId);
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
      case SyncOperation.privateBackupUpsert:
        await _processPrivateBackup(item, userId);
    }
  }

  Future<void> _enqueuePrivateBackupBackfill(
    String userId, {
    required bool guestMode,
  }) async {
    if (!_isCloudReady || cloud.currentIdentity?.userId != userId) return;
    final epoch = repositories.ownerContext.capture();
    if (guestMode ? epoch.userId != null : epoch.userId != userId) return;
    final principal = (await repositories.profiles.current()).principalId;
    if (principal != (guestMode ? principal : 'account:$userId') ||
        (guestMode && !(isGuestBackupSession?.call() ?? false))) {
      return;
    }
    final existing = await repositories.syncQueue.listAll();
    repositories.ownerContext.requireCurrent(epoch);
    var added = 0;
    Future<void> enqueue(String entityType, String id) async {
      var alreadyQueued = false;
      for (final row in existing) {
        if (row.entityType != entityType ||
            row.entityId != id ||
            row.operation != SyncOperation.privateBackupUpsert.value ||
            row.ownerUserId != userId) {
          continue;
        }
        if (await repositories.syncQueue.localPrincipalForItem(row.id) ==
            principal) {
          alreadyQueued = true;
          break;
        }
      }
      if (alreadyQueued || added >= 500) return;
      await repositories.syncQueue.enqueue(
        entityType: entityType,
        entityId: id,
        operation: SyncOperation.privateBackupUpsert.value,
        ownerUserId: userId,
      );
      repositories.ownerContext.requireCurrent(epoch);
      added++;
    }

    final conversations = await repositories.conversations.listConversations();
    repositories.ownerContext.requireCurrent(epoch);
    for (final conversation in conversations) {
      if (RelioMockData.isDemoId(conversation.id) ||
          RelioMockData.isDemoId(conversation.participantId)) {
        continue;
      }
      await enqueue('private_backup_conversation', conversation.id);
      final backedUpConversations = {conversation.id};
      final messages = await repositories.messages.listMessages(
        conversation.id,
      );
      repositories.ownerContext.requireCurrent(epoch);
      for (final message in messages) {
        if (message.type == MessageType.text ||
            message.type == MessageType.image ||
            message.type == MessageType.video) {
          if ((message.type == MessageType.image ||
                  message.type == MessageType.video) &&
              (message.localFilePath == null ||
                  !await mediaStorage.isManagedFile(message.localFilePath!))) {
            continue;
          }
          final sourceId = message.conversationId;
          if (sourceId != null && backedUpConversations.add(sourceId)) {
            await enqueue('private_backup_conversation', sourceId);
          }
          await enqueue('private_backup_message', message.id);
          if (added >= 500) break;
        }
      }
      if (added >= 500) break;
    }
    if (added >= 500) _runAgain = true;
  }

  Future<void> _processPrivateBackup(RelioQueueItem item, String userId) async {
    final owner = repositories.ownerContext.capture();
    final guestMode = isGuestBackupSession?.call() ?? false;
    final principal = await repositories.syncQueue.localPrincipalForItem(
      item.id,
    );
    final expectedPrincipal = guestMode
        ? (await repositories.profiles.current()).principalId
        : 'account:$userId';
    if ((guestMode ? owner.userId != null : owner.userId != userId) ||
        cloud.currentIdentity?.userId != userId ||
        principal != expectedPrincipal ||
        !await _privateBackupIsEnabled(guestMode: guestMode)) {
      throw const SyncOwnershipException('waiting_for_ownership');
    }
    if (item.entityType == 'private_backup_conversation') {
      final conversation = await repositories.conversations.getConversation(
        item.entityId,
      );
      repositories.ownerContext.requireCurrent(owner);
      if (conversation == null ||
          RelioMockData.isDemoId(conversation.id) ||
          RelioMockData.isDemoId(conversation.participantId)) {
        throw const CloudException(
          'บทสนทนาไม่เข้าเกณฑ์สำรอง',
          code: 'invalidLocalData',
        );
      }
      await cloud.upsertPrivateBackupRecord(
        CloudPrivateBackupRecord(
          recordType: 'conversation',
          sourceId: conversation.id,
          payload: {
            'localConversationId': conversation.id,
            'peerDeviceId': conversation.participantId,
            'remotePrincipal': await repositories.conversations
                .remotePrincipalForConversation(conversation.id),
            'displayName': conversation.displayName,
            'createdAt': conversation.createdAt.toUtc().toIso8601String(),
            'updatedAt': conversation.updatedAt.toUtc().toIso8601String(),
            'provenance': 'account_private_backup',
          },
        ),
      );
      repositories.ownerContext.requireCurrent(owner);
      return;
    }
    if (item.entityType != 'private_backup_message') {
      throw const CloudException(
        'ประเภทข้อมูลสำรองไม่รองรับ',
        code: 'unsupportedOperation',
      );
    }
    final message = await repositories.messages.getMessage(item.entityId);
    repositories.ownerContext.requireCurrent(owner);
    if (message == null ||
        message.conversationId == null ||
        (message.type != MessageType.text &&
            message.type != MessageType.image &&
            message.type != MessageType.video)) {
      throw const CloudException(
        'ข้อความไม่เข้าเกณฑ์สำรอง',
        code: 'invalidLocalData',
      );
    }
    final conversation = await repositories.conversations.getConversation(
      message.conversationId!,
    );
    if (conversation == null ||
        RelioMockData.isDemoId(conversation.id) ||
        RelioMockData.isDemoId(conversation.participantId)) {
      throw const CloudException(
        'บทสนทนาไม่เข้าเกณฑ์สำรอง',
        code: 'invalidLocalData',
      );
    }
    final attachments = (await repositories.attachments.listAll())
        .where((row) => row.messageId == message.id)
        .toList(growable: false);
    if ((message.type == MessageType.image ||
            message.type == MessageType.video) &&
        attachments.isEmpty) {
      throw const CloudException(
        'ไม่พบข้อมูลไฟล์แนบของข้อความสื่อ',
        code: 'invalidLocalData',
      );
    }
    final attachmentPayload = <Map<String, Object?>>[];
    for (final attachment in attachments) {
      if (!await mediaStorage.isManagedFile(attachment.localPath)) {
        throw const CloudException(
          'ไม่พบไฟล์สื่อในเครื่อง',
          code: 'missingLocalFile',
        );
      }
      final validation = await mediaStorage.validateFile(attachment.localPath);
      if (validation.mimeType != attachment.mimeType ||
          validation.byteSize != attachment.byteSize) {
        throw const CloudException(
          'ไฟล์สื่อไม่ตรงกับ metadata',
          code: 'invalidLocalData',
        );
      }
      final sha256 = await mediaStorage.sha256ForFile(attachment.localPath);
      final path = CloudStoragePathPolicy.forPrivateBackupAttachment(
        userId: userId,
        messageId: message.id,
        attachmentId: attachment.id,
        fileName: attachment.fileName,
      );
      await cloud.uploadAttachment(
        localPath: attachment.localPath,
        storagePath: path,
      );
      repositories.ownerContext.requireCurrent(owner);
      attachmentPayload.add({
        'id': attachment.id,
        'transferId': attachment.transferId,
        'fileName': attachment.fileName,
        'mimeType': attachment.mimeType,
        'mediaType': attachment.mediaType.name,
        'byteSize': attachment.byteSize,
        'sha256': sha256,
        'storagePath': path,
      });
    }
    await cloud.upsertPrivateBackupRecord(
      CloudPrivateBackupRecord(
        recordType: 'message',
        sourceId: message.id,
        payload: {
          'localMessageId': message.id,
          'localConversationId': message.conversationId,
          'senderIdentity': message.senderId,
          'senderDeviceId': message.senderDeviceId,
          'messageType': message.type.name,
          'content': message.text,
          'isOutgoing': message.outgoing,
          'deliveryStatus': message.status?.name ?? 'pending',
          'createdAt': message.createdAt?.toUtc().toIso8601String(),
          'readAt': message.readAt?.toUtc().toIso8601String(),
          'attachments': attachmentPayload,
          'provenance': 'account_private_backup',
        },
      ),
    );
    repositories.ownerContext.requireCurrent(owner);
  }

  Future<bool> _privateBackupIsEnabled({required bool guestMode}) async =>
      await privateBackupEnabled?.call(guestMode: guestMode) ?? true;

  Future<CloudAttachmentDto> _attachmentDto(
    RelioMediaAttachment attachment,
    String userId,
  ) async {
    if (!await mediaStorage.isManagedFile(attachment.localPath)) {
      throw const CloudException(
        'ไม่พบไฟล์สื่อในเครื่อง',
        code: 'missingLocalFile',
      );
    }
    final validation = await mediaStorage.validateFile(attachment.localPath);
    if (validation.mimeType != attachment.mimeType ||
        validation.byteSize != attachment.byteSize) {
      throw const CloudException(
        'ไฟล์ในเครื่องไม่ตรงกับ metadata',
        code: 'invalidLocalData',
      );
    }
    final digest = await mediaStorage.sha256ForFile(attachment.localPath);
    await repositories.attachments.updateChecksumSha256(attachment.id, digest);
    return CloudAttachmentDto(
      id: attachment.id,
      messageId: attachment.messageId,
      storagePath: _storagePath(attachment, userId),
      mediaType: attachment.mediaType.name,
      mimeType: attachment.mimeType,
      fileName: attachment.fileName,
      byteSize: attachment.byteSize,
      transferStatus: attachment.transferStatus.name,
      sha256: digest,
    );
  }

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
      case SyncOperation.attachmentDownload:
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
      case SyncOperation.privateBackupUpsert:
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
      case SyncOperation.attachmentUpload || SyncOperation.attachmentDownload:
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
      case SyncOperation.privateBackupUpsert:
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
      case SyncOperation.attachmentDownload:
        await repositories.attachments.updateCloudFileStatus(
          item.entityId,
          CloudSyncStatus.failed.value,
        );
        await repositories.attachments.markFailed(
          item.entityId,
          'cloud_download_failed',
        );
      case SyncOperation.profileUpsert ||
          SyncOperation.conversationUpsert ||
          SyncOperation.sosUpsert ||
          null:
        break;
      case SyncOperation.readReceiptUpsert:
        break;
      case SyncOperation.privateBackupUpsert:
        break;
    }
  }

  Future<void> _handleFailure(RelioQueueItem item, Object error) async {
    // จำกัดรายละเอียด diagnostics เพื่อไม่ให้ข้อความจาก backend เปิดเผยพิกัด SOS
    // เนื้อหาข้อความ token หรือข้อมูลอ่อนไหวใน payload    // Keep queue diagnostics safe: backend text must not echo SOS coordinates,
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
      if (SyncOperation.parse(item.operation) ==
          SyncOperation.attachmentDownload) {
        await repositories.attachments.updateCloudFileStatus(
          item.entityId,
          'downloadPending',
        );
      }
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
    if (_disposed) return;
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
      _internetSimulator.internetAvailable &&
      cloud.cloudState == CloudState.ready &&
      cloud.authState == AuthState.authenticated &&
      cloud.currentIdentity != null;

  void _scheduleRun() {
    if (!_started || _disposed) return;
    if (_runOperation != null) {
      _runAgain = true;
      return;
    }
    unawaited(run());
  }

  void _onInternetSimulatorChanged() {
    if (_internetSimulator.internetAvailable) {
      _scheduleRun();
      return;
    }
    _queueRetryTimer?.cancel();
    _queueRetryTimer = null;
    _pullRetryTimer?.cancel();
    _pullRetryTimer = null;
    unawaited(_setWaitingForCloud());
  }

  Future<void> _setWaitingForCloud() async {
    await _refreshSnapshot(state: SyncEngineState.waitingForCloud);
  }

  // สรุปคิวที่เก็บใน SQLite เพื่อแจ้ง Stream สถานะ โดยหน้า UI ต้องกรอง owner ตามการใช้งานเอง
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
    _internetSimulator.removeListener(_onInternetSimulatorChanged);
    _queueRetryTimer?.cancel();
    _pullRetryTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      await _runOperation;
    } on Object {
      /* owner-bound work may abort on disposal */
    }
    await _stateController.close();
  }
}
