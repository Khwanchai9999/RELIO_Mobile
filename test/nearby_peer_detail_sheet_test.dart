import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/nearby/nearby_peer_detail_sheet.dart';

void main() {
  const sizes = [Size(412, 915), Size(360, 800), Size(320, 640)];

  for (final size in sizes) {
    testWidgets('peer details scroll and actions fit at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var chatTaps = 0;
      var navigateTaps = 0;
      var sheetExtent = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(bottom: 24),
              viewPadding: const EdgeInsets.only(bottom: 24),
              textScaler: TextScaler.linear(size.width == 320 ? 1.2 : 1),
            ),
            child: NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                sheetExtent = notification.extent;
                return false;
              },
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (context) => FilledButton(
                        onPressed: () => showNearbyPeerDetailSheet(
                          context: context,
                          device: _longContentPeer,
                          myLocation: _myLocation,
                          onChat: () => chatTaps++,
                          onNavigate: () => navigateTaps++,
                        ),
                        child: const Text('Open peer'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            bottomNavigationBar: const SizedBox(
              height: 72,
              child: Center(child: Text('RELIO bottom navigation')),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open peer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('RELIO H QA'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final listView = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(ListView),
      );
      final scrollable = find.descendant(
        of: listView,
        matching: find.byType(Scrollable),
      );
      expect(listView, findsOneWidget);
      expect(scrollable, findsOneWidget);
      await tester.drag(scrollable, const Offset(0, -700));
      await tester.pumpAndSettle();
      final staleWarning = find.text('ตำแหน่งเก่าอาจไม่ตรงกับตำแหน่งปัจจุบัน');
      await tester.scrollUntilVisible(
        staleWarning,
        180,
        scrollable: scrollable,
        maxScrolls: 12,
      );
      expect(staleWarning, findsOneWidget);

      final chat = find.text('แชท');
      final navigate = find.text('ดูเส้นทาง');
      await tester.scrollUntilVisible(
        chat,
        240,
        scrollable: scrollable,
        maxScrolls: 12,
      );
      await tester.scrollUntilVisible(
        navigate,
        160,
        scrollable: scrollable,
        maxScrolls: 12,
      );
      await tester.pumpAndSettle();
      expect(chat, findsOneWidget);
      expect(navigate, findsOneWidget);
      final navigationRect = tester.getRect(
        find.text('RELIO bottom navigation'),
      );
      expect(navigationRect.overlaps(tester.getRect(chat)), isFalse);
      expect(navigationRect.overlaps(tester.getRect(navigate)), isFalse);
      expect(tester.takeException(), isNull);

      final offsetBeforeScrollBack = tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels;
      final extentBeforeScrollBack = sheetExtent;
      await tester.drag(scrollable, const Offset(0, 180));
      await tester.pumpAndSettle();
      final offsetAfterScrollBack = tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels;
      expect(
        offsetAfterScrollBack < offsetBeforeScrollBack ||
            sheetExtent < extentBeforeScrollBack,
        isTrue,
      );
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        chat,
        240,
        scrollable: scrollable,
        maxScrolls: 12,
      );
      await tester.pumpAndSettle();

      await tester.tap(chat);
      await tester.pumpAndSettle();
      expect(chatTaps, 1);

      await tester.tap(find.text('Open peer'));
      await tester.pumpAndSettle();
      final secondListView = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(ListView),
      );
      final secondScrollable = find.descendant(
        of: secondListView,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        navigate,
        240,
        scrollable: secondScrollable,
        maxScrolls: 12,
      );
      await tester.pumpAndSettle();
      await tester.tap(navigate);
      await tester.pumpAndSettle();
      expect(navigateTaps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

final _myLocation = LocationData(
  latitude: 13.7563,
  longitude: 100.5018,
  capturedAt: DateTime.utc(2026, 10, 12),
);

final _longContentPeer = RelioDevice(
  id: 'peer-1',
  name: 'RELIO H QA ชื่ออุปกรณ์ทดสอบที่ยาวเพื่อทดสอบการตัดบรรทัด',
  status: DeviceStatus.normal,
  signalQuality: 0,
  isConnected: true,
  isDemo: false,
  batteryLevel: 100,
  isCharging: true,
  peerDeviceModel: 'Huawei STK-L22 Android device model information',
  locationLatitude: 13.7564,
  locationLongitude: 100.5019,
  locationCapturedAt: DateTime.utc(2026, 10, 1),
);
