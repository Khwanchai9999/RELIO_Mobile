import 'dart:async';

import 'package:relio_mobile/core/notifications/local_notification_service.dart';

class RecordingNotifications implements LocalNotificationSink {
  final shown = <({String id, String title, String body, String route})>[];
  final taps = StreamController<String>.broadcast();
  Future<void> Function(String id)? beforeShow;
  String? initialRoute;
  @override
  Stream<String> get tappedRoutes => taps.stream;
  @override
  Future<String?> consumeInitialRoute() async => initialRoute;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> get notificationsAllowed async => true;
  @override
  Future<String?> getFcmToken() async => null;
  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
    required String route,
    required bool urgent,
  }) async {
    await beforeShow?.call(id);
    shown.add((id: id, title: title, body: body, route: route));
  }
}
