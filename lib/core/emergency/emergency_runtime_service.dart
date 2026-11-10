import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum EmergencyMode { sos, rescue, nearbyRelay }

abstract interface class EmergencyRuntimeService {
  Future<bool> start(EmergencyMode mode);
  Future<void> stop({EmergencyMode? mode});
  Future<bool> isRunning({EmergencyMode? mode});
}

// ห่อการเรียก emergency runtime ฝั่ง Android เพื่อให้ส่วนแอปและ tests ใช้ interface เดียวกัน
class AndroidEmergencyRuntimeService implements EmergencyRuntimeService {
  static const MethodChannel _channel = MethodChannel(
    'relio/emergency_runtime',
  );

  @override
  Future<bool> start(EmergencyMode mode) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('start', {'mode': mode.name}) ??
        false;
  }

  @override
  Future<void> stop({EmergencyMode? mode}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('stop', {'mode': mode?.name});
  }

  @override
  Future<bool> isRunning({EmergencyMode? mode}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('isRunning', {
          'mode': mode?.name,
        }) ??
        false;
  }
}

class FakeEmergencyRuntimeService implements EmergencyRuntimeService {
  bool running = false;
  EmergencyMode? mode;
  @override
  Future<bool> start(EmergencyMode value) async {
    mode = value;
    running = true;
    return true;
  }

  @override
  Future<void> stop({EmergencyMode? mode}) async {
    if (mode == null || this.mode == mode) {
      running = false;
      this.mode = null;
    }
  }

  @override
  Future<bool> isRunning({EmergencyMode? mode}) async =>
      running && (mode == null || this.mode == mode);
}
