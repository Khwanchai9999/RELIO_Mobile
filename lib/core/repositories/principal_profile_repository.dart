import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../cloud/cloud_data_source.dart';
import '../cloud/cloud_models.dart';
import '../database/app_database.dart';
import '../identity/owner_context.dart';

class PrincipalProfile {
  const PrincipalProfile(
    this.principalId,
    this.displayName,
    this.isCustom,
    this.avatarPath,
    this.revision,
  );
  final String principalId;
  final String displayName;
  final bool isCustom;
  final String? avatarPath;
  final int revision;
}

/// Profile แยกตามคน; device_id และ legacy settings ไม่ถูกเปลี่ยนเมื่อสลับบัญชี
class PrincipalProfileRepository extends ChangeNotifier {
  PrincipalProfileRepository(this.db, this.owners) {
    _subscription = owners.changes.listen((_) {
      notifyListeners();
      unawaited(refresh().catchError((Object _) {}));
    });
  }
  final AppDatabase db;
  final OwnerContext owners;
  late final StreamSubscription<Object?> _subscription;
  CloudDataSource? cloud;

  Future<String> guestPrincipal() => guestPrincipalFor(db);

  static Future<String> guestPrincipalFor(AppDatabase db) async {
    await db.customStatement(
      'INSERT OR IGNORE INTO app_settings(key,value,updated_at) VALUES (?,?,?)',
      [
        'guest_principal',
        'guest:${const Uuid().v4()}',
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ],
    );
    final row = await db
        .customSelect(
          "SELECT value FROM app_settings WHERE key='guest_principal'",
        )
        .getSingle();
    return row.read<String>('value');
  }

  Future<String> principalFor(OwnerSnapshot owner) async =>
      owner.userId == null ? guestPrincipal() : 'account:${owner.userId}';

  Future<PrincipalProfile> current() async {
    final owner = owners.capture();
    final id = await principalFor(owner);
    owners.requireCurrent(owner);
    final result = await forPrincipal(id);
    owners.requireCurrent(owner);
    return result;
  }

  Future<PrincipalProfile> forPrincipal(String id) => loadPrincipal(db, id);

  static Future<PrincipalProfile> loadPrincipal(
    AppDatabase db,
    String id,
  ) async {
    await db.customStatement(
      'INSERT OR IGNORE INTO local_principal_profiles '
      '(principal_id,kind,cloud_user_id,display_name,updated_at) VALUES (?,?,?,?,?)',
      [
        id,
        id.startsWith('account:') ? 'account' : 'guest',
        id.startsWith('account:') ? id.substring(8) : null,
        'ผู้ใช้ RELIO ${Random.secure().nextInt(9000) + 1000}',
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    final row = await db
        .customSelect(
          'SELECT * FROM local_principal_profiles WHERE principal_id=?',
          variables: [Variable.withString(id)],
        )
        .getSingle();
    return PrincipalProfile(
      id,
      row.read<String>('display_name'),
      row.read<int>('is_custom') == 1,
      row.readNullable<String>('avatar_path'),
      row.read<int>('revision'),
    );
  }

  // ผูกชื่อและ snapshot ในคิวกับ principal ที่เริ่มแก้ไข แล้วตรวจ owner ซ้ำใน transaction
  Future<void> setName(String name, {bool enqueue = true}) async {
    name = name.trim();
    if (name.isEmpty || name.runes.length > 40) throw ArgumentError.value(name);
    final owner = owners.capture();
    final profile = await current();
    owners.requireCurrent(owner);
    await db.transaction(() async {
      owners.requireCurrent(owner);
      await db.customStatement(
        'UPDATE local_principal_profiles SET display_name=?,is_custom=?,'
        'revision=revision+1,updated_at=? WHERE principal_id=?',
        [
          name,
          RegExp(r'^ผู้ใช้ RELIO \d{4}$').hasMatch(name) ? 0 : 1,
          DateTime.now().millisecondsSinceEpoch,
          profile.principalId,
        ],
      );
      if (enqueue && owner.userId != null) {
        final queueId = const Uuid().v4();
        final now = DateTime.now();
        await db
            .into(db.syncQueue)
            .insert(
              SyncQueueCompanion.insert(
                id: queueId,
                entityType: 'profile',
                entityId: profile.principalId,
                operation: 'profileUpsert',
                status: 'pending',
                ownerUserId: Value(owner.userId),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await db.customStatement(
          'INSERT INTO profile_sync_snapshots VALUES (?,?,?,?)',
          [queueId, owner.userId, name, profile.revision + 1],
        );
        await db.customStatement('INSERT INTO queue_principals VALUES (?,?)', [
          queueId,
          profile.principalId,
        ]);
      }
      owners.requireCurrent(owner);
    });
    if (owners.isCurrent(owner)) notifyListeners();
  }

  Future<void> setAvatar(String? path, OwnerSnapshot owner) async {
    owners.requireCurrent(owner);
    final profile = await current();
    await db.transaction(() async {
      owners.requireCurrent(owner);
      await db.customStatement(
        'UPDATE local_principal_profiles SET avatar_path=?,revision=revision+1,'
        'updated_at=? WHERE principal_id=?',
        [path, DateTime.now().millisecondsSinceEpoch, profile.principalId],
      );
      owners.requireCurrent(owner);
    });
    if (owners.isCurrent(owner)) notifyListeners();
  }

  Future<void> refresh() async {
    final owner = owners.capture();
    var cached = await current();
    owners.requireCurrent(owner);
    notifyListeners();
    final source = cloud;
    final authenticated = source?.currentIdentity;
    final initialName = authenticated?.displayName?.trim();
    // บัญชีที่เพิ่งยืนยัน email อาจยังไม่มี profiles row; ใช้เฉพาะ metadata ของ owner ที่ตรงกัน
    if (cached.revision == 0 &&
        authenticated?.userId == owner.userId &&
        initialName != null &&
        initialName.isNotEmpty &&
        initialName.runes.length <= 40) {
      owners.requireCurrent(owner);
      await setName(initialName, enqueue: false);
      cached = await current();
      owners.requireCurrent(owner);
    }
    if (owner.userId == null ||
        source == null ||
        source.cloudState != CloudState.ready) {
      return;
    }
    try {
      final remote = await source.fetchMyProfile();
      owners.requireCurrent(owner);
      if (remote.displayName.trim().isEmpty ||
          remote.displayName.runes.length > 40 ||
          remote.userId != owner.userId) {
        return;
      }
      var applied = false;
      await db.transaction(() async {
        owners.requireCurrent(owner);
        final latest = await current();
        if (latest.revision != cached.revision) return;
        // ตรวจ revision และคิวใน transaction เดียว ไม่ให้ Cloud fetch ทับ local edit
        final pending = await db
            .customSelect(
              'SELECT 1 FROM profile_sync_snapshots p JOIN sync_queue q ON q.id=p.queue_id '
              'WHERE p.owner_user_id=? AND q.status != ? LIMIT 1',
              variables: [
                Variable.withString(owner.userId!),
                Variable.withString('completed'),
              ],
            )
            .get();
        owners.requireCurrent(owner);
        if (pending.isNotEmpty ||
            latest.displayName == remote.displayName.trim()) {
          return;
        }
        await db.customStatement(
          'UPDATE local_principal_profiles SET display_name=?,is_custom=1,'
          'revision=revision+1,updated_at=? WHERE principal_id=? AND revision=?',
          [
            remote.displayName.trim(),
            DateTime.now().millisecondsSinceEpoch,
            cached.principalId,
            cached.revision,
          ],
        );
        owners.requireCurrent(owner);
        applied = true;
      });
      if (applied && owners.isCurrent(owner)) notifyListeners();
    } on CloudException {
      /* cache ของ owner นี้ยังใช้งาน offline ได้ */
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
