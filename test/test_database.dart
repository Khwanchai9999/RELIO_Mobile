import 'package:drift/drift.dart';

import 'package:relio_mobile/core/database/app_database.dart';

AppDatabase createTestDatabase() {
  final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  // แต่ละ test ใช้ in-memory Database แยกกันจริง จึงปิด warning เฉพาะช่วงสร้าง
  // instance นี้; production ยังใช้ค่า Drift default และไม่ถูกกลบ warning
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  try {
    return AppDatabase.memory();
  } finally {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
  }
}
