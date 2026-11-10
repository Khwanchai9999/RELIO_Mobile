import 'package:flutter/services.dart';

class PackagedMapService {
  static Future<String>? _preparation;
  // แชร์ Future การเตรียมแผนที่ระหว่างผู้เรียก เพื่อไม่เริ่มงานเตรียมไฟล์ซ้ำพร้อมกัน
  static Future<String> prepare() => _preparation ??= _prepare();

  static Future<String> _prepare() async {
    try {
      final path = await const MethodChannel(
        'relio/offline_map',
      ).invokeMethod<String>('prepare');
      if (path == null) throw StateError('Map preparation unavailable');
      final style = await rootBundle.loadString('assets/maps/style.json');
      return style.replaceAll(
        'asset://flutter_assets/assets/maps/',
        Uri.directory(path).toString(),
      );
    } catch (_) {
      // หากเตรียมไฟล์ไม่สำเร็จ ให้การเปิดแผนที่ครั้งถัดไปลองใหม่ได้
      _preparation = null;
      rethrow;
    }
  }
}
