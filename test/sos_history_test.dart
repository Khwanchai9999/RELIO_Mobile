import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/identity/owner_context.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';

void main() {
  test(
    'schema 12 upgrade preserves SOS rows without inventing history',
    () async {
      final directory = await Directory.systemTemp.createTemp('relio-sos-v12-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}relio.sqlite',
      );
      var db = AppDatabase.withExecutor(NativeDatabase(file));
      final startedAt = DateTime.utc(2026, 11, 3, 9);
      await db
          .into(db.sosEvents)
          .insert(
            SosEventsCompanion.insert(
              id: 'existing-sos',
              ownerDeviceId: 'peer-device',
              ownerUserId: 'peer-account',
              message: const Value('ต้องการความช่วยเหลือ'),
              latitude: const Value(14.04),
              longitude: const Value(100.73),
              locationAccuracy: const Value(10),
              locationCapturedAt: Value(startedAt),
              createdAt: startedAt,
              updatedAt: startedAt,
              isActive: true,
              deliveryStatus: 'delivered',
            ),
          );
      await db.customStatement('DROP TABLE sos_history_entries');
      await db.customStatement('PRAGMA user_version = 12');
      await db.close();

      db = AppDatabase.withExecutor(NativeDatabase(file));
      addTearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });

      expect(db.schemaVersion, 14);
      final existing = await db.select(db.sosEvents).getSingle();
      expect(existing.id, 'existing-sos');
      expect(existing.latitude, 14.04);
      expect(existing.longitude, 100.73);
      expect(existing.isActive, isTrue);
      expect(await db.select(db.sosHistoryEntries).get(), isEmpty);
    },
  );

  test(
    // ตรวจการซ่อนประวัติแยกตาม owner โดย SOS ที่กำลังทำงานยังอยู่ และประวัติไม่กลับมาหลังเปิดฐานข้อมูลใหม่
    'SOS history is durable, owner scoped, deduplicated and safely hidden',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'relio-sos-history-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}relio.sqlite',
      );
      var db = AppDatabase.withExecutor(NativeDatabase(file));
      var activeOwner = 'account-a';
      final changes = StreamController<Object?>.broadcast(sync: true);
      var owners = OwnerContext(() => activeOwner, changes.stream);
      var sos = _repository(db, owners, () => activeOwner);
      final startedAt = DateTime.utc(2026, 11, 3, 9);
      final firstFix = startedAt.add(const Duration(minutes: 1));
      final latestFix = startedAt.add(const Duration(minutes: 3));

      await sos.createIncoming(
        id: 'stable-sos-id',
        ownerDeviceId: 'requester-device',
        ownerUserId: 'requester-account',
        requesterDisplayName: 'ผู้ขอ QA',
        message: 'ต้องการความช่วยเหลือ',
        latitude: 14.01,
        longitude: 100.70,
        locationAccuracy: 20,
        locationCapturedAt: firstFix,
        createdAt: startedAt,
        isActive: true,
      );
      await sos.createIncoming(
        id: 'stable-sos-id',
        ownerDeviceId: 'requester-device',
        ownerUserId: 'requester-account',
        latitude: 14.04,
        longitude: 100.73,
        locationAccuracy: 8,
        locationCapturedAt: latestFix,
        createdAt: startedAt.add(const Duration(minutes: 2)),
        isActive: true,
      );
      await sos.createIncoming(
        id: 'stable-sos-id',
        ownerDeviceId: 'requester-device',
        ownerUserId: 'requester-account',
        latitude: 13.9,
        longitude: 100.6,
        locationCapturedAt: firstFix,
        createdAt: startedAt.add(const Duration(minutes: 4)),
        isActive: true,
      );

      var history = await sos.listHistory();
      expect(history, hasLength(1));
      expect(history.single.requesterDisplayName, 'ผู้ขอ QA');
      expect(history.single.event.createdAt, startedAt.toLocal());
      expect(history.single.event.latitude, 14.04);
      expect(history.single.event.longitude, 100.73);
      expect(history.single.event.locationCapturedAt, latestFix.toLocal());
      expect(await db.select(db.sosHistoryEntries).get(), hasLength(1));

      activeOwner = 'account-b';
      changes.add(null);
      expect(await sos.listHistory(), isEmpty);
      activeOwner = 'account-a';
      changes.add(null);
      expect(await sos.listHistory(), hasLength(1));

      await sos.hideHistory('stable-sos-id');
      expect(await sos.listHistory(), isEmpty);
      expect(
        (await sos.readActive(ownerDeviceId: 'requester-device'))?.isActive,
        isTrue,
      );
      await sos.createIncoming(
        id: 'stable-sos-id',
        ownerDeviceId: 'requester-device',
        ownerUserId: 'requester-account',
        createdAt: startedAt,
        isActive: true,
      );
      expect(await sos.listHistory(), isEmpty);
      expect((await db.select(db.sosEvents).getSingle()).isActive, isTrue);

      await sos.createIncoming(
        id: 'second-sos-id',
        ownerDeviceId: 'second-requester-device',
        ownerUserId: 'second-requester-account',
        createdAt: startedAt,
        isActive: true,
      );
      expect(await sos.listHistory(), hasLength(1));
      await sos.hideAllHistory();
      expect(await sos.listHistory(), isEmpty);
      expect(
        (await db.select(db.sosEvents).get()).every((event) => event.isActive),
        isTrue,
      );
      expect(await db.select(db.messages).get(), isEmpty);
      expect(await db.select(db.syncQueue).get(), isEmpty);

      await owners.dispose();
      await db.close();
      db = AppDatabase.withExecutor(NativeDatabase(file));
      owners = OwnerContext(() => activeOwner);
      sos = _repository(db, owners, () => activeOwner);
      addTearDown(() async {
        await owners.dispose();
        await db.close();
        await changes.close();
        await directory.delete(recursive: true);
      });
      expect(await sos.listHistory(), isEmpty);
      expect(
        (await sos.readActive(ownerDeviceId: 'requester-device'))?.isActive,
        isTrue,
      );
    },
  );
}

DriftSosRepository _repository(
  AppDatabase db,
  OwnerContext owners,
  String? Function() ownerProvider,
) => DriftSosRepository(
  db,
  DriftSyncQueueRepository(db, ownerUserIdProvider: ownerProvider),
  ownerContext: owners,
  ownerUserIdProvider: ownerProvider,
);
