import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/feature_flags/feature_flags.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/location/location_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/nearby/nearby_map_canvas.dart';
import 'package:relio_mobile/features/nearby/nearby_screen.dart';

void main() {
  testWidgets(
    'Nearby Map loads a permitted fresh fix without Locate or sharing',
    (tester) async {
      final database = AppDatabase.memory();
      final location = LocationData(
        latitude: 14.04,
        longitude: 100.73,
        accuracyMeters: 12,
        capturedAt: DateTime.now(),
        source: 'test-gps',
      );
      final dependencies = RelioDependencies(
        database: database,
        transport: MockNearbyTransport(autoAcknowledge: false),
        locationService: FakeLocationService(LocationResult.success(location)),
      );
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
      await tester.pump(const Duration(milliseconds: 100));

      var canvas = tester.widget<NearbyMapCanvas>(find.byType(NearbyMapCanvas));
      final locationService =
          dependencies.locationService as FakeLocationService;
      expect(canvas.myLocation, isNull);
      expect(locationService.freshLocationCalls, 0);
      expect(canvas.locationFocusRequest, 0);
      expect(
        find.byTooltip('แชร์ตำแหน่งล่าสุดกับ peer ที่เชื่อมต่อ'),
        findsNothing,
      );
      expect(find.byTooltip('ไปยังตำแหน่งของฉัน'), findsOneWidget);
      await tester.tap(find.byTooltip('ไปยังตำแหน่งของฉัน'));
      await tester.pump();
      canvas = tester.widget<NearbyMapCanvas>(find.byType(NearbyMapCanvas));
      expect(locationService.freshLocationCalls, 1);
      expect(canvas.locationFocusRequest, 1);
      expect(canvas.myLocation?.latitude, 14.04);
      expect(canvas.myLocation?.longitude, 100.73);
      expect(dependencies.nearbyService.lastSentPacket, isNull);
    },
  );

  testWidgets('map OFF renders list-first and never creates MapLibre canvas', (
    tester,
  ) async {
    final database = AppDatabase.memory();
    final flags = FeatureFlagController(
      repository: FeatureFlagRepository(RelioSettingsRepository(database)),
      allowLocalOverrides: true,
    );
    await flags.initialize();
    await flags.setOverride(RelioFeatureFlag.nearbyMapUi, false);
    final dependencies = RelioDependencies(
      database: database,
      transport: MockNearbyTransport(autoAcknowledge: false),
      featureFlags: flags,
    );
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
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(NearbyMapCanvas), findsNothing);
    expect(find.text('อุปกรณ์ใกล้เคียง'), findsWidgets);
    expect(find.text('รายการ'), findsOneWidget);
    expect(find.text('แผนที่'), findsNothing);
    expect(find.text('ค้นหาอุปกรณ์'), findsOneWidget);
    expect(
      find.byTooltip('แชร์ตำแหน่งล่าสุดกับ peer ที่เชื่อมต่อ'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
