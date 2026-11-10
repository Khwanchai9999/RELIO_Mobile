// ตัวช่วยแสดงความใหม่ของพิกัด SOS เพื่อแยกตำแหน่งล่าสุดออกจากข้อมูลเก่าหรือไม่มีข้อมูล
import '../../core/domain/relio_entities.dart';
import '../../core/location/nearby_map_calculations.dart';

String sosLocationFreshnessLabel(RelioSosEvent? event, DateTime now) {
  if (event == null ||
      !NearbyMapCalculations.isValidPoint(event.latitude, event.longitude)) {
    return 'ยังไม่มีตำแหน่ง';
  }
  return NearbyMapCalculations.freshnessLabel(event.locationCapturedAt, now);
}
