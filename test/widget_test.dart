import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';

Finder findGeneratedName() => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      RegExp(r'^ผู้ใช้ RELIO \d{4}$').hasMatch(widget.data ?? ''),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<RelioDependencies> pumpApp(
    WidgetTester tester, {
    bool withDemo = false,
  }) async {
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await dependencies.dispose();
    });
    // Widget flows that exercise unrelated Nearby controls start after a
    // prior explicit refusal; first-use consent has dedicated coverage.
    await dependencies.repositories.settings.setBool(
      'nearby_live_location_enabled',
      false,
    );
    await dependencies.initialize();
    if (withDemo) {
      await dependencies.internalExperience.setDeveloperMode(true);
      await dependencies.internalExperience.setDemoEnabled(true);
    }
    await tester.pumpWidget(RelioApp(dependencies: dependencies));
    return dependencies;
  }

  Future<void> settleCurrentPage(WidgetTester tester) async {
    await tester.pump();
    if (find.text('สวัสดี 👋').evaluate().isNotEmpty) {
      // Home's CHECKING indicator is intentionally an ongoing animation.
      await tester.pump(const Duration(milliseconds: 500));
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await settleCurrentPage(tester);
    await tester.tap(finder);
    await settleCurrentPage(tester);
  }

  Future<void> tapLastText(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    await tester.ensureVisible(finder);
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await settleCurrentPage(tester);
    await tester.tap(finder);
    await settleCurrentPage(tester);
  }

  Future<void> tapScrollableText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.3);
    await tester.tap(finder);
    await settleCurrentPage(tester);
  }

  testWidgets('app starts on the RELIO welcome screen', (tester) async {
    await pumpApp(tester);

    expect(find.text('RELIO'), findsOneWidget);
    expect(find.text('สื่อสารได้ แม้ไม่มีสัญญาณ'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบ'), findsOneWidget);
  });

  testWidgets('primary navigation remains usable with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    expect(findGeneratedName(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.radar_outlined));
    await settleCurrentPage(tester);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await settleCurrentPage(tester);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('SOS').first);
    await settleCurrentPage(tester);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.person_outline));
    await settleCurrentPage(tester);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
    expect(tester.takeException(), isNull);

    await tapText(tester, 'การตั้งค่า');
    expect(find.text('ตั้งค่า'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all Thai navigation labels stay visible on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');

    Future<void> expectAllLabels() async {
      final navigationBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(
        navigationBar.labelBehavior,
        NavigationDestinationLabelBehavior.alwaysShow,
      );
      for (final label in ['หน้าหลัก', 'ใกล้เคียง', 'แชท', 'SOS', 'โปรไฟล์']) {
        expect(find.text(label), findsWidgets, reason: 'missing label: $label');
      }
      expect(tester.takeException(), isNull);
    }

    await expectAllLabels();
    for (final icon in [
      Icons.radar_outlined,
      Icons.chat_bubble_outline,
      Icons.warning_amber_outlined,
      Icons.person_outline,
      Icons.home_outlined,
    ]) {
      await tester.tap(find.byIcon(icon));
      await settleCurrentPage(tester);
      await expectAllLabels();
    }
  });

  testWidgets('offline entry navigates to Home and primary navigation works', (
    tester,
  ) async {
    await pumpApp(tester);

    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    expect(findGeneratedName(), findsOneWidget);

    await tester.tap(find.text('ใกล้เคียง'));
    await settleCurrentPage(tester);
    expect(find.text('อุปกรณ์ใกล้เคียง'), findsOneWidget);
  });

  testWidgets('Nearby SOS filter changes the visible list', (tester) async {
    await pumpApp(tester, withDemo: true);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tapText(tester, 'ใกล้เคียง');

    await tapText(tester, 'SOS (2)');
    expect(find.text('สมชาย ใจดี'), findsOneWidget);
    expect(find.text('อ้อม'), findsOneWidget);
    expect(find.text('มิ้นท์'), findsNothing);
  });

  testWidgets('Nearby keeps prototype peers hidden until DEMO is enabled', (
    tester,
  ) async {
    final dependencies = await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tapText(tester, 'ใกล้เคียง');

    expect(dependencies.internalExperience.developerModeEnabled, isFalse);
    expect(dependencies.internalExperience.demoEnabled, isFalse);
    expect(find.text('DEMO'), findsNothing);
    expect(
      await dependencies.repositories.conversations.listConversations(),
      isEmpty,
    );
    expect(find.text('ตำแหน่งของฉัน'), findsNothing);
    expect(
      find.byKey(const ValueKey('nearby-local-location-status')),
      findsNothing,
    );
  });

  testWidgets('SOS request screen shows the one-tap help flow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tester.tap(find.text('SOS').first);
    await settleCurrentPage(tester);
    final form = find
        .ancestor(
          of: find.byType(TextField),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    final scrollable = find
        .descendant(of: form, matching: find.byType(Scrollable))
        .first;
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      0,
    );
    expect(find.text('ส่งสัญญาณ SOS').hitTestable(), findsOneWidget);
    expect(find.text('คำขอ SOS'), findsOneWidget);
    expect(find.text('โหมดกู้ภัย'), findsOneWidget);
    expect(find.text('สถานะ: ยังไม่ได้ส่ง SOS'), findsOneWidget);
    expect(find.text('ตำแหน่งของคุณ'), findsNothing);
    expect(find.text('อุปกรณ์ใกล้เคียง'), findsNothing);
    expect(find.textContaining('±'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one tap activates SOS without a confirmation dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tester.tap(find.text('SOS').first);
    await settleCurrentPage(tester);
    final message =
        'บาดเจ็บและต้องการความช่วยเหลือ กรุณามาที่จุดนัดพบใกล้ทางเข้าอุทยาน';
    await tester.enterText(find.byType(TextField), message);
    await tester.tap(find.text('ส่งสัญญาณ SOS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('คุณต้องการเปิดโหมด SOS หรือไม่?'), findsNothing);
    expect(find.text('SOS ACTIVE'), findsOneWidget);
    expect(find.text('ปิดโหมด SOS'), findsOneWidget);
    expect(find.text('เปิด SOS แล้ว'), findsOneWidget);
    expect(find.text('ยังไม่มีอุปกรณ์เชื่อมต่อ'), findsOneWidget);
    expect(find.text('ตำแหน่งล่าสุด'), findsOneWidget);
    expect(find.text('ยังไม่มีพิกัดที่บันทึกไว้'), findsOneWidget);
    final activeScroll = find
        .ancestor(
          of: find.text('ปิดโหมด SOS'),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    final activeScrollable = find
        .descendant(of: activeScroll, matching: find.byType(Scrollable))
        .first;
    expect(
      tester.state<ScrollableState>(activeScrollable).position.maxScrollExtent,
      0,
    );
    await tester.tap(find.text('ข้อความฉุกเฉิน'));
    await tester.pump();
    expect(find.text(message), findsWidgets);
    await tester.tap(find.text('ปิด').last);
    await tester.pump();
    await tester.tap(find.text('ปิดโหมด SOS'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('ต้องการปิดโหมด SOS หรือไม่?'), findsOneWidget);
    await tester.tap(find.text('ปิด SOS'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('สถานะ: ยังไม่ได้ส่ง SOS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('persisted local SOS can be managed after app relaunch', (
    tester,
  ) async {
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await dependencies.dispose();
    });
    await dependencies.initialize();
    await tester.pumpWidget(RelioApp(dependencies: dependencies));
    await tapText(tester, 'ใช้งานแบบออฟไลน์');

    await dependencies.repositories.sos.createAndActivate(
      ownerDeviceId: await dependencies.identity.getDeviceId(),
      ownerUserId: '',
    );
    await settleCurrentPage(tester);
    await tester.tap(find.text('SOS').first);
    await settleCurrentPage(tester);

    expect(find.text('สถานะ: ยังไม่ได้ส่ง SOS'), findsNothing);
    final manageSos = find.text('จัดการ SOS ที่เปิดอยู่');
    await tester.ensureVisible(manageSos);
    await tester.tap(manageSos);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('SOS ACTIVE'), findsOneWidget);
  });

  testWidgets('chat composer inserts a pending local message', (tester) async {
    await pumpApp(tester, withDemo: true);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tapLastText(tester, 'แชท');
    await tester.pump(const Duration(milliseconds: 500));
    final somchai = find.text('สมชาย ใจดี').last;
    await tester.ensureVisible(somchai);
    await tester.tap(somchai);
    await settleCurrentPage(tester);

    await tester.enterText(find.byType(TextField), 'ทดสอบข้อความ Nearby');
    expect(find.byTooltip('ตัวเลือกบทสนทนา'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await tester.pump(const Duration(milliseconds: 50));
    final sendButton = find.widgetWithIcon(IconButton, Icons.send_rounded);
    await tester.ensureVisible(sendButton);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'ทดสอบข้อความ Nearby',
    );
    await tester.tap(sendButton);
    await tester.pump();
    await tester.pump();
    expect(find.text('ทดสอบข้อความ Nearby'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('รอส่ง'), findsOneWidget);
  });

  testWidgets('developer diagnostics exposes mock Nearby state', (
    tester,
  ) async {
    final dependencies = await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tapText(tester, 'ใกล้เคียง');
    expect(find.text('ตรวจสอบ Nearby (สำหรับทีมพัฒนา)'), findsNothing);
    expect(find.text('เครื่องมือภายใน'), findsNothing);
    await tester.tap(find.text('โปรไฟล์').last);
    await settleCurrentPage(tester);
    await tapText(tester, 'การตั้งค่า');
    await tester.scrollUntilVisible(
      find.text('เกี่ยวกับ RELIO'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tapText(tester, 'เกี่ยวกับ RELIO');
    for (var tap = 0; tap < 7; tap++) {
      await tester.tap(
        find.byKey(const ValueKey('about-version-internal-tools')),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(dependencies.internalExperience.developerModeEnabled, isTrue);
    await tapText(tester, 'ตัวเลือกสำหรับนักพัฒนา');
    await tester.pumpAndSettle();
    expect(find.text('เครื่องมือภายใน'), findsOneWidget);
    await tapScrollableText(tester, 'Nearby และ Relay');
    await tapScrollableText(tester, 'ตรวจสอบ Nearby (สำหรับทีมพัฒนา)');

    expect(find.text('MOCK transport — developer diagnostics'), findsOneWidget);
    expect(find.text('MockNearbyTransport'), findsOneWidget);
    expect(find.text('Start Discovery'), findsOneWidget);
  });

  testWidgets('cloud diagnostics is truthful when Supabase is not configured', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tapText(tester, 'ใกล้เคียง');
    expect(find.text('ตรวจสอบ Cloud (สำหรับทีมพัฒนา)'), findsNothing);
    await tester.tap(find.text('โปรไฟล์').last);
    await settleCurrentPage(tester);
    await tapText(tester, 'การตั้งค่า');
    await tester.scrollUntilVisible(
      find.text('เกี่ยวกับ RELIO'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tapText(tester, 'เกี่ยวกับ RELIO');
    for (var tap = 0; tap < 7; tap++) {
      await tester.tap(
        find.byKey(const ValueKey('about-version-internal-tools')),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapText(tester, 'ตัวเลือกสำหรับนักพัฒนา');
    await tester.pumpAndSettle();
    expect(find.text('เครื่องมือภายใน'), findsOneWidget);
    await tapScrollableText(tester, 'การวินิจฉัยและบันทึกเหตุการณ์');
    await tapScrollableText(tester, 'ตรวจสอบ Cloud (สำหรับทีมพัฒนา)');

    expect(find.text('ยังไม่ได้ตั้งค่า Cloud'), findsOneWidget);
    expect(find.text('Guest / local-only'), findsOneWidget);
  });

  testWidgets('theme settings updates the application root immediately', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tester.tap(find.text('โปรไฟล์').last);
    await settleCurrentPage(tester);
    await tapText(tester, 'ธีมแอป');

    await tapText(tester, 'โหมดมืด');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    await tapText(tester, 'โหมดสว่าง');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );

    await tapText(tester, 'ตามการตั้งค่าเครื่อง');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });
}
