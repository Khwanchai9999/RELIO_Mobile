import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:relio_mobile/app/theme/relio_colors.dart';
import 'package:relio_mobile/core/location/nearby_map_calculations.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/nearby/nearby_map_canvas.dart';
import 'package:relio_mobile/features/nearby/nearby_offline_map.dart';

void main() {
  test('offline area stays bounded around its requested center', () {
    final plan = NearbyOfflineMapPlan.around(const LatLng(13.75, 100.5));
    expect(plan, isNotNull);
    expect(plan!.bounds.northeast.latitude, greaterThan(13.75));
    expect(plan.bounds.southwest.latitude, lessThan(13.75));
    expect(plan.bounds.northeast.longitude, greaterThan(100.5));
    expect(plan.bounds.southwest.longitude, lessThan(100.5));
    expect(NearbyOfflineMapPlan.around(const LatLng(89, 0)), isNull);
  });

  test('offline downloads are enabled only for the approved HTTPS host', () {
    expect(
      supportsNearbyOfflineStyle(
        'https://tiles.openfreemap.org/styles/liberty',
      ),
      isTrue,
    );
    expect(
      supportsNearbyOfflineStyle('http://tiles.openfreemap.org/styles/liberty'),
      isFalse,
    );
    expect(
      supportsNearbyOfflineStyle(
        'https://tile.openstreetmap.org/styles/liberty',
      ),
      isFalse,
    );
    expect(
      supportsNearbyOfflineStyle(
        'https://tiles.openfreemap.org:444/styles/liberty',
      ),
      isFalse,
    );
  });

  test('map marker colors keep emergency precedence explicit', () {
    expect(nearbyMapStatusColor(DeviceStatus.normal), const Color(0xFF16A34A));
    expect(nearbyMapStatusColor(DeviceStatus.sos), const Color(0xFFEF334D));
    expect(nearbyMapStatusColor(DeviceStatus.rescue), const Color(0xFF2563EB));
    expect(nearbyMapStatusColor(DeviceStatus.offline), RelioColors.muted);
    expect(
      NearbyMapCalculations.validCompassHeading(null, accuracyDegrees: 10),
      isNull,
    );
    expect(
      NearbyMapCalculations.validCompassHeading(
        double.nan,
        accuracyDegrees: 10,
      ),
      isNull,
    );
    expect(
      NearbyMapCalculations.validCompassHeading(-1, accuracyDegrees: 10),
      isNull,
    );
    expect(
      NearbyMapCalculations.validCompassHeading(361, accuracyDegrees: 10),
      isNull,
    );
    expect(
      NearbyMapCalculations.validCompassHeading(180, accuracyDegrees: null),
      180,
    );
    expect(
      NearbyMapCalculations.validCompassHeading(180, accuracyDegrees: 60),
      isNull,
    );
    expect(
      NearbyMapCalculations.validCompassHeading(360, accuracyDegrees: 10),
      0,
    );
    expect(
      NearbyMapCalculations.validCompassHeading(135, accuracyDegrees: 10),
      135,
    );
    expect(nearbyOfflineMapMaxTiles, 3000);
    expect(nearbyOfflineMapMaxBytes, 50 * 1024 * 1024);
    expect(nearbyOfflineMapMaxZoom, 15);
  });

  testWidgets(
    'manager confirms download and deletes only the selected region',
    (tester) async {
      final store = _FakeOfflineMapStore();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NearbyOfflineMapManager(
              center: const LatLng(13.75, 100.5),
              styleUrl: 'https://tiles.openfreemap.org/styles/liberty',
              store: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีแผนที่ออฟไลน์'), findsOneWidget);

      await tester.tap(find.text('ดาวน์โหลดบริเวณนี้ · 5 กม.'));
      await tester.pumpAndSettle();
      expect(find.text('ดาวน์โหลดแผนที่ออฟไลน์?'), findsOneWidget);
      await tester.tap(find.text('ดาวน์โหลด'));
      await tester.pumpAndSettle();
      expect(store.downloadCalls, 1);
      expect(find.text('ดาวน์โหลดแผนที่ออฟไลน์แล้ว'), findsOneWidget);
      expect(find.text('ตัวอย่างพื้นที่ A'), findsOneWidget);

      await tester.tap(find.byTooltip('ลบ ตัวอย่างพื้นที่ A'));
      await tester.pumpAndSettle();
      expect(find.text('ลบแผนที่ออฟไลน์นี้?'), findsOneWidget);
      await tester.tap(find.text('ลบแผนที่'));
      await tester.pumpAndSettle();
      expect(store.deletedIds, [9]);
      expect(find.text('ยังไม่มีแผนที่ออฟไลน์'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manager blocks unapproved map providers and invalid centers', (
    tester,
  ) async {
    final store = _FakeOfflineMapStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyOfflineMapManager(
            center: null,
            styleUrl: 'https://tiles.example.invalid/style.json',
            store: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final downloadButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('ดาวน์โหลดบริเวณนี้ · 5 กม.'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(downloadButton.onPressed, isNull);
    expect(
      find.textContaining('ยังไม่รองรับการดาวน์โหลดออฟไลน์'),
      findsOneWidget,
    );
    expect(store.downloadCalls, 0);
  });
}

class _FakeOfflineMapStore implements NearbyOfflineMapStore {
  final regions = <NearbyOfflineMapRegion>[];
  final deletedIds = <int>[];
  int downloadCalls = 0;

  @override
  Future<List<NearbyOfflineMapRegion>> listRegions() async => [...regions];

  @override
  Future<NearbyOfflineMapRegion> download({
    required String styleUrl,
    required NearbyOfflineMapPlan plan,
    required ValueChanged<NearbyOfflineMapProgress> onProgress,
  }) async {
    downloadCalls++;
    onProgress(const NearbyOfflineMapProgress(fraction: 0.6));
    onProgress(const NearbyOfflineMapProgress(fraction: 1, complete: true));
    const region = NearbyOfflineMapRegion(
      id: 9,
      name: 'ตัวอย่างพื้นที่ A',
      complete: true,
      progress: 1,
      sizeBytes: 1024,
    );
    regions.add(region);
    return region;
  }

  @override
  Future<void> deleteRegion(int id) async {
    deletedIds.add(id);
    regions.removeWhere((region) => region.id == id);
  }
}
