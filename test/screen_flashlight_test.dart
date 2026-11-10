import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/features/flashlight/screen_flashlight_screen.dart';

void main() {
  testWidgets('starts white and alternates signal at 250 ms without a dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: ScreenFlashlightScreen()));
    await tester.pump();

    expect(find.text('แสงสีขาว'), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.white,
    );

    await tester.tap(find.text('สลับ'));
    await tester.pump();
    expect(find.text('ไฟสัญญาณ').first, findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('คำเตือน:'), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFFFF0000),
    );

    await tester.pump(const Duration(milliseconds: 249));
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFFFF0000),
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFF0000FF),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFFFF0000),
    );

    await tester.tap(find.text('สลับ'));
    await tester.pump();
    expect(find.text('แสงสีขาว'), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.white,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.white,
    );

    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFFFF0000),
    );
    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.white,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('landscape puts controls in a right-side column', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: ScreenFlashlightScreen()));
    await tester.pump();
    expect(find.text('แตะหน้าจอเพื่อสลับโหมด'), findsNothing);
    expect(find.textContaining('คำเตือน:'), findsOneWidget);
    final row = tester.widget<Row>(find.byType(Row).first);
    expect(row.children.last, isA<SafeArea>());
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('pausing the app stops the signal and restores white mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const MaterialApp(home: ScreenFlashlightScreen()));
    await tester.pump();

    await tester.tap(find.text('สลับ'));
    await tester.pump();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFFFF0000),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.white,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Colors.white,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
