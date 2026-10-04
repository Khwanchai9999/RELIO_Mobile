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
}
