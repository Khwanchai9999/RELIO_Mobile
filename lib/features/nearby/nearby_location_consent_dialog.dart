// กล่องขอความยินยอมก่อนเปิดการแชร์ตำแหน่งสด เพื่อให้ผู้ใช้ตัดสินใจอย่างชัดเจน
import 'package:flutter/material.dart';

Future<bool?> showNearbyLiveLocationConsentDialog(
  BuildContext context, {
  required bool firstUse,
}) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(
      firstUse ? 'แชร์ตำแหน่งสดบน Nearby?' : 'จัดการการแชร์ตำแหน่งสด',
    ),
    content: const SingleChildScrollView(
      child: Text(
        'เมื่ออนุญาต RELIO จะรับตำแหน่งขณะเปิดแอป และแชร์เฉพาะกับอุปกรณ์ Nearby '
        'ที่เชื่อมต่อและยืนยันตัวตนแล้วเท่านั้น แอปไม่ติดตามตำแหน่งเบื้องหลังและไม่ส่งตำแหน่งนี้ไป Cloud '
        'ตำแหน่งล่าสุดที่แคชไว้จะแสดงบนเครื่องนี้เท่านั้นจนกว่าจะได้ GPS สด '
        'คุณเปลี่ยนความยินยอมได้ในตั้งค่า และควบคุมสิทธิ์ Location เพิ่มเติมได้จาก Android',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('ไม่อนุญาต'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('อนุญาต'),
      ),
    ],
  ),
);
