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
  IntColumn get batteryLevel => integer().nullable()();
  BoolColumn get isCharging => boolean().nullable()();
  DateTimeColumn get batteryUpdatedAt => dateTime().nullable()();
  RealColumn get peerLatitude => real().nullable()();
  RealColumn get peerLongitude => real().nullable()();
  RealColumn get peerLocationAccuracy => real().nullable()();
  DateTimeColumn get peerLocationCapturedAt => dateTime().nullable()();
  TextColumn get peerDeviceModel => text().nullable()();

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

class EmergencyContacts extends Table {
  TextColumn get id => text()();
  TextColumn get principalId => text()();
  TextColumn get name => text()();
  TextColumn get phone => text()();
  TextColumn get relationship => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
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
    EmergencyContacts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'relio_local'));

  AppDatabase.memory() : super(NativeDatabase.memory());

  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) async {
      await migrator.createAll();
      await _createConversationScopes();
      await _createPrincipalSchema();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS emergency_contacts_principal_idx '
        'ON emergency_contacts(principal_id)',
      );
    },
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
      if (from < 8) {
        await _createConversationScopes();
        await customStatement('''
          INSERT INTO conversation_scopes(conversation_id, owner_user_id, source_id)
          SELECT local_conversation_id, MIN(owner_user_id), local_conversation_id
          FROM cloud_conversation_links
          GROUP BY local_conversation_id
          HAVING COUNT(DISTINCT owner_user_id) = 1
        ''');
        await customStatement('''
          INSERT OR IGNORE INTO conversation_scopes(conversation_id, owner_user_id, source_id)
          SELECT messages.conversation_id, MIN(sync_queue.owner_user_id), messages.conversation_id
          FROM messages
          JOIN sync_queue
            ON sync_queue.entity_type = 'message'
            AND sync_queue.entity_id = messages.id
          WHERE sync_queue.owner_user_id IS NOT NULL
          GROUP BY messages.conversation_id
          HAVING COUNT(DISTINCT sync_queue.owner_user_id) = 1
        ''');
      }
      if (from < 9) {
        await migrator.addColumn(nearbyDevices, nearbyDevices.batteryLevel);
        await migrator.addColumn(nearbyDevices, nearbyDevices.isCharging);
        await migrator.addColumn(nearbyDevices, nearbyDevices.batteryUpdatedAt);
        await migrator.addColumn(nearbyDevices, nearbyDevices.peerLatitude);
        await migrator.addColumn(nearbyDevices, nearbyDevices.peerLongitude);
        await migrator.addColumn(
          nearbyDevices,
          nearbyDevices.peerLocationAccuracy,
        );
        await migrator.addColumn(
          nearbyDevices,
          nearbyDevices.peerLocationCapturedAt,
        );
        await migrator.addColumn(nearbyDevices, nearbyDevices.peerDeviceModel);
      }
      if (from < 10) {
        await _createPrincipalSchema();
        // หลักฐาน owner ต้องไม่ขัดกัน; แถวที่ระบุไม่ได้เก็บไว้ ไม่เปิดให้ Guest
        await customStatement('''
          INSERT OR IGNORE INTO conversation_principals
            (conversation_id, local_principal, remote_principal, remote_device_id, state)
          SELECT c.id,
            CASE WHEN s.owner_user_id IS NULL THEN 'legacyUnknown:' || c.id
              ELSE 'account:' || s.owner_user_id END,
            COALESCE((SELECT 'account:' || l.peer_user_id FROM cloud_conversation_links l
              WHERE l.local_conversation_id = c.id AND l.owner_user_id = s.owner_user_id LIMIT 1),
              'legacy-device:' || c.participant_id),
            c.participant_id,
            CASE WHEN s.owner_user_id IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM cloud_conversation_links l
                WHERE l.local_conversation_id = c.id AND l.owner_user_id != s.owner_user_id)
              AND NOT EXISTS (SELECT 1 FROM sync_queue q
                WHERE (q.entity_id = c.id OR q.entity_id IN
                  (SELECT m.id FROM messages m WHERE m.conversation_id = c.id))
                AND (q.owner_user_id IS NULL OR q.owner_user_id != s.owner_user_id))
              THEN 'active' ELSE 'legacyUnknown' END
          FROM conversations c LEFT JOIN conversation_scopes s ON s.conversation_id = c.id
        ''');
        await customStatement('''
          INSERT OR IGNORE INTO local_principal_profiles
            (principal_id, kind, display_name, is_custom, avatar_path, revision, updated_at)
          SELECT 'legacyUnknown:installation', 'legacyUnknown',
            COALESCE((SELECT value FROM app_settings WHERE key = 'display_name'), 'Legacy profile'),
            1, (SELECT value FROM app_settings WHERE key = 'profile_avatar_path'), 0, 0
          WHERE EXISTS (SELECT 1 FROM app_settings WHERE key IN ('display_name', 'profile_avatar_path'))
        ''');
      }
      if (from < 11) {
        await migrator.createTable(emergencyContacts);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS emergency_contacts_principal_idx '
          'ON emergency_contacts(principal_id)',
        );
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createConversationScopes() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS conversation_scopes (
        conversation_id TEXT PRIMARY KEY NOT NULL
          REFERENCES conversations(id) ON DELETE CASCADE,
        owner_user_id TEXT NOT NULL,
        source_id TEXT NOT NULL
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS conversation_scopes_owner_idx
      ON conversation_scopes(owner_user_id, conversation_id)
    ''');
    await customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS conversation_scopes_source_idx
      ON conversation_scopes(owner_user_id, source_id)
    ''');
  }

  Future<void> _createPrincipalSchema() async {
    await customStatement(
      '''CREATE TABLE IF NOT EXISTS local_principal_profiles (
      principal_id TEXT PRIMARY KEY NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('guest','account','legacyUnknown')),
      cloud_user_id TEXT,
      display_name TEXT NOT NULL,
      is_custom INTEGER NOT NULL DEFAULT 0,
      avatar_path TEXT,
      revision INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )''',
    );
    await customStatement(
      '''CREATE TABLE IF NOT EXISTS conversation_principals (
      conversation_id TEXT PRIMARY KEY NOT NULL REFERENCES conversations(id),
      local_principal TEXT NOT NULL,
      remote_principal TEXT NOT NULL,
      remote_device_id TEXT,
      state TEXT NOT NULL CHECK(state IN ('active','legacyUnknown'))
    )''',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS conversation_principal_pair_idx ON conversation_principals(local_principal, remote_principal)',
    );
    await customStatement(
      '''CREATE TABLE IF NOT EXISTS remote_principal_profiles (
      device_id TEXT NOT NULL, principal_id TEXT NOT NULL,
      display_name TEXT NOT NULL, revision INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      PRIMARY KEY(device_id, principal_id)
    )''',
    );
    await customStatement(
      '''CREATE TABLE IF NOT EXISTS nearby_active_principals (
      device_id TEXT PRIMARY KEY NOT NULL, principal_id TEXT NOT NULL
    )''',
    );
    await customStatement('''CREATE TABLE IF NOT EXISTS profile_sync_snapshots (
      queue_id TEXT PRIMARY KEY NOT NULL, owner_user_id TEXT NOT NULL,
      display_name TEXT NOT NULL, revision INTEGER NOT NULL
    )''');
    await customStatement('''CREATE TABLE IF NOT EXISTS queue_principals (
      queue_id TEXT PRIMARY KEY NOT NULL, local_principal TEXT NOT NULL
    )''');
  }
}
