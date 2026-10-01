enum SyncQueueStatus {
  pending('pending'),
  processing('processing'),
  completed('completed'),
  failed('failed');

  const SyncQueueStatus(this.value);

  final String value;

  static SyncQueueStatus? parse(String value) => values
      .cast<SyncQueueStatus?>()
      .firstWhere((item) => item!.value == value, orElse: () => null);
}

enum SyncOperation {
  profileUpsert('profileUpsert'),
  conversationUpsert('conversationUpsert'),
  messageUpsert('messageUpsert'),
  sosUpsert('sosUpsert'),
  attachmentMetadataUpsert('attachmentMetadataUpsert'),
  attachmentUpload('attachmentUpload'),
  readReceiptUpsert('readReceiptUpsert');

  const SyncOperation(this.value);

  final String value;

  static SyncOperation? parse(String value) => values
      .cast<SyncOperation?>()
      .firstWhere((item) => item!.value == value, orElse: () => null);
}

enum SyncEntityType {
  profile('profile'),
  conversation('conversation'),
  message('message'),
  sosEvent('sos_event'),
  attachment('attachment');

  const SyncEntityType(this.value);

  final String value;

  static SyncEntityType? parse(String value) => values
      .cast<SyncEntityType?>()
      .firstWhere((item) => item!.value == value, orElse: () => null);
}

enum CloudSyncStatus {
  notQueued('notQueued'),
  pending('pending'),
  syncing('syncing'),
  synced('synced'),
  failed('failed');

  const CloudSyncStatus(this.value);

  final String value;

  static CloudSyncStatus parse(String value) => values.firstWhere(
    (item) => item.value == value,
    orElse: () => CloudSyncStatus.notQueued,
  );
}

class SyncQueueSummary {
  const SyncQueueSummary({
    required this.pending,
    required this.processing,
    required this.completed,
    required this.failed,
  });

  const SyncQueueSummary.empty()
    : pending = 0,
      processing = 0,
      completed = 0,
      failed = 0;

  final int pending;
  final int processing;
  final int completed;
  final int failed;

  int get total => pending + processing + completed + failed;
}
