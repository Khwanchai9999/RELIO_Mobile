import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/media/media_storage_service.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/core/sync/sync_engine.dart';
import 'package:relio_mobile/core/sync/sync_types.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  test(
    'opted-in Guest backs up private rows without shared Cloud delivery',
    () async {
      final cloud = FakeCloudDataSource();
      final account = await cloud.signInAnonymously();
      final database = AppDatabase.memory();
      final repositories = RelioRepositories(
        database,
        ownerUserIdProvider: () => null,
      );
      final mediaRoot = await Directory.systemTemp.createTemp(
        'relio-guest-backup-',
      );
      final engine = SyncEngine(
        repositories: repositories,
        cloud: cloud,
        identity: RelioDeviceIdentityRepository(database),
        mediaStorage: MediaStorageService(rootDirectory: mediaRoot),
        isGuestBackupSession: () => true,
        privateBackupEnabled: ({required guestMode}) async => guestMode,
      );
      addTearDown(() async {
        await engine.dispose();
        await cloud.dispose();
        await database.close();
        await mediaRoot.delete(recursive: true);
      });

      final conversation = await repositories.conversations.ensureConversation(
        id: 'guest-backup-conversation',
        participantId: 'qa-peer-device',
        displayName: 'QA peer',
        participantStatus: DeviceStatus.normal,
      );
      final message = await repositories.messages.createOutgoingText(
        conversationId: conversation.id,
        senderId: account.userId,
        senderDeviceId: 'guest-device',
        text: 'Private Guest fixture only',
      );
      await engine.initialize();
      await engine.run();

      final records = await cloud.fetchPrivateBackupRecords(
        recordType: 'message',
        limit: 100,
      );
      expect(records.map((record) => record.sourceId), contains(message.id));
      expect(records.single.payload['content'], 'Private Guest fixture only');
      expect(cloud.conversations, isEmpty);
      expect(cloud.messages, isEmpty);

      final queue = await repositories.syncQueue.listAll();
      final privateRows = queue
          .where(
            (row) => row.operation == SyncOperation.privateBackupUpsert.value,
          )
          .toList(growable: false);
      expect(privateRows, hasLength(2));
      expect(
        privateRows.every(
          (row) =>
              row.ownerUserId == account.userId &&
              row.status == SyncQueueStatus.completed.value,
        ),
        isTrue,
      );
      final guestPrincipal =
          (await repositories.profiles.current()).principalId;
      for (final row in privateRows) {
        expect(
          await repositories.syncQueue.localPrincipalForItem(row.id),
          guestPrincipal,
        );
      }
      expect(
        queue
            .singleWhere(
              (row) =>
                  row.entityId == message.id &&
                  row.operation == SyncOperation.messageUpsert.value,
            )
            .status,
        SyncQueueStatus.pending.value,
      );

      await engine.run();
      expect(
        (await cloud.fetchPrivateBackupRecords(recordType: 'message')).length,
        1,
      );
      expect(cloud.privateBackupRecords, hasLength(2));
    },
  );
}
