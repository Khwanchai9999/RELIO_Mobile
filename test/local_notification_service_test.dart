import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/notifications/local_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'notification preferences reach Android without duplicate effects',
    () async {
      const channel = MethodChannel('relio/notifications');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await AndroidLocalNotificationService().show(
        id: 'message',
        title: 'RELIO',
        body: 'มีข้อความใหม่',
        route: '/chat/device-id',
        urgent: false,
        soundEnabled: false,
        vibrationEnabled: true,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'showLocalNotification');
      expect(calls.single.arguments, containsPair('soundEnabled', false));
      expect(calls.single.arguments, containsPair('vibrationEnabled', true));
    },
  );
}
