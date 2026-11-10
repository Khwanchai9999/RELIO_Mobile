import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/sync/sync_types.dart';
import 'package:relio_mobile/features/sync/sync_status_counts.dart';

RelioQueueItem item(
  String id,
  String status, {
  String owner = 'owner-a',
  String type = 'message',
  SyncOperation operation = SyncOperation.messageUpsert,
}) => RelioQueueItem(
  id: id,
  entityType: type,
  entityId: id,
  operation: operation.value,
  status: status,
  ownerUserId: owner,
  attemptCount: 1,
  lastError: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  nextAttemptAt: null,
);

void main() {
  group('SyncQueueCounts', () {
    test('known empty queues display zero counts', () {
      final counts = SyncQueueCounts.fromItems([], ownerUserId: 'owner-a');
      expect(counts.pending, 0);
      expect(counts.failed, 0);
    });

    test('pending and processing count unique owned Cloud work', () {
      final counts = SyncQueueCounts.fromItems([
        item('pending', 'pending'),
        item('running', 'processing'),
        item(
          'upload',
          'pending',
          type: 'attachment',
          operation: SyncOperation.attachmentUpload,
        ),
        item(
          'upload',
          'pending',
          type: 'attachment',
          operation: SyncOperation.attachmentMetadataUpsert,
        ),
        item(
          'download',
          'pending',
          type: 'attachment',
          operation: SyncOperation.attachmentDownload,
        ),
        item('other-owner', 'pending', owner: 'owner-b'),
      ], ownerUserId: 'owner-a');
      expect(counts.pending, 3);
      expect(counts.failed, 0);
    });

    test(
      'failed work is exclusive and takes precedence over queued retries',
      () {
        final counts = SyncQueueCounts.fromItems([
          item('same', 'pending'),
          item('same', 'failed', operation: SyncOperation.privateBackupUpsert),
          item('second', 'failed'),
        ], ownerUserId: 'owner-a');
        expect(counts.pending, 0);
        expect(counts.failed, 2);
      },
    );

    test('successful retry removes failed and pending counts', () {
      final failed = SyncQueueCounts.fromItems([
        item('retry', 'failed'),
      ], ownerUserId: 'owner-a');
      final completed = SyncQueueCounts.fromItems([
        item('retry', 'completed'),
      ], ownerUserId: 'owner-a');
      expect(failed.failed, 1);
      expect(completed.failed, 0);
      expect(completed.pending, 0);
    });
  });

  group('fetchConfirmedPrivateBackupCount', () {
    final identity = CloudIdentity(
      userId: 'owner-a',
      email: 'owner@example.test',
    );

    test(
      'counts unique confirmed records by owner and backup type only',
      () async {
        final cloud = FakeCloudDataSource(
          restoreIdentityOnInitialize: identity,
        );
        await cloud.initialize();
        cloud.privateBackupRecords.addAll({
          'owner-a:message:m1': const CloudPrivateBackupRecord(
            recordType: 'message',
            sourceId: 'm1',
            payload: {'attachment': 'x'},
          ),
          'owner-a:conversation:c1': const CloudPrivateBackupRecord(
            recordType: 'conversation',
            sourceId: 'c1',
            payload: {},
          ),
          'owner-b:message:m2': const CloudPrivateBackupRecord(
            recordType: 'message',
            sourceId: 'm2',
            payload: {},
          ),
        });
        expect(await fetchConfirmedPrivateBackupCount(cloud, 'owner-a'), 2);
      },
    );

    test(
      'offline, unauthenticated and failed Cloud lookups stay unknown',
      () async {
        final signedOut = FakeCloudDataSource();
        await signedOut.initialize();
        expect(
          await fetchConfirmedPrivateBackupCount(signedOut, 'owner-a'),
          isNull,
        );

        final cloud = FakeCloudDataSource(
          restoreIdentityOnInitialize: identity,
        );
        await cloud.initialize();
        cloud.offline = true;
        expect(
          await fetchConfirmedPrivateBackupCount(cloud, 'owner-a'),
          isNull,
        );

        cloud.offline = false;
        cloud.failureMode = FakeCloudFailure.temporaryServer;
        expect(
          await fetchConfirmedPrivateBackupCount(cloud, 'owner-a'),
          isNull,
        );
      },
    );
  });
}
