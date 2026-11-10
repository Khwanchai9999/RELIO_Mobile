// ตัวช่วยแปลงข้อความพิกัดที่บันทึกไว้เป็นปลายทางนำทาง โดยไม่สร้างข้อความหรือขอตำแหน่งใหม่
import '../../core/location/nearby_map_calculations.dart';
import '../../data/models/prototype_models.dart';

// เปิดแผนที่จากพิกัดและเวลาที่บันทึกในข้อความ โดยไม่ขอตำแหน่ง GPS ใหม่
Uri? chatSharedLocationUri(RelioMessage message) {
  if (message.type != MessageType.location ||
      !NearbyMapCalculations.isValidPoint(
        message.latitude,
        message.longitude,
      )) {
    return null;
  }
  return Uri(
    path: '/nearby',
    queryParameters: {
      'lat': message.latitude!.toString(),
      'lon': message.longitude!.toString(),
      'shared': '1',
      if (message.createdAt != null)
        'capturedAt': '${message.createdAt!.millisecondsSinceEpoch}',
    },
  );
}
