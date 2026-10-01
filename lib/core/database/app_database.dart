import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get participantId => text()();
  TextColumn get displayName => text()();
  TextColumn get participantStatus => text()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastMessageAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CloudConversationLinks extends Table {
  TextColumn get localConversationId => text()();
  TextColumn get cloudConversationId => text()();
  TextColumn get ownerUserId => text()();
  TextColumn get peerUserId => text()();
  DateTimeColumn get messageCursorAt => dateTime().nullable()();
  TextColumn get messageCursorId => text().nullable()();
  DateTimeColumn get receiptCursorAt => dateTime().nullable()();
  TextColumn get receiptCursorMessageId => text().nullable()();
  TextColumn get receiptCursorReaderId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {localConversationId, ownerUserId};
}

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get senderId => text()();
  TextColumn get senderDeviceId => text().nullable()();
  TextColumn get messageType => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get deliveryStatus => text()();
  TextColumn get cloudSyncStatus =>
      text().withDefault(const Constant('notQueued'))();
  BoolColumn get isOutgoing => boolean()();
  TextColumn get localFilePath => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get locationAccuracy => real().nullable()();
  DateTimeColumn get locationCapturedAt => dateTime().nullable()();
  TextColumn get nearbyMessageId => text().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class NearbyDevices extends Table {
  TextColumn get deviceId => text()();
  TextColumn get displayName => text()();
  TextColumn get status => text()();
  DateTimeColumn get lastSeenAt => dateTime()();
  IntColumn get signalQuality => integer().nullable()();
  IntColumn get approxDistance => integer().nullable()();
  BoolColumn get isTrusted => boolean().withDefault(const Constant(false))();
  BoolColumn get isBlocked => boolean().withDefault(const Constant(false))();
  BoolColumn get autoReconnectEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get publicIdentityKey => text().nullable()();
  TextColumn get publicIdentityFingerprint => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {deviceId};
}

class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get status => text()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get ownerUserId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SosEvents extends Table {
  TextColumn get id => text()();
  TextColumn get ownerDeviceId => text()();
  TextColumn get ownerUserId => text()();
  TextColumn get message => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get locationAccuracy => real().nullable()();
  DateTimeColumn get locationCapturedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isActive => boolean()();
  TextColumn get deliveryStatus => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get messageId => text()();
  TextColumn get transferId => text()();
  TextColumn get mediaType => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  TextColumn get localPath => text()();
  TextColumn get remoteFileName => text().nullable()();
  IntColumn get byteSize => integer()();
  IntColumn get bytesTransferred => integer().withDefault(const Constant(0))();
  TextColumn get transferStatus => text()();
  TextColumn get cloudMetadataStatus =>
      text().withDefault(const Constant('notQueued'))();
  TextColumn get cloudFileStatus =>
      text().withDefault(const Constant('notQueued'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get errorCode => text().nullable()();
  TextColumn get checksumSha256 => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class RelayPackets extends Table {
  TextColumn get packetId => text()();
  TextColumn get originDeviceId => text()();
  TextColumn get destinationDeviceId => text()();
  TextColumn get payloadType => text()();
  TextColumn get payloadId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime()();
  IntColumn get hopCount => integer()();
  IntColumn get maxHops => integer()();
  IntColumn get priority => integer()();
  TextColumn get previousHopDeviceId => text().nullable()();
  TextColumn get protocol => text()();
  TextColumn get payloadJson => text()();
  TextColumn get state => text()();
  DateTimeColumn get storedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {packetId};
}

class RelayForwardHistory extends Table {
  TextColumn get packetId => text()();
  TextColumn get targetDeviceId => text()();
  TextColumn get targetEndpointId => text()();
  TextColumn get status => text()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {packetId, targetDeviceId};
}

@DriftDatabase(
  tables: [
    Conversations,
    CloudConversationLinks,
    Messages,
    NearbyDevices,
    SyncQueue,
    SosEvents,
    AppSettings,
    Attachments,
    RelayPackets,
    RelayForwardHistory,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'relio_local'));

  AppDatabase.memory() : super(NativeDatabase.memory());

  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) async => migrator.createAll(),
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from < 2) {
        await migrator.createTable(attachments);
        await migrator.addColumn(sosEvents, sosEvents.locationAccuracy);
        await migrator.addColumn(sosEvents, sosEvents.locationCapturedAt);
      }
      if (from < 3) {
        await migrator.addColumn(messages, messages.cloudSyncStatus);
        await migrator.addColumn(syncQueue, syncQueue.ownerUserId);
        await migrator.addColumn(attachments, attachments.cloudMetadataStatus);
        await migrator.addColumn(attachments, attachments.cloudFileStatus);
        await customStatement('''
          UPDATE sync_queue
          SET operation = CASE entity_type
            WHEN 'message' THEN 'messageUpsert'
            WHEN 'sos_event' THEN 'sosUpsert'
            WHEN 'attachment' THEN 'attachmentMetadataUpsert'
            ELSE operation
          END
          WHERE operation = 'cloud_sync'
        ''');
      }
      if (from < 4) {
        await migrator.createTable(relayPackets);
        await migrator.createTable(relayForwardHistory);
      }
      if (from < 5) {
        await migrator.addColumn(conversations, conversations.unreadCount);
        await migrator.addColumn(messages, messages.readAt);
        await migrator.addColumn(nearbyDevices, nearbyDevices.isTrusted);
        await migrator.addColumn(nearbyDevices, nearbyDevices.isBlocked);
        await migrator.addColumn(
          nearbyDevices,
          nearbyDevices.autoReconnectEnabled,
        );
      }
      if (from < 6) {
        await migrator.addColumn(
          nearbyDevices,
          nearbyDevices.publicIdentityKey,
        );
        await migrator.addColumn(
          nearbyDevices,
          nearbyDevices.publicIdentityFingerprint,
        );
        // Peers created before key pinning must pair again before auto-reconnect.
        await customStatement(
          'UPDATE nearby_devices SET auto_reconnect_enabled = 0',
        );
      }
      if (from < 7) {
        await migrator.createTable(cloudConversationLinks);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
