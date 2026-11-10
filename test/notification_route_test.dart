import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

import 'support/recording_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final cold in [true, false]) {
    testWidgets('notification tap opens exact stored chat coldStart=$cold', (
      tester,
    ) async {
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(),
        useMockTransport: true,
        androidPlatformOverride: true,
        localNotificationSink: RecordingNotifications()
          ..initialRoute = cold ? '/chat/persistent-room' : null,
      );
      addTearDown(dependencies.dispose);
      final notifications =
          dependencies.localNotificationService as RecordingNotifications;
      addTearDown(notifications.taps.close);
      await dependencies.repositories.conversations.ensureConversation(
        id: 'persistent-room',
        participantId: 'peer-device',
        displayName: 'สมชายจากห้องเดิม',
        participantStatus: DeviceStatus.offline,
      );
      await dependencies.initialize();
      await tester.pumpWidget(RelioApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      if (!cold) {
        notifications.taps.add('/chat/persistent-room');
        await tester.pumpAndSettle();
      }
      expect(
        find.text('สมชายจากห้องเดิม'),
        findsOneWidget,
        reason:
            'route=${dependencies.nearbyService.screenRoute}; active=${dependencies.nearbyService.activeConversationId}',
      );
      expect(
        dependencies.nearbyService.activeConversationId,
        'persistent-room',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final cold in [true, false]) {
    testWidgets('SOS notification opens its exact event coldStart=$cold', (
      tester,
    ) async {
      const eventId = '11111111-2222-4333-8444-555555555555';
      const deviceId = 'stable-sender-device';
      final route = Uri(
        path: '/rescue/request/$deviceId',
        queryParameters: {'eventId': eventId},
      ).toString();
      final notifications = RecordingNotifications()
        ..initialRoute = cold ? route : null;
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(),
        useMockTransport: true,
        androidPlatformOverride: true,
        localNotificationSink: notifications,
      );
      addTearDown(dependencies.dispose);
      addTearDown(notifications.taps.close);
      await dependencies.initialize();
      await dependencies.repositories.sos.createIncoming(
        id: eventId,
        ownerDeviceId: deviceId,
        ownerUserId: 'qa-owner',
        message: 'exact event body',
        createdAt: DateTime.utc(2026, 11, 2),
        isActive: false,
      );
      await tester.pumpWidget(RelioApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      if (!cold) {
        notifications.taps.add(route);
        await tester.pumpAndSettle();
      }
      expect(find.text('คำขอ SOS สิ้นสุดแล้ว'), findsOneWidget);
      expect(find.text('exact event body'), findsOneWidget);
      expect(find.text('ไม่พบคำขอ SOS นี้ในเครื่อง'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
