// ตัวช่วยเปิดหน้าปุ่มโทรของ Android ด้วยหมายเลขที่ผู้ใช้เลือก โดยไม่โทรออกให้อัตโนมัติ
import 'package:flutter/services.dart';

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Emergency Dialer
class EmergencyDialer {
  const EmergencyDialer();

  static const _channel = MethodChannel('relio/emergency_dialer');

  Future<void> open(String phone) async {
    await _channel.invokeMethod<void>('openDialer', {'phone': phone});
  }
}
