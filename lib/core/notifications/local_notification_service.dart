import 'dart:async';

import 'package:flutter/services.dart';

// แยกสัญญาการแจ้งเตือนออกจาก Android implementation เพื่อให้ทดสอบได้
// เนื้อหา notification ต้องผ่านการกรองก่อนแสดงบน lock screen
abstract interface class LocalNotificationSink {
  Stream<String> get tappedRoutes;
  Future<String?> consumeInitialRoute();
  Future<bool> requestPermission();
  Future<bool> get notificationsAllowed;
  Future<String?> getFcmToken();
  Future<void> show({
    required String id,
    required String title,
    required String body,
    required String route,
    required bool urgent,
    required bool soundEnabled,
    required bool vibrationEnabled,
  });
}

class AndroidLocalNotificationService implements LocalNotificationSink {
  AndroidLocalNotificationService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('relio/notifications');

  final MethodChannel _channel;
  final StreamController<String> _routes = StreamController<String>.broadcast();
  bool _handlerRegistered = false;

  @override
  Stream<String> get tappedRoutes {
    _ensureHandler();
    return _routes.stream;
  }

  void _ensureHandler() {
    if (_handlerRegistered) return;
    _channel.setMethodCallHandler(_handleNativeCall);
    _handlerRegistered = true;
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'notificationTapped' && call.arguments is String) {
      _routes.add(call.arguments! as String);
    }
    return null;
  }

  @override
  Future<String?> consumeInitialRoute() async {
    _ensureHandler();
    try {
      return await _channel.invokeMethod<String>('consumeNotificationRoute');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    _ensureHandler();
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> get notificationsAllowed async {
    _ensureHandler();
    try {
      return await _channel.invokeMethod<bool>('notificationsAllowed') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String?> getFcmToken() async {
    _ensureHandler();
    try {
      return await _channel.invokeMethod<String>('getFcmToken');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
    required String route,
    required bool urgent,
    required bool soundEnabled,
    required bool vibrationEnabled,
  }) async {
    _ensureHandler();
    try {
      await _channel.invokeMethod<void>('showLocalNotification', {
        'id': id,
        'title': title,
        'body': body,
        'route': route,
        'urgent': urgent,
        'soundEnabled': soundEnabled,
        'vibrationEnabled': vibrationEnabled,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

class NoopLocalNotificationService implements LocalNotificationSink {
  const NoopLocalNotificationService();

  @override
  Stream<String> get tappedRoutes => const Stream<String>.empty();

  @override
  Future<String?> consumeInitialRoute() async => null;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<bool> get notificationsAllowed async => false;

  @override
  Future<String?> getFcmToken() async => null;

  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
    required String route,
    required bool urgent,
    required bool soundEnabled,
    required bool vibrationEnabled,
  }) async {}
}
