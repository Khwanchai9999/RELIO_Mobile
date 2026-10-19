import 'package:flutter/services.dart';

class EmergencyDialer {
  const EmergencyDialer();

  static const _channel = MethodChannel('relio/emergency_dialer');

  Future<void> open(String phone) async {
    await _channel.invokeMethod<void>('openDialer', {'phone': phone});
  }
}
