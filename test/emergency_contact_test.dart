import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/identity/owner_context.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/repositories/principal_profile_repository.dart';
import 'package:relio_mobile/features/emergency/emergency_contact_repository.dart';
import 'package:relio_mobile/features/emergency/emergency_contact_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'emergency screen creates, dials, edits and confirms deletion offline',
    (tester) async {
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(autoAcknowledge: false),
      );
      final dialed = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('relio/emergency_dialer'),
        (call) async {
          expect(call.method, 'openDialer');
          dialed.add(
            (call.arguments as Map<Object?, Object?>)['phone'] as String,
          );
          return null;
        },
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('relio/emergency_dialer'),
          null,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await dependencies.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: dependencies,
            child: const EmergencyContactScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีผู้ติดต่อฉุกเฉินที่บันทึกไว้'), findsOneWidget);
      await tester.tap(find.text('เพิ่มผู้ติดต่อ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'แม่');
      await tester.enterText(
        find.byType(TextFormField).last,
        '+66 81 234 5678',
      );
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();
      expect(find.text('แม่'), findsOneWidget);
      await tester.tap(find.text('เปิดแอปโทรศัพท์'));
      await tester.pumpAndSettle();
      expect(dialed, ['+66 81 234 5678']);
      await tester.tap(find.text('แก้ไข'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'พี่สาว');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();
      expect(find.text('พี่สาว'), findsOneWidget);
      await tester.tap(find.text('ลบ').first);
      await tester.pumpAndSettle();
      expect(find.text('ลบผู้ติดต่อฉุกเฉิน?'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(find.text('พี่สาว'), findsOneWidget);
      await tester.tap(find.text('ลบ').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบ').last);
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีผู้ติดต่อฉุกเฉินที่บันทึกไว้'), findsOneWidget);
    },
  );

  testWidgets('emergency screen supports narrow widths and large Thai text', (
    tester,
  ) async {
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await dependencies.dispose();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: RelioDependencyScope(
          dependencies: dependencies,
          child: const EmergencyContactScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final width in [320.0, 360.0, 393.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.6]) {
        tester.view.physicalSize = Size(width, 800);
        tester.binding.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          equals(null),
          reason: '$width dp at $scale',
        );
      }
    }
  });
  test(
    'emergency contacts support offline CRUD and principal isolation',
    () async {
      final db = AppDatabase.memory();
      String? active;
      final changes = StreamController<Object?>.broadcast(sync: true);
      final owners = OwnerContext(() => active, changes.stream);
      final profiles = PrincipalProfileRepository(db, owners);
      final contacts = EmergencyContactRepository(db, profiles);
      addTearDown(() async {
        profiles.dispose();
        await owners.dispose();
        await changes.close();
        await db.close();
      });

      await contacts.save(name: 'ผู้ติดต่อ Guest', phone: '+66 81 234 5678');
      final guest = (await contacts.list()).single;
      expect(guest.phone, '+66 81 234 5678');
      await contacts.save(
        id: guest.id,
        name: 'ชื่อใหม่',
        phone: '0812345678',
        relationship: 'ครอบครัว',
        note: 'โทรเมื่อจำเป็น',
      );
      expect((await contacts.list()).single.name, 'ชื่อใหม่');

      active = 'account-a';
      changes.add(null);
      expect(await contacts.list(), isEmpty);
      await contacts.save(name: 'ผู้ติดต่อ A', phone: '12345');
      final accountA = (await contacts.list()).single;
      await expectLater(
        contacts.save(id: guest.id, name: 'ผิดคน', phone: '12345'),
        throwsStateError,
      );
      active = 'account-b';
      changes.add(null);
      expect(await contacts.list(), isEmpty);
      await contacts.save(name: 'ผู้ติดต่อ B', phone: '54321');
      expect((await contacts.list()).single.name, 'ผู้ติดต่อ B');
      active = 'account-a';
      changes.add(null);
      expect((await contacts.list()).single.id, accountA.id);
      await contacts.delete(accountA.id);
      expect(await contacts.list(), isEmpty);
      active = null;
      changes.add(null);
      expect((await contacts.list()).single.name, 'ชื่อใหม่');
      expect(await db.select(db.syncQueue).get(), isEmpty);
    },
  );

  test(
    'owner switch during pending write fails closed, including A to B to A',
    () async {
      final db = AppDatabase.memory();
      var active = 'account-a';
      final changes = StreamController<Object?>.broadcast(sync: true);
      final owners = OwnerContext(() => active, changes.stream);
      final profiles = PrincipalProfileRepository(db, owners);
      final contacts = EmergencyContactRepository(db, profiles);
      addTearDown(() async {
        profiles.dispose();
        await owners.dispose();
        await changes.close();
        await db.close();
      });
      final pending = contacts.save(name: 'ห้ามบันทึก', phone: '12345');
      active = 'account-b';
      changes.add(null);
      active = 'account-a';
      changes.add(null);
      await expectLater(pending, throwsA(isA<OwnerChangedException>()));
      expect(await contacts.list(), isEmpty);
    },
  );

  test(
    'contacts persist after reopening a disposable local database',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'relio-emergency-reopen-',
      );
      final file = File('${dir.path}${Platform.pathSeparator}local.sqlite');
      addTearDown(() => dir.delete(recursive: true));
      final first = AppDatabase.withExecutor(NativeDatabase(file));
      final firstOwners = OwnerContext(() => null);
      final firstProfiles = PrincipalProfileRepository(first, firstOwners);
      await EmergencyContactRepository(
        first,
        firstProfiles,
      ).save(name: 'ผู้ติดต่อ', phone: '+66 81 234 5678');
      firstProfiles.dispose();
      await firstOwners.dispose();
      await first.close();

      final reopened = AppDatabase.withExecutor(NativeDatabase(file));
      final reopenedOwners = OwnerContext(() => null);
      final reopenedProfiles = PrincipalProfileRepository(
        reopened,
        reopenedOwners,
      );
      addTearDown(() async {
        reopenedProfiles.dispose();
        await reopenedOwners.dispose();
        await reopened.close();
      });
      expect(
        (await EmergencyContactRepository(
          reopened,
          reopenedProfiles,
        ).list()).single.name,
        'ผู้ติดต่อ',
      );
    },
  );

  test(
    'schema 10 to 11 adds contacts and preserves existing local rows',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'relio-emergency-migration-',
      );
      final file = File('${dir.path}${Platform.pathSeparator}local.sqlite');
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase.withExecutor(NativeDatabase(file));
      final now = DateTime(2026, 1, 1);
      await db
          .into(db.conversations)
          .insert(
            ConversationsCompanion.insert(
              id: 'conversation',
              participantId: 'peer',
              displayName: 'peer',
              participantStatus: 'normal',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: 'message',
              conversationId: 'conversation',
              senderId: 'peer',
              messageType: 'text',
              content: 'preserved',
              createdAt: now,
              updatedAt: now,
              deliveryStatus: 'delivered',
              isOutgoing: false,
            ),
          );
      await db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: 'attachment',
              messageId: 'message',
              transferId: 'transfer',
              mediaType: 'image',
              fileName: 'file.png',
              mimeType: 'image/png',
              localPath: 'local',
              byteSize: 1,
              transferStatus: 'completed',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.sosEvents)
          .insert(
            SosEventsCompanion.insert(
              id: 'sos',
              ownerDeviceId: 'device',
              ownerUserId: 'owner',
              createdAt: now,
              updatedAt: now,
              isActive: false,
              deliveryStatus: 'delivered',
            ),
          );
      await db
          .into(db.nearbyDevices)
          .insert(
            NearbyDevicesCompanion.insert(
              deviceId: 'peer',
              displayName: 'peer',
              status: 'normal',
              lastSeenAt: now,
              isTrusted: const Value(true),
            ),
          );
      await db
          .into(db.syncQueue)
          .insert(
            SyncQueueCompanion.insert(
              id: 'queue',
              entityType: 'message',
              entityId: 'message',
              operation: 'messageUpsert',
              status: 'pending',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.customStatement(
        'INSERT INTO local_principal_profiles '
        '(principal_id,kind,display_name,updated_at) VALUES (?,?,?,?)',
        ['account:owner', 'account', 'Owner', 1],
      );
      await db.customStatement('DROP TABLE emergency_contacts');
      await db.customStatement('PRAGMA user_version = 10');
      await db.close();

      final upgraded = AppDatabase.withExecutor(NativeDatabase(file));
      addTearDown(upgraded.close);
      expect(await upgraded.select(upgraded.emergencyContacts).get(), isEmpty);
      expect(
        (await upgraded.select(upgraded.conversations).get()).single.id,
        'conversation',
      );
      expect(
        (await upgraded.select(upgraded.messages).get()).single.content,
        'preserved',
      );
      expect(
        (await upgraded.select(upgraded.attachments).get()).single.id,
        'attachment',
      );
      expect(
        (await upgraded.select(upgraded.sosEvents).get()).single.id,
        'sos',
      );
      expect(
        (await upgraded.select(upgraded.nearbyDevices).get()).single.isTrusted,
        isTrue,
      );
      expect(
        (await upgraded.select(upgraded.syncQueue).get()).single.id,
        'queue',
      );
      final profiles = await upgraded
          .customSelect('SELECT principal_id FROM local_principal_profiles')
          .get();
      expect(profiles.single.read<String>('principal_id'), 'account:owner');
    },
  );
}
