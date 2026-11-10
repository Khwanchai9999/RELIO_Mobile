import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/feature_flags/feature_flags.dart';
import 'package:relio_mobile/core/nearby/nearby_readiness.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/nearby/nearby_screen.dart';

const _ready = NearbyReadiness(
  policy: NearbyPermissionPolicy(34),
  legacyPermissionsGranted: true,
  bluetoothAvailable: true,
  bluetoothEnabled: true,
  wifiAvailable: true,
  wifiEnabled: true,
  playServicesStatus: 'available',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Nearby DEMO state gates fixtures, counts, and status filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final database = AppDatabase.memory();
    final flags = FeatureFlagController(
      repository: FeatureFlagRepository(RelioSettingsRepository(database)),
      allowLocalOverrides: true,
    );
    await flags.initialize();
    await flags.setOverride(RelioFeatureFlag.nearbyMapUi, false);

    final transport = MockNearbyTransport(autoAcknowledge: false);
    final dependencies = RelioDependencies(
      database: database,
      transport: transport,
      featureFlags: flags,
    );
    await dependencies.repositories.settings.setBool(
      'nearby_live_location_enabled',
      false,
    );
    await dependencies.internalExperience.initialize();
    await dependencies.internalExperience.setDeveloperMode(true);
    await dependencies.nearbyService.initialize();
    dependencies.nearbyService.updateReadiness(_ready);
    dependencies.nearbyService.discoveredPeers.addAll(const [
      NearbyPeer(
        id: 'real-sos-endpoint',
        name: 'Real SOS peer',
        deviceId: 'real-sos',
      ),
      NearbyPeer(
        id: 'real-rescue-endpoint',
        name: 'Real Rescue peer',
        deviceId: 'real-rescue',
      ),
    ]);
    dependencies.nearbyService.peerStatuses
      ..['real-sos'] = DeviceStatus.sos
      ..['real-rescue'] = DeviceStatus.rescue;

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await dependencies.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RelioDependencyScope(
          dependencies: dependencies,
          child: const NearbyScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(dependencies.internalExperience.demoEnabled, isFalse);
    expect(find.text('ทั้งหมด (2)'), findsOneWidget);
    expect(find.text('SOS (1)'), findsOneWidget);
    expect(find.text('Rescue (1)'), findsOneWidget);
    await _scrollListToEnd(tester);
    expect(find.text('ข้อมูลตัวอย่าง'), findsNothing);
    expect(
      find.text('ข้อมูล DEMO แยกจากอุปกรณ์จริงและไม่แสดงเป็น marker'),
      findsNothing,
    );
    expect(find.text('เครื่องมือ QA / Diagnostics'), findsNothing);
    expect(find.text('Bluetooth Classic QA ทำงานอยู่'), findsNothing);
    expect(find.text('สมชาย ใจดี'), findsNothing);
    expect(find.text('ทีมกู้ภัย A'), findsNothing);
    expect(find.text('Real SOS peer'), findsOneWidget);
    expect(find.text('Real Rescue peer'), findsOneWidget);

    await tester.tap(find.byTooltip('ย่อแผงควบคุม'));
    await tester.pump();
    expect(find.text('อุปกรณ์ใกล้เคียง • 0 เครื่อง • SOS 1'), findsOneWidget);
    await tester.tap(find.byTooltip('ขยายแผงควบคุม'));
    await tester.pump();

    await dependencies.internalExperience.setDemoEnabled(true);
    await tester.pump();
    expect(find.text('ทั้งหมด (7)'), findsOneWidget);
    expect(find.text('SOS (3)'), findsOneWidget);
    expect(find.text('Rescue (2)'), findsOneWidget);
    expect(find.text('สมชาย ใจดี'), findsOneWidget);
    expect(find.text('ทีมกู้ภัย A'), findsOneWidget);
    await _scrollListToEnd(tester);
    expect(find.text('ข้อมูลตัวอย่าง'), findsOneWidget);
    expect(
      find.text('ข้อมูล DEMO แยกจากอุปกรณ์จริงและไม่แสดงเป็น marker'),
      findsOneWidget,
    );
    expect(find.text('เครื่องมือ QA / Diagnostics'), findsNothing);
    await tester.tap(find.byTooltip('ย่อแผงควบคุม'));
    await tester.pump();
    expect(find.text('อุปกรณ์ใกล้เคียง • 0 เครื่อง • SOS 3'), findsOneWidget);
    await tester.tap(find.byTooltip('ขยายแผงควบคุม'));
    await tester.pump();

    await dependencies.internalExperience.setDemoEnabled(false);
    await tester.pump();
    expect(find.text('ทั้งหมด (2)'), findsOneWidget);
    expect(find.text('SOS (1)'), findsOneWidget);
    expect(find.text('Rescue (1)'), findsOneWidget);
    expect(find.text('สมชาย ใจดี'), findsNothing);
    expect(find.text('ทีมกู้ภัย A'), findsNothing);
    expect(find.text('Real SOS peer'), findsOneWidget);
    expect(find.text('Real Rescue peer'), findsOneWidget);
    await _scrollListToEnd(tester);
    expect(find.text('ข้อมูลตัวอย่าง'), findsNothing);
    expect(
      find.text('ข้อมูล DEMO แยกจากอุปกรณ์จริงและไม่แสดงเป็น marker'),
      findsNothing,
    );
    expect(find.text('เครื่องมือ QA / Diagnostics'), findsNothing);
    await dependencies.internalExperience.setDemoEnabled(true);
    await tester.pump();
    expect(find.text('ทั้งหมด (7)'), findsOneWidget);
    expect(find.text('สมชาย ใจดี'), findsOneWidget);
    await tester.tap(find.text('SOS (3)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Real SOS peer'), findsOneWidget);
    expect(find.text('สมชาย ใจดี'), findsOneWidget);
    expect(find.text('ทีมกู้ภัย A'), findsNothing);

    await tester.tap(find.text('Rescue (2)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Real Rescue peer'), findsOneWidget);
    expect(find.text('ทีมกู้ภัย A'), findsOneWidget);
    expect(find.text('สมชาย ใจดี'), findsNothing);

    await dependencies.internalExperience.setDemoEnabled(false);
    await tester.pump();
    expect(find.text('Real Rescue peer'), findsOneWidget);
    expect(find.text('ทีมกู้ภัย A'), findsNothing);
    expect(tester.takeException(), isNull);

    await dependencies.internalExperience.setDeveloperMode(false);
    await tester.pump();
    expect(dependencies.internalExperience.demoEnabled, isFalse);
    expect(find.text('ทั้งหมด (2)'), findsOneWidget);
    await tester.tap(find.text('ทั้งหมด (2)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Real SOS peer'), findsOneWidget);
    expect(find.text('Real Rescue peer'), findsOneWidget);
    await _scrollListToEnd(tester);
    expect(find.text('ข้อมูลตัวอย่าง'), findsNothing);
    expect(find.text('เครื่องมือ QA / Diagnostics'), findsNothing);
  });
}

Future<void> _scrollListToEnd(WidgetTester tester) async {
  final list = find.byType(ListView).last;
  await tester.drag(list, const Offset(0, -1200));
  await tester.pump(const Duration(milliseconds: 400));
}
