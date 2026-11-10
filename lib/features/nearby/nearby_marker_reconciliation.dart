// ตรรกะเปรียบเทียบหมุดเดิมกับชุดข้อมูลใหม่ เพื่อลดการอัปเดตแผนที่ที่ไม่จำเป็น
/// เก็บ signature หลัง Native ยืนยันแล้ว เพื่อไม่สร้าง marker ใหม่เมื่อข้อมูลเท่าเดิม
/// Handle อยู่ที่ canvas; งานที่ล้มเหลวยังต้อง retry ได้โดยไม่ commit signature
class NearbyMarkerReconciliation {
  final Map<String, String> _applied = {};
  final Set<String> _wanted = {};

  void begin() => _wanted.clear();

  bool needsUpdate(String id, String signature) {
    _wanted.add(id);
    return _applied[id] != signature;
  }

  void applied(String id, String signature) => _applied[id] = signature;

  List<String> get missingIds => _applied.keys
      .where((id) => !_wanted.contains(id))
      .toList(growable: false);

  void forget(String id) => _applied.remove(id);

  void reset() {
    _applied.clear();
    _wanted.clear();
  }
}
