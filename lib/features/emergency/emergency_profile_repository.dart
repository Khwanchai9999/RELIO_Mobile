// Repository สำหรับโปรไฟล์สุขภาพฉุกเฉินแบบ local-only พร้อมตรวจ OwnerContext ก่อนเปลี่ยนข้อมูล
import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/identity/owner_context.dart';
import '../../core/repositories/principal_profile_repository.dart';

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Emergency Profile Data
class EmergencyProfileData {
  const EmergencyProfileData({
    this.medicalConditions,
    this.allergies,
    this.medications,
    this.careNotes,
    this.shareContactsOnSos = false,
    this.shareHealthOnSos = false,
  });

  final String? medicalConditions;
  final String? allergies;
  final String? medications;
  final String? careNotes;
  final bool shareContactsOnSos;
  final bool shareHealthOnSos;

  bool get hasHealthInformation => [
    medicalConditions,
    allergies,
    medications,
    careNotes,
  ].any((value) => value?.trim().isNotEmpty == true);
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Emergency Profile Repository
class EmergencyProfileRepository {
  const EmergencyProfileRepository(this.db, this.profiles);

  final AppDatabase db;
  final PrincipalProfileRepository profiles;

  OwnerContext get _owners => profiles.owners;

  // อ่านข้อมูลสุขภาพและความตั้งใจแชร์เฉพาะ principal ปัจจุบัน การอ่านนี้ไม่ได้ส่งข้อมูลให้ผู้อื่น
  Future<EmergencyProfileData> read() async {
    final owner = _owners.capture();
    final principal = await profiles.principalFor(owner);
    _owners.requireCurrent(owner);
    final row = await (db.select(
      db.emergencyProfiles,
    )..where((item) => item.principalId.equals(principal))).getSingleOrNull();
    _owners.requireCurrent(owner);
    return row == null
        ? const EmergencyProfileData()
        : EmergencyProfileData(
            medicalConditions: row.medicalConditions,
            allergies: row.allergies,
            medications: row.medications,
            careNotes: row.careNotes,
            shareContactsOnSos: row.shareContactsOnSos,
            shareHealthOnSos: row.shareHealthOnSos,
          );
  }

  Future<void> save({
    OwnerSnapshot? expectedOwner,
    required String medicalConditions,
    required String allergies,
    required String medications,
    required String careNotes,
    required bool shareContactsOnSos,
    required bool shareHealthOnSos,
  }) async {
    final fields = <String, int>{
      'โรคประจำตัว': 500,
      'การแพ้ยา/สิ่งที่แพ้': 500,
      'ยาที่ใช้ประจำ': 500,
      'ข้อควรระวังในการช่วยเหลือ': 1000,
    };
    final values = [medicalConditions, allergies, medications, careNotes];
    for (var index = 0; index < values.length; index++) {
      if (values[index].runes.length > fields.values.elementAt(index)) {
        throw FormatException('${fields.keys.elementAt(index)} ยาวเกินกำหนด');
      }
    }

    String? clean(String value) {
      final result = value.trim();
      return result.isEmpty ? null : result;
    }

    final owner = expectedOwner ?? _owners.capture();
    final principal = await profiles.principalFor(owner);
    _owners.requireCurrent(owner);
    await db.transaction(() async {
      _owners.requireCurrent(owner);
      await db
          .into(db.emergencyProfiles)
          .insertOnConflictUpdate(
            EmergencyProfilesCompanion.insert(
              principalId: principal,
              medicalConditions: Value(clean(medicalConditions)),
              allergies: Value(clean(allergies)),
              medications: Value(clean(medications)),
              careNotes: Value(clean(careNotes)),
              shareContactsOnSos: Value(shareContactsOnSos),
              shareHealthOnSos: Value(shareHealthOnSos),
              updatedAt: DateTime.now(),
            ),
          );
      _owners.requireCurrent(owner);
    });
  }

  Future<void> delete({OwnerSnapshot? expectedOwner}) async {
    final owner = expectedOwner ?? _owners.capture();
    final principal = await profiles.principalFor(owner);
    _owners.requireCurrent(owner);
    await db.transaction(() async {
      _owners.requireCurrent(owner);
      await (db.delete(
        db.emergencyProfiles,
      )..where((row) => row.principalId.equals(principal))).go();
      _owners.requireCurrent(owner);
    });
  }
}
