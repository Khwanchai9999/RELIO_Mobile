import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/identity/owner_context.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/repositories/principal_profile_repository.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/emergency/emergency_contact_repository.dart';
import 'package:relio_mobile/features/emergency/emergency_contact_screen.dart';
import 'package:relio_mobile/features/emergency/emergency_profile_repository.dart';
import 'package:relio_mobile/features/rescue/rescue_screen.dart';
import 'package:relio_mobile/features/sos/sos_screens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'profile CRUD is local, optional, principal-scoped and independent',
    () async {
      final db = AppDatabase.memory();
      var active = null as String?;
      final changes = StreamController<Object?>.broadcast(sync: true);
      final owners = OwnerContext(() => active, changes.stream);
      final profiles = PrincipalProfileRepository(db, owners);
      final emergency = EmergencyProfileRepository(db, profiles);
      final contacts = EmergencyContactRepository(db, profiles);
      addTearDown(() async {
        profiles.dispose();
        await owners.dispose();
        await changes.close();
        await db.close();
      });

      expect(await emergency.read(), const EmergencyProfileData());
      await contacts.save(name: 'QA contact', phone: '12345');
      await emergency.save(
        medicalConditions: 'synthetic condition',
        allergies: 'synthetic allergy',
        medications: '',
        careNotes: 'synthetic care note',
        shareContactsOnSos: false,
        shareHealthOnSos: true,
      );
      final guestProfile = await emergency.read();
      expect(guestProfile.medicalConditions, 'synthetic condition');
      expect(guestProfile.allergies, 'synthetic allergy');
      expect(guestProfile.shareContactsOnSos, isFalse);
      expect(guestProfile.shareHealthOnSos, isTrue);

      active = 'account-a';
      changes.add(null);
      expect(await emergency.read(), const EmergencyProfileData());
      await emergency.save(
        medicalConditions: '',
        allergies: '',
        medications: 'synthetic medication',
        careNotes: '',
        shareContactsOnSos: true,
        shareHealthOnSos: false,
      );
      active = 'account-b';
      changes.add(null);
      expect(await emergency.read(), const EmergencyProfileData());
      expect(await contacts.list(), isEmpty);

      active = 'account-a';
      changes.add(null);
      expect((await emergency.read()).medications, 'synthetic medication');
      await emergency.delete();
      expect(await emergency.read(), const EmergencyProfileData());
      expect(await db.select(db.syncQueue).get(), isEmpty);

      active = null;
      changes.add(null);
      expect((await emergency.read()).medicalConditions, 'synthetic condition');
      expect((await contacts.list()).single.name, 'QA contact');
    },
  );

  test('owner switch during profile save fails closed', () async {
    final db = AppDatabase.memory();
    var active = 'account-a';
    final changes = StreamController<Object?>.broadcast(sync: true);
    final owners = OwnerContext(() => active, changes.stream);
    final profiles = PrincipalProfileRepository(db, owners);
    final repository = EmergencyProfileRepository(db, profiles);
    addTearDown(() async {
      profiles.dispose();
      await owners.dispose();
      await changes.close();
      await db.close();
    });

    final expectedOwner = owners.capture();
    final pending = repository.save(
      expectedOwner: expectedOwner,
      medicalConditions: 'synthetic private value',
      allergies: '',
      medications: '',
      careNotes: '',
      shareContactsOnSos: false,
      shareHealthOnSos: false,
    );
    active = 'account-b';
    changes.add(null);
    active = 'account-a';
    changes.add(null);
    await expectLater(pending, throwsA(isA<OwnerChangedException>()));
    expect(await repository.read(), const EmergencyProfileData());
  });

  test(
    'schema 11 to 13 adds profiles without changing emergency contacts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'relio-emergency-profile-migration-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}local.sqlite',
      );
      addTearDown(() => directory.delete(recursive: true));
      final before = AppDatabase.withExecutor(NativeDatabase(file));
      await before
          .into(before.emergencyContacts)
          .insert(
            EmergencyContactsCompanion.insert(
              id: 'existing-contact',
              principalId: 'guest:installation',
              name: 'Existing contact',
              phone: '12345',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          );
      await before.customStatement('DROP TABLE emergency_profiles');
      await before.customStatement('PRAGMA user_version = 11');
      await before.close();

      final after = AppDatabase.withExecutor(NativeDatabase(file));
      addTearDown(after.close);
      expect(
        (await after.select(after.emergencyContacts).get()).single.name,
        'Existing contact',
      );
      expect(await after.select(after.emergencyProfiles).get(), isEmpty);
    },
  );

  testWidgets('emergency form saves optional fields and separate preferences', (
    tester,
  ) async {
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await dependencies.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    await tester.pumpWidget(
      MaterialApp(
        home: RelioDependencyScope(
          dependencies: dependencies,
          child: const EmergencyContactScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('ข้อมูลสุขภาพที่ควรทราบ'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(4));
    await tester.enterText(find.byType(TextField).first, 'synthetic condition');
    await tester.enterText(
      find.byType(TextField).last,
      'synthetic first-aid note',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNWidgets(2));
    await tester.ensureVisible(find.text('ข้อมูลสุขภาพ'));
    await tester.tap(find.text('ข้อมูลสุขภาพ'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('บันทึกข้อมูลฉุกเฉิน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึกข้อมูลฉุกเฉิน'));
    await tester.pumpAndSettle();

    final saved = await EmergencyProfileRepository(
      dependencies.database,
      dependencies.repositories.profiles,
    ).read();
    expect(saved.medicalConditions, 'synthetic condition');
    expect(saved.careNotes, 'synthetic first-aid note');
    expect(saved.shareContactsOnSos, isFalse);
    expect(saved.shareHealthOnSos, isTrue);
  });

  testWidgets(
    'rescue lists current SOS requests and protects local health data',
    (tester) async {
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(autoAcknowledge: false),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await dependencies.dispose();
      });
      await EmergencyProfileRepository(
        dependencies.database,
        dependencies.repositories.profiles,
      ).save(
        medicalConditions: 'SYNTHETIC_PRIVATE_HEALTH_SENTINEL',
        allergies: '',
        medications: '',
        careNotes: '',
        shareContactsOnSos: true,
        shareHealthOnSos: true,
      );
      final now = DateTime(2026, 10, 31, 12);
      await dependencies.repositories.sos.createIncoming(
        id: 'older-sos',
        ownerDeviceId: 'device-older',
        ownerUserId: 'sender-older',
        message: 'ต้องการความช่วยเหลือ',
        createdAt: now.subtract(const Duration(minutes: 5)),
        isActive: true,
      );
      await dependencies.repositories.sos.createIncoming(
        id: 'newer-sos',
        ownerDeviceId: 'device-newer',
        ownerUserId: 'sender-newer',
        message: 'ขอความช่วยเหลือด่วน',
        latitude: 14.04,
        longitude: 100.73,
        locationCapturedAt: now,
        createdAt: now,
        isActive: true,
      );
      await dependencies.repositories.sos.createIncoming(
        id: 'middle-sos',
        ownerDeviceId: 'device-middle',
        ownerUserId: 'sender-middle',
        message: 'ต้องการความช่วยเหลือระหว่างทาง',
        createdAt: now.subtract(const Duration(minutes: 2)),
        isActive: true,
      );
      final nearby = dependencies.nearbyService;
      nearby.discoveredPeers.addAll([
        NearbyPeer(
          id: 'endpoint-older',
          name: 'QA Older Peer',
          deviceId: 'device-older',
          lastSeenAt: now.subtract(const Duration(minutes: 5)),
        ),
        NearbyPeer(
          id: 'endpoint-newer',
          name: 'QA Newer Peer',
          deviceId: 'device-newer',
          lastSeenAt: now,
        ),
        NearbyPeer(
          id: 'endpoint-middle',
          name: 'QA Middle Peer',
          deviceId: 'device-middle',
          lastSeenAt: now.subtract(const Duration(minutes: 2)),
        ),
      ]);
      nearby.peerStatuses.addAll({
        'device-older': DeviceStatus.sos,
        'device-newer': DeviceStatus.sos,
        'device-middle': DeviceStatus.sos,
      });
      nearby.notifyListeners();

      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: dependencies,
            child: const SOSReceivedScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('รายละเอียดคำขอ SOS'), findsOneWidget);
      expect(find.text('QA Newer Peer'), findsOneWidget);
      expect(find.text('ขอความช่วยเหลือด่วน'), findsOneWidget);
      expect(find.text('ลำดับ 1'), findsOneWidget);
      expect(
        find.text('คำขอนี้ไม่มีข้อมูลผู้ติดต่อหรือสุขภาพแนบมา'),
        findsNothing,
      );
      expect(find.text('โหมดกู้ภัย (Rescue)'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('QA Middle Peer'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('QA Middle Peer'), findsOneWidget);
      expect(find.text('ลำดับ 2'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('QA Older Peer'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('QA Older Peer'), findsOneWidget);
      expect(find.text('ลำดับ 3'), findsOneWidget);
      expect(find.text('SYNTHETIC_PRIVATE_HEALTH_SENTINEL'), findsNothing);
      expect(find.text('คำขอที่ 1 จาก'), findsNothing);

      final scrollPosition = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      nearby.notifyListeners();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('QA Older Peer'), findsOneWidget);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        scrollPosition,
      );

      nearby.peerStatuses['device-newer'] = DeviceStatus.normal;
      nearby.peerStatuses['device-older'] = DeviceStatus.normal;
      nearby.peerStatuses['device-middle'] = DeviceStatus.normal;
      nearby.notifyListeners();
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีคำขอ SOS ที่กำลังทำงาน'), findsOneWidget);
      expect(find.text('QA Newer Peer'), findsNothing);
    },
  );

  testWidgets(
    'active Rescue shows request details and fails disclosures closed',
    (tester) async {
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(autoAcknowledge: false),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await dependencies.dispose();
      });
      await dependencies.repositories.settings.setBool('rescue_mode', true);
      await EmergencyProfileRepository(
        dependencies.database,
        dependencies.repositories.profiles,
      ).save(
        medicalConditions: 'SYNTHETIC_PRIVATE_HEALTH_SENTINEL',
        allergies: 'SYNTHETIC_PRIVATE_ALLERGY_SENTINEL',
        medications: '',
        careNotes: '',
        shareContactsOnSos: true,
        shareHealthOnSos: true,
      );
      final startedAt = DateTime(2026, 11, 3, 16, 25);
      await dependencies.repositories.sos.createIncoming(
        id: 'rescue-sos',
        ownerDeviceId: 'rescue-requester-device',
        ownerUserId: 'rescue-requester-account',
        requesterDisplayName: 'QA SOS Requester',
        message: 'ต้องการความช่วยเหลือ',
        latitude: 14.041314,
        longitude: 100.739545,
        locationAccuracy: 10,
        locationCapturedAt: startedAt,
        createdAt: startedAt,
        isActive: true,
      );
      dependencies.nearbyService.discoveredPeers.add(
        NearbyPeer(
          id: 'rescue-endpoint',
          name: 'QA SOS Requester',
          deviceId: 'rescue-requester-device',
          lastSeenAt: startedAt,
        ),
      );
      dependencies.nearbyService.peerStatuses['rescue-requester-device'] =
          DeviceStatus.sos;

      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: dependencies,
            child: const RescueScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RESCUE ACTIVE'), findsOneWidget);
      expect(find.text('1 คำขอ'), findsOneWidget);
      expect(find.text('ปิดโหมดกู้ภัย'), findsOneWidget);
      expect(find.text('ผู้ขอความช่วยเหลือ'), findsOneWidget);
      expect(find.text('ประวัติ'), findsOneWidget);
      expect(find.text('QA SOS Requester'), findsOneWidget);
      expect(find.text('ข้อมูลฉุกเฉินที่เปิดเผย'), findsOneWidget);
      expect(
        find.text('ยังไม่มีข้อมูลฉุกเฉินที่ได้รับอนุญาตให้เปิดเผย'),
        findsOneWidget,
      );
      expect(find.text('SYNTHETIC_PRIVATE_HEALTH_SENTINEL'), findsNothing);
      expect(find.text('SYNTHETIC_PRIVATE_ALLERGY_SENTINEL'), findsNothing);
      expect(
        tester.getTopLeft(find.text('RESCUE ACTIVE')).dy,
        lessThan(tester.getTopLeft(find.text('ปิดโหมดกู้ภัย')).dy),
      );
      expect(
        tester.getTopLeft(find.text('ปิดโหมดกู้ภัย')).dy,
        lessThan(tester.getTopLeft(find.text('ผู้ขอความช่วยเหลือ')).dy),
      );
      expect(
        tester.getTopLeft(find.text('นำทางไปยังตำแหน่ง')).dy,
        lessThan(tester.getTopLeft(find.text('เปิดแชท')).dy),
      );
    },
  );
}
