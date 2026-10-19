import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/profile/profile_screen.dart';
import 'package:relio_mobile/features/rescue/rescue_screen.dart';
import 'package:relio_mobile/features/settings/settings_screen.dart';

void main() {
  Future<RelioDependencies> pumpScreen(
    WidgetTester tester,
    Widget screen,
  ) async {
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await dependencies.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: RelioThemeScope(
          notifier: RelioThemeController(),
          child: RelioDependencyScope(
            dependencies: dependencies,
            child: screen,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return dependencies;
  }

  testWidgets(
    'Profile retains emergency and sensitive actions without duplicate menus',
    (tester) async {
      await pumpScreen(tester, const ProfileScreen());
      expect(find.text('ข้อมูลฉุกเฉิน'), findsOneWidget);
      expect(find.byTooltip('แก้ไขชื่อ'), findsOneWidget);
      for (final removed in [
        'แก้ไขข้อมูลสมาชิก',
        'โหมดหน่วยกู้ภัย (Rescue)',
        'ธีม',
        'การแจ้งเตือน',
        'การเชื่อมต่อ',
        'สถานะการซิงก์',
        'ความเป็นส่วนตัว',
      ]) {
        expect(find.text(removed), findsNothing);
      }
    },
  );

  testWidgets(
    'Settings keeps working notifications and Privacy without Rescue writer',
    (tester) async {
      final dependencies = await pumpScreen(tester, const SettingsScreen());
      expect(find.text('โหมดหน่วยกู้ภัย'), findsNothing);
      expect(find.text('ธีมแอป'), findsOneWidget);
      expect(find.text('การแจ้งเตือน'), findsWidgets);
      expect(find.text('แสดงเนื้อหาข้อความในการแจ้งเตือน'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('หลักการจัดการข้อมูล'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('หลักการจัดการข้อมูล'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('หลักการจัดการข้อมูล'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('ผู้ติดต่อฉุกเฉินเก็บไว้ในเครื่อง'),
        findsOneWidget,
      );
      await tester.tap(find.text('ปิด'));
      await tester.pumpAndSettle();
      expect(
        await dependencies.repositories.settings.getBool(
          'rescue_mode',
          defaultValue: false,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'Rescue activation still requires confirmation and deactivation persists',
    (tester) async {
      final dependencies = await pumpScreen(tester, const RescueScreen());
      await tester.tap(find.text('เปิดโหมดหน่วยกู้ภัย').last);
      await tester.pumpAndSettle();
      expect(find.text('เปิดโหมดหน่วยกู้ภัย?'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(
        await dependencies.repositories.settings.getBool(
          'rescue_mode',
          defaultValue: false,
        ),
        isFalse,
      );
      await tester.tap(find.text('เปิดโหมดหน่วยกู้ภัย').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('เปิดโหมดกู้ภัย'));
      await tester.pumpAndSettle();
      expect(
        await dependencies.repositories.settings.getBool(
          'rescue_mode',
          defaultValue: false,
        ),
        isTrue,
      );
      await tester.tap(find.text('ปิดโหมดกู้ภัย'));
      await tester.pumpAndSettle();
      expect(
        await dependencies.repositories.settings.getBool(
          'rescue_mode',
          defaultValue: false,
        ),
        isFalse,
      );
    },
  );

  testWidgets('Settings stays readable at narrow widths and large Thai text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final dependencies = await pumpScreen(tester, const SettingsScreen());
    for (final width in [320.0, 360.0, 393.0, 430.0]) {
      for (final scale in [1.0, 1.3, 1.6]) {
        tester.view.physicalSize = Size(width, 800);
        tester.binding.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$width dp at $scale text scale',
        );
      }
    }
    expect(
      await dependencies.repositories.settings.getBool(
        'rescue_mode',
        defaultValue: false,
      ),
      isFalse,
    );
  });
}
