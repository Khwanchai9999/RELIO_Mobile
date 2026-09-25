import 'package:flutter/material.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = RelioThemeController();
  // โหลด preference ก่อนสร้าง MaterialApp เพื่อไม่ให้ผู้ใช้เห็นธีมผิดชั่วคราว
  await themeController.load();
  runApp(RelioApp(themeController: themeController));
}
