import '../../core/domain/relio_entities.dart';
import '../../core/cloud/cloud_data_source.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/sync/sync_types.dart';

/// Unique Cloud write work, grouped by its persisted entity identity.
class SyncQueueCounts {
  const SyncQueueCounts({required this.pending, required this.failed});

  final int pending;
  final int failed;

  factory SyncQueueCounts.fromItems(
    Iterable<RelioQueueItem> items, {
    required String? ownerUserId,
  }) {
    const writes = {
      SyncOperation.profileUpsert,
      SyncOperation.conversationUpsert,
      SyncOperation.messageUpsert,
      SyncOperation.sosUpsert,
      SyncOperation.attachmentMetadataUpsert,
      SyncOperation.attachmentUpload,
      SyncOperation.readReceiptUpsert,
      SyncOperation.privateBackupUpsert,
    };
    final statuses = <String, String>{};
    int priority(String status) => switch (status) {
      'failed' => 3,
      'processing' => 2,
      'pending' => 1,
      _ => 0,
    };
    for (final item in items) {
      if (ownerUserId == null ||
          item.ownerUserId != ownerUserId ||
          !writes.contains(SyncOperation.parse(item.operation))) {
        continue;
      }
      final status = item.status;
      if (!{'pending', 'processing', 'failed'}.contains(status)) continue;
      final key = '${item.entityType}\u0000${item.entityId}';
      final current = statuses[key];
      if (current == null || priority(status) > priority(current)) {
        statuses[key] = status;
      }
    }
    return SyncQueueCounts(
      pending: statuses.values
          .where((s) => s == 'pending' || s == 'processing')
          .length,
      failed: statuses.values.where((s) => s == 'failed').length,
    );
  }
}

/// Counts the authenticated owner's actual private backup rows across both
/// record types. A failed/unauthorized lookup returns unknown, never zero.
Future<int?> fetchConfirmedPrivateBackupCount(
  CloudDataSource cloud,
  String? ownerId,
) async {
  if (ownerId == null ||
      cloud.authState != AuthState.authenticated ||
      cloud.cloudState != CloudState.ready) {
    return null;
  }
  final keys = <String>{};
  try {
    for (final type in const ['conversation', 'message']) {
      String? cursor;
      while (true) {
        if (cloud.currentIdentity?.userId != ownerId ||
            cloud.authState != AuthState.authenticated ||
            cloud.cloudState != CloudState.ready) {
          return null;
        }
        final page = await cloud.fetchPrivateBackupRecords(
          recordType: type,
          afterSourceId: cursor,
        );
        for (final record in page) {
          keys.add('${record.recordType}\u0000${record.sourceId}');
        }
        if (page.length < 100) break;
        cursor = page.last.sourceId;
      }
    }
  } catch (_) {
    return null;
  }
  return cloud.currentIdentity?.userId == ownerId ? keys.length : null;
}
