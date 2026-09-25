import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpApp(WidgetTester tester) async {
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
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapLastText(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('app starts on the RELIO welcome screen', (tester) async {
    await pumpApp(tester);

    expect(find.text('RELIO'), findsOneWidget);
    expect(find.text('สื่อสารได้ แม้ไม่มีสัญญาณ'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบ'), findsOneWidget);
  });

  testWidgets('offline entry navigates to Home and primary navigation works', (
    tester,
  ) async {
    await pumpApp(tester);

    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    expect(find.text('มินนี่'), findsOneWidget);

    await tester.tap(find.text('ใกล้เคียง'));
    await tester.pumpAndSettle();
    expect(find.text('อุปกรณ์ใกล้เคียง'), findsOneWidget);
  });

  testWidgets('Nearby SOS filter changes the visible list', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tapText(tester, 'ใกล้เคียง');

    await tapText(tester, 'SOS (2)');
    expect(find.text('สมชาย ใจดี'), findsOneWidget);
    expect(find.text('อ้อม'), findsOneWidget);
    expect(find.text('มิ้นท์'), findsNothing);
  });

  testWidgets('SOS confirmation opens the active state', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tester.tap(find.text('SOS').first);
    await tester.pumpAndSettle();
    await tapText(tester, 'เปิดโหมด SOS');
    expect(find.text('คุณต้องการเปิดโหมด SOS หรือไม่?'), findsOneWidget);

    await tester.tap(find.text('เปิด SOS'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('SOS ACTIVE'), findsOneWidget);
    expect(find.text('ปิดโหมด SOS'), findsOneWidget);
  });

  testWidgets('chat composer inserts a pending local message', (tester) async {
    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tapLastText(tester, 'แชท');
    await tester.pump(const Duration(milliseconds: 500));
    final somchai = find.text('สมชาย ใจดี').last;
    await tester.ensureVisible(somchai);
    await tester.tap(somchai);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ทดสอบข้อความ Nearby');
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
    expect(find.text('ส่งแล้ว'), findsAtLeastNWidgets(2));
  });

  testWidgets('developer diagnostics exposes mock Nearby state', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tester.tap(find.text('โปรไฟล์').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ตั้งค่า'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tapText(tester, 'Nearby Diagnostics');

    expect(find.text('Development-only screen'), findsOneWidget);
    expect(find.text('MockNearbyTransport'), findsOneWidget);
    expect(find.text('Start Discovery'), findsOneWidget);
  });

  testWidgets('cloud diagnostics is truthful when Supabase is not configured', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tester.tap(find.text('โปรไฟล์').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ตั้งค่า'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tapText(tester, 'Cloud Diagnostics');

    expect(find.text('ยังไม่ได้ตั้งค่า Cloud'), findsOneWidget);
    expect(find.text('Guest / local-only'), findsOneWidget);
  });

  testWidgets('theme settings updates the application root immediately', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapText(tester, 'ใช้งานแบบออฟไลน์');
    await tester.tap(find.text('โปรไฟล์').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ตั้งค่า'));
    await tester.pumpAndSettle();
    await tapText(tester, 'ธีม');

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

    await tapText(tester, 'ตามระบบ');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });
}
