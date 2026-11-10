import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/sos/sos_screens.dart';

File _materialIconsFontFile() {
  final roots = <String>[];
  final environmentRoot = Platform.environment['FLUTTER_ROOT'];
  if (environmentRoot != null && environmentRoot.isNotEmpty) {
    roots.add(environmentRoot);
  }

  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    roots.add(directory.path);
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }

  final separator = Platform.pathSeparator;
  for (final root in roots) {
    final font = File(
      [
        root,
        'bin',
        'cache',
        'artifacts',
        'material_fonts',
        'materialicons-regular.otf',
      ].join(separator),
    );
    if (font.existsSync()) return font;
  }

  throw StateError('ไม่พบ Material Icons ใน Flutter SDK');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Realme-size SOS screens render for visual review', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final iconsFont = _materialIconsFontFile();
    await tester.runAsync(() async {
      final iconBytes = await iconsFont.readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();
    });
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });

    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await dependencies.dispose();
    });
    await dependencies.initialize();
    await tester.pumpWidget(RelioApp(dependencies: dependencies));
    await tester.ensureVisible(find.text('ใช้งานแบบออฟไลน์'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ใช้งานแบบออฟไลน์'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.tap(find.text('SOS').first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('ส่งสัญญาณ SOS'), findsOneWidget);
    expect(find.text('คำขอ SOS'), findsOneWidget);
    expect(find.text('โหมดกู้ภัย'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('โหมดกู้ภัย')).dy,
      lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
    );
    await expectLater(
      find.byType(RelioShell),
      matchesGoldenFile('goldens/sos-pre-activation.png'),
    );

    await dependencies.repositories.sos.createAndActivate(
      ownerDeviceId: await dependencies.identity.getDeviceId(),
      ownerUserId: '',
      message: 'ต้องการความช่วยเหลือ กรุณามาที่จุดนัดพบ',
      latitude: 14.04055,
      longitude: 100.73988,
      locationAccuracy: 12,
      // คงอายุพิกัดของ golden ไว้ที่ 3 นาที ไม่ให้เปลี่ยนตามวันที่รัน test
      locationCapturedAt: DateTime.now().subtract(const Duration(minutes: 3)),
    );
    final sosContext = tester.element(find.byType(SOSScreen));
    GoRouter.of(sosContext).go('/sos/active');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SOS ACTIVE'), findsOneWidget);
    expect(find.text('เปิด SOS แล้ว'), findsOneWidget);
    expect(find.text('ตำแหน่งล่าสุด'), findsOneWidget);
    expect(find.text('ข้อความฉุกเฉิน'), findsOneWidget);
    expect(find.text('ปิดโหมด SOS'), findsOneWidget);
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
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(RelioShell),
      matchesGoldenFile('goldens/sos-active.png'),
    );
  });
}
