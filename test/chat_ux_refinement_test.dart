import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/nearby_reachability.dart';
import 'package:relio_mobile/core/presentation/live_route_presentation.dart';
import 'package:relio_mobile/features/chat/chat_date_separator.dart';

void main() {
  group('live route subtitle presentation', () {
    test('labels direct and automatic relay routes', () {
      expect(
        const LiveRoutePresentation(kind: LiveRouteKind.direct).chatSubtitle,
        'เชื่อมต่อโดยตรง',
      );
      expect(
        const LiveRoutePresentation(
          kind: LiveRouteKind.relay,
          nextHopName: 'เครื่องกลางจริง',
          hops: 2,
        ).chatSubtitle,
        'ผ่าน เครื่องกลางจริง · 2 ทอด',
      );
      expect(
        const LiveRoutePresentation(kind: LiveRouteKind.relay).chatSubtitle,
        'ผ่านรีเลย์ · 2 ทอด',
      );
      expect(
        const LiveRoutePresentation(
          kind: LiveRouteKind.relay,
          nextHopName: 'เครื่องกลางจริง',
          hops: 2,
        ).nearbySubtitle,
        'เชื่อมต่อผ่าน เครื่องกลางจริง · 2 ทอด',
      );
    });

    test('searching and unreachable labels are distinct', () {
      expect(
        const LiveRoutePresentation(kind: LiveRouteKind.searching).chatSubtitle,
        'กำลังค้นหาเส้นทาง…',
      );
      expect(
        const LiveRoutePresentation(
          kind: LiveRouteKind.unreachable,
        ).chatSubtitle,
        'ออฟไลน์ · ไม่มีเส้นทาง',
      );
      expect(
        const LiveRoutePresentation(
          kind: LiveRouteKind.unreachable,
        ).nearbySubtitle,
        'ยังไม่สามารถเชื่อมต่อได้',
      );
    });

    test(
      'live changes resolve next hop and clear the stale relay subtitle',
      () {
        const liveRoute = NearbyReachabilityRoute(
          ['middle-device', 'destination-device'],
          'Destination',
          Duration(seconds: 20),
        );
        final relay = liveRoutePresentationFrom(
          deviceId: 'destination-device',
          activeRoutes: const [liveRoute],
          directDeviceIds: const {},
          nextHopNames: const {'middle-device': 'เครื่องกลางจริง'},
        );
        expect(relay.chatSubtitle, 'ผ่าน เครื่องกลางจริง · 2 ทอด');

        final direct = liveRoutePresentationFrom(
          deviceId: 'destination-device',
          activeRoutes: const [liveRoute],
          directDeviceIds: const {'destination-device'},
          nextHopNames: const {},
        );
        expect(direct.chatSubtitle, 'เชื่อมต่อโดยตรง');

        final expired = liveRoutePresentationFrom(
          deviceId: 'destination-device',
          activeRoutes: const [],
          directDeviceIds: const {},
          nextHopNames: const {},
        );
        expect(expired.chatSubtitle, 'ออฟไลน์ · ไม่มีเส้นทาง');
      },
    );
  });

  group('chat local date separators', () {
    final now = DateTime(2026, 11, 9, 12);

    test('formats today, yesterday and older dates in Thai Buddhist year', () {
      expect(
        formatChatDateSeparator(DateTime(2026, 11, 9, 1), now: now),
        'วันนี้ · 9 พฤศจิกายน 2569',
      );
      expect(
        formatChatDateSeparator(DateTime(2026, 11, 8, 23), now: now),
        'เมื่อวาน · 8 พฤศจิกายน 2569',
      );
      expect(
        formatChatDateSeparator(DateTime(2026, 11, 7), now: now),
        '7 พฤศจิกายน 2569',
      );
    });

    test('groups by local calendar day and avoids duplicate separators', () {
      final todayEarlier = DateTime(2026, 11, 9, 1);
      final todayLater = DateTime(2026, 11, 9, 23);
      final yesterday = DateTime(2026, 11, 8, 23, 59);
      expect(shouldShowChatDateSeparator(todayLater, todayEarlier), isFalse);
      expect(shouldShowChatDateSeparator(yesterday, todayEarlier), isTrue);
      expect(shouldShowChatDateSeparator(yesterday, null), isTrue);
      expect(shouldShowChatDateSeparator(null, yesterday), isFalse);
    });
  });
}
