// Repository สำหรับข้อมูลผู้ติดต่อฉุกเฉินใน SQLite โดยผูกการอ่านและแก้ไขกับเจ้าของข้อมูล
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/identity/owner_context.dart';
import '../../core/repositories/principal_profile_repository.dart';

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Emergency Contact Entry
class EmergencyContactEntry {
  const EmergencyContactEntry({
    required this.id,
    required this.name,
    required this.phone,
    this.relationship,
    this.note,
  });

  final String id;
  final String name;
  final String phone;
  final String? relationship;
  final String? note;
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Emergency Contact Repository
class EmergencyContactRepository {
  const EmergencyContactRepository(this.db, this.profiles);

  final AppDatabase db;
  final PrincipalProfileRepository profiles;

  OwnerContext get _owners => profiles.owners;

  Future<List<EmergencyContactEntry>> list() async {
    final owner = _owners.capture();
    final principal = await profiles.principalFor(owner);
    _owners.requireCurrent(owner);
    final rows =
        await (db.select(db.emergencyContacts)
              ..where((row) => row.principalId.equals(principal))
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    _owners.requireCurrent(owner);
    return rows
        .map(
          (row) => EmergencyContactEntry(
            id: row.id,
            name: row.name,
            phone: row.phone,
            relationship: row.relationship,
            note: row.note,
          ),
        )
        .toList(growable: false);
  }

  // ตรวจรูปแบบข้อมูลก่อนบันทึก และตรวจ owner ซ้ำใน transaction เพื่อไม่ให้รายชื่อข้ามบัญชี
  Future<void> save({
    String? id,
    required String name,
    required String phone,
    String? relationship,
    String? note,
  }) async {
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final cleanRelationship = relationship?.trim();
    final cleanNote = note?.trim();
    if (cleanName.isEmpty || cleanName.runes.length > 80) {
      throw const FormatException('กรุณาระบุชื่อไม่เกิน 80 ตัวอักษร');
    }
    final digits = cleanPhone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.length > 40 ||
        !RegExp(r'^\+?[0-9() .-]+$').hasMatch(cleanPhone) ||
        digits.length < 3 ||
        digits.length > 20) {
      throw const FormatException('หมายเลขโทรศัพท์ไม่ถูกต้อง');
    }
    if ((cleanRelationship?.runes.length ?? 0) > 80 ||
        (cleanNote?.runes.length ?? 0) > 500) {
      throw const FormatException('ข้อมูลยาวเกินกำหนด');
    }
    final owner = _owners.capture();
    final principal = await profiles.principalFor(owner);
    _owners.requireCurrent(owner);
    await db.transaction(() async {
      _owners.requireCurrent(owner);
      final now = DateTime.now();
      if (id == null) {
        await db
            .into(db.emergencyContacts)
            .insert(
              EmergencyContactsCompanion.insert(
                id: const Uuid().v4(),
                principalId: principal,
                name: cleanName,
                phone: cleanPhone,
                relationship: Value(
                  cleanRelationship?.isEmpty == true ? null : cleanRelationship,
                ),
                note: Value(cleanNote?.isEmpty == true ? null : cleanNote),
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        final changed =
            await (db.update(db.emergencyContacts)..where(
                  (row) =>
                      row.id.equals(id) & row.principalId.equals(principal),
                ))
                .write(
                  EmergencyContactsCompanion(
                    name: Value(cleanName),
                    phone: Value(cleanPhone),
                    relationship: Value(
                      cleanRelationship?.isEmpty == true
                          ? null
                          : cleanRelationship,
                    ),
                    note: Value(cleanNote?.isEmpty == true ? null : cleanNote),
                    updatedAt: Value(now),
                  ),
                );
        if (changed != 1) throw StateError('ไม่พบผู้ติดต่อของบัญชีนี้');
      }
      _owners.requireCurrent(owner);
    });
  }

  Future<void> delete(String id) async {
    final owner = _owners.capture();
    final principal = await profiles.principalFor(owner);
    _owners.requireCurrent(owner);
    await db.transaction(() async {
      _owners.requireCurrent(owner);
      await (db.delete(db.emergencyContacts)..where(
            (row) => row.id.equals(id) & row.principalId.equals(principal),
          ))
          .go();
      _owners.requireCurrent(owner);
    });
  }
}
