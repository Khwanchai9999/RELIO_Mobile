import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/nearby/nearby_route_preview_card.dart';

void main() {
  testWidgets('shows straight-line route summary and stale peer freshness', (
    tester,
  ) async {
    final now = DateTime.now();
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              NearbyRoutePreviewCard(
                peer: RelioDevice(
                  id: 'canonical-peer',
                  name: 'RELIO Samsung QA',
                  status: DeviceStatus.normal,
                  signalQuality: 0,
                  isDemo: false,
                  locationLatitude: 0,
                  locationLongitude: 0.01,
                  locationCapturedAt: now.subtract(const Duration(minutes: 8)),
                ),
                myLocation: LocationData(
                  latitude: 0,
                  longitude: 0,
                  capturedAt: DateTime.now(),
                ),
                onClose: () => closed = true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('ดูเส้นทาง • RELIO Samsung QA'), findsOneWidget);
    expect(find.textContaining('1.1 กม.'), findsOneWidget);
    expect(find.textContaining('ประมาณ ตะวันออก'), findsOneWidget);
    expect(find.textContaining('⚠ อัปเดต'), findsOneWidget);
    expect(find.text('เส้นตรงโดยประมาณ ไม่ใช่เส้นทางถนน'), findsOneWidget);
    await tester.tap(find.byTooltip('ปิดดูเส้นทาง'));
    expect(closed, isTrue);
  });

  testWidgets(
    'without local location shows peer freshness but no fake distance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                NearbyRoutePreviewCard(
                  peer: RelioDevice(
                    id: 'canonical-peer',
                    name: 'RELIO peer',
                    status: DeviceStatus.normal,
                    signalQuality: 0,
                    isDemo: false,
                    locationLatitude: 13.0,
                    locationLongitude: 100.0,
                    locationCapturedAt: DateTime.now(),
                  ),
                  myLocation: null,
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(
        find.textContaining('ตำแหน่งเครื่องนี้ยังไม่พร้อม'),
        findsOneWidget,
      );
      expect(find.textContaining('ไม่ทราบระยะ'), findsNothing);
      expect(find.text('เส้นตรงโดยประมาณ ไม่ใช่เส้นทางถนน'), findsNothing);
    },
  );
}
