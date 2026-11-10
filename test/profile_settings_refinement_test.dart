import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/developer/internal_tools_screen.dart';
import 'package:relio_mobile/features/profile/profile_screen.dart';
import 'package:relio_mobile/features/settings/connectivity_diagnostics_card.dart';
import 'package:relio_mobile/features/settings/settings_screen.dart';
import 'package:relio_mobile/features/onboarding/welcome_screen.dart';

void main() {
  Future<(RelioDependencies, GoRouter)> pumpRoutedProfile(
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
    );
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(
          path: '/internal-tools',
          builder: (_, _) => const InternalToolsScreen(),
        ),
        GoRoute(
          path: '/settings/theme',
          builder: (_, _) => const ThemeSettingsScreen(),
        ),
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('หน้าหลัก Guest')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('หน้าเข้าสู่ระบบ')),
        ),
        GoRoute(
          path: '/sos/active',
          builder: (_, _) => const Scaffold(body: Text('จัดการ SOS')),
        ),
      ],
    );
    final theme = RelioThemeController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      theme.dispose();
      await dependencies.dispose();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(
      RelioDependencyScope(
        dependencies: dependencies,
        child: RelioThemeScope(
          notifier: theme,
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (dependencies, router);
  }

  testWidgets(
    'Profile theme and Settings entries open their existing screens',
    (tester) async {
      await pumpRoutedProfile(tester);
      await tester.ensureVisible(find.text('ธีมแอป'));
      await tester.tap(find.text('ธีมแอป'));
      await tester.pumpAndSettle();
      expect(find.text('เลือกธีมที่ต้องการแสดงผล'), findsOneWidget);
      await tester.tap(find.byTooltip('ย้อนกลับ'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.ensureVisible(find.text('การตั้งค่า'));
      await tester.tap(find.text('การตั้งค่า'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
    },
  );

  testWidgets('Profile top-right settings shortcut opens Settings', (
    tester,
  ) async {
    await pumpRoutedProfile(tester);
    await tester.tap(find.byTooltip('ตั้งค่า'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('Settings keeps consumer sections and hides QA clutter', (
    tester,
  ) async {
    await pumpRoutedProfile(tester);
    tester.view.physicalSize = const Size(800, 3000);
    await tester.ensureVisible(find.text('การตั้งค่า'));
    await tester.tap(find.text('การตั้งค่า'));
    await tester.pumpAndSettle();

    for (final section in [
      'การแจ้งเตือน',
      'การจัดการข้อมูล',
      'ความเป็นส่วนตัว',
      'เกี่ยวกับแอป',
    ]) {
      expect(find.text(section), findsWidgets);
    }
    for (final internalEntry in [
      'จำลองอินเทอร์เน็ต Offline (QA)',
      'ฟีเจอร์ทดลอง (QA)',
      'ตรวจสอบอัปเดต',
      'การวินิจฉัยระบบ',
      'ตรวจสอบ Nearby (สำหรับทีมพัฒนา)',
      'ตรวจสอบ Cloud (สำหรับทีมพัฒนา)',
      'ตรวจสอบ Relay (สำหรับทีมพัฒนา)',
    ]) {
      expect(find.text(internalEntry), findsNothing);
    }
    expect(find.byType(ConnectivityDiagnosticsCard), findsNothing);
    expect(find.text('ช่วยค้นหาอุปกรณ์ผ่านรีเลย์'), findsOneWidget);
    expect(find.text('ความยินยอมตำแหน่งสดบน Nearby'), findsNothing);
    expect(find.text('หลักการจัดการข้อมูล'), findsOneWidget);
  });

  testWidgets(
    'About version gesture enables Developer Mode and reveals one Settings entry',
    (tester) async {
      await pumpRoutedProfile(tester);
      tester.view.physicalSize = const Size(800, 1400);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('การตั้งค่า'));
      await tester.tap(find.text('การตั้งค่า'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('เกี่ยวกับ RELIO'), 300);
      await tester.tap(find.text('เกี่ยวกับ RELIO'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Version 0.9.0+'), findsOneWidget);

      for (var tap = 0; tap < 7; tap++) {
        await tester.tap(
          find.byKey(const ValueKey('about-version-internal-tools')),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byType(InternalToolsScreen), findsNothing);
      expect(find.text('ตัวเลือกสำหรับนักพัฒนา'), findsOneWidget);
      await tester.tap(find.text('ตัวเลือกสำหรับนักพัฒนา'));
      await tester.pumpAndSettle();
      expect(find.byType(InternalToolsScreen), findsOneWidget);
      expect(find.text('สถานะอุปกรณ์และการเชื่อมต่อ'), findsOneWidget);
      expect(find.text('Nearby และ Relay'), findsOneWidget);
      expect(find.text('เครื่องมือทดลองและจำลอง'), findsOneWidget);
      expect(find.text('การวินิจฉัยและบันทึกเหตุการณ์'), findsOneWidget);
      await tester.tap(find.text('Nearby และ Relay'));
      await tester.pumpAndSettle();
      expect(find.text('ตรวจสอบ Nearby (สำหรับทีมพัฒนา)'), findsOneWidget);
    },
    skip: !RelioBuildInfo.developerDiagnosticsEnabled,
  );

  testWidgets(
    'notification controls keep the approved order and saved defaults',
    (tester) async {
      final (dependencies, _) = await pumpRoutedProfile(tester);
      await dependencies.repositories.settings.setBool(
        'notification_sound',
        false,
      );
      await dependencies.repositories.settings.setBool(
        'notification_vibration',
        false,
      );
      await tester.ensureVisible(find.text('การตั้งค่า'));
      await tester.tap(find.text('การตั้งค่า'));
      await tester.pumpAndSettle();

      final soundY = tester.getTopLeft(find.text('เสียงแจ้งเตือน')).dy;
      final vibrationY = tester
          .getTopLeft(find.text('สั่นเมื่อมีการแจ้งเตือน'))
          .dy;
      final previewY = tester.getTopLeft(find.text('แสดงเนื้อหาข้อความ')).dy;
      expect(soundY, lessThan(vibrationY));
      expect(vibrationY, lessThan(previewY));

      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches, hasLength(5));
      expect(switches[0].value, isTrue);
      expect(switches[1].value, isFalse);
      expect(switches[2].value, isFalse);
      expect(switches[3].value, isTrue);
      expect(switches[4].value, isFalse);
    },
  );

  testWidgets(
    'Internal Tools retains QA controls in the QA environment',
    (tester) async {
      await pumpRoutedProfile(tester);
      await tester.ensureVisible(find.text('การตั้งค่า'));
      await tester.tap(find.text('การตั้งค่า'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('เกี่ยวกับ RELIO'), 300);
      await tester.tap(find.text('เกี่ยวกับ RELIO'));
      await tester.pumpAndSettle();
      for (var tap = 0; tap < 7; tap++) {
        await tester.tap(
          find.byKey(const ValueKey('about-version-internal-tools')),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.text('ตัวเลือกสำหรับนักพัฒนา'), findsOneWidget);
      await tester.tap(find.text('ตัวเลือกสำหรับนักพัฒนา'));
      await tester.pumpAndSettle();
      expect(find.byType(InternalToolsScreen), findsOneWidget);
      await tester.tap(find.text('สถานะอุปกรณ์และการเชื่อมต่อ'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectivityDiagnosticsCard), findsOneWidget);
      expect(find.text('สถานะระบบจริง'), findsOneWidget);
      await tester.tap(find.text('สถานะอุปกรณ์และการเชื่อมต่อ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เครื่องมือทดลองและจำลอง'));
      await tester.pumpAndSettle();
      expect(find.text('จำลองอินเทอร์เน็ต Offline (QA)'), findsOneWidget);
      expect(find.text('ฟีเจอร์ทดลอง (QA)'), findsOneWidget);
      expect(find.text('ตรวจสอบอัปเดต'), findsOneWidget);
      expect(find.text('แสดงข้อมูล DEMO'), findsOneWidget);
    },
    skip: !RelioBuildInfo.isTest,
  );

  testWidgets(
    'Production About has no Internal Tools tap surface',
    (tester) async {
      await pumpRoutedProfile(tester);
      await tester.ensureVisible(find.text('การตั้งค่า'));
      await tester.tap(find.text('การตั้งค่า'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('เกี่ยวกับ RELIO'));
      await tester.tap(find.text('เกี่ยวกับ RELIO'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('about-version-internal-tools')),
        findsNothing,
      );
    },
    skip: RelioBuildInfo.developerDiagnosticsEnabled,
  );

  testWidgets(
    'Guest can cancel exit or return to Welcome without losing data',
    (tester) async {
      final (dependencies, _) = await pumpRoutedProfile(tester);
      final deviceId = await dependencies.identity.getDeviceId();
      await dependencies.repositories.settings.setValue(
        'guest_exit_probe',
        'kept',
      );

      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guest-exit-offline')));
      await tester.pumpAndSettle();
      expect(find.text('ออกจากโหมดออฟไลน์?'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('guest-exit-offline')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guest-exit-offline')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ออกจากโหมดออฟไลน์').last);
      await tester.pumpAndSettle();
      expect(
        find.text('เชื่อมต่อผู้คนใกล้กัน เพื่อความปลอดภัยของทุกคน'),
        findsOneWidget,
      );
      expect(await dependencies.identity.getDeviceId(), deviceId);
      expect(
        await dependencies.repositories.settings.getValue('guest_exit_probe'),
        'kept',
      );
      for (
        var attempt = 0;
        attempt < 8 && find.text('ใช้งานแบบออฟไลน์').evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -420));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('ใช้งานแบบออฟไลน์'));
      await tester.pumpAndSettle();
      expect(find.text('หน้าหลัก Guest'), findsOneWidget);
      expect(
        await dependencies.repositories.settings.getBool(
          'guest_mode_exited',
          defaultValue: false,
        ),
        isFalse,
      );
    },
  );

  testWidgets('Guest exit is blocked while a local SOS is active', (
    tester,
  ) async {
    final (dependencies, _) = await pumpRoutedProfile(tester);
    final deviceId = await dependencies.identity.getDeviceId();
    await dependencies.repositories.sos.createAndActivate(
      ownerDeviceId: deviceId,
      ownerUserId: '',
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guest-exit-offline')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ออกจากโหมดออฟไลน์').last);
    await tester.pumpAndSettle();
    expect(find.text('ยังมี SOS กำลังใช้งาน'), findsOneWidget);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(
      (await dependencies.repositories.sos.readActive(
        ownerDeviceId: deviceId,
      ))?.isActive,
      isTrue,
    );
  });

  testWidgets('Guest Login CTA opens the existing Login route', (tester) async {
    await pumpRoutedProfile(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guest-login')));
    await tester.pumpAndSettle();
    expect(find.text('หน้าเข้าสู่ระบบ'), findsOneWidget);
  });
}
