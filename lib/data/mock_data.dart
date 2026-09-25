import 'models/prototype_models.dart';

abstract final class RelioMockData {
  static const devices = [
    RelioDevice(
      id: 'somchai',
      name: 'สมชาย ใจดี',
      status: DeviceStatus.sos,
      distanceMetersApprox: 12,
      signalQuality: 4,
    ),
    RelioDevice(
      id: 'rescue-team-a',
      name: 'ทีมกู้ภัย A',
      status: DeviceStatus.rescue,
      distanceMetersApprox: 28,
      signalQuality: 4,
    ),
    RelioDevice(
      id: 'mint',
      name: 'มิ้นท์',
      status: DeviceStatus.normal,
      distanceMetersApprox: 45,
      signalQuality: 3,
    ),
    RelioDevice(
      id: 'james',
      name: 'James',
      status: DeviceStatus.offline,
      distanceMetersApprox: 60,
      signalQuality: 2,
      isConnected: false,
    ),
    RelioDevice(
      id: 'aom',
      name: 'อ้อม',
      status: DeviceStatus.sos,
      distanceMetersApprox: 78,
      signalQuality: 2,
    ),
  ];

  static const chats = [
    RelioChatPreview(
      id: 'rescue-team-a',
      name: 'ทีมกู้ภัย A',
      message: 'กำลังเดินทางไปยังจุดของคุณ',
      time: '10:24',
      status: DeviceStatus.rescue,
      unread: 1,
    ),
    RelioChatPreview(
      id: 'somchai',
      name: 'สมชาย ใจดี',
      message: 'ผมอยู่ที่จุดนัดพบแล้ว',
      time: '10:20',
      status: DeviceStatus.sos,
      unread: 0,
    ),
    RelioChatPreview(
      id: 'mint',
      name: 'มิ้นท์',
      message: 'รับทราบ เดี๋ยวช่วยประสานงานให้',
      time: '09:52',
      status: DeviceStatus.normal,
      unread: 0,
    ),
  ];

  static const initialMessages = [
    RelioMessage(
      id: 'system',
      text: 'เริ่มการสนทนา Nearby',
      time: '',
      outgoing: false,
      type: MessageType.text,
    ),
    RelioMessage(
      id: 'm1',
      text: 'สวัสดีครับ ผมอยู่จุดเกิดเหตุ มีผู้บาดเจ็บครับ',
      time: '10:20',
      outgoing: false,
      type: MessageType.text,
    ),
    RelioMessage(
      id: 'm2',
      text: 'รับทราบครับ ตอนนี้ปลอดภัยไหม?',
      time: '10:21',
      outgoing: true,
      type: MessageType.text,
      status: DeliveryStatus.nearbySent,
    ),
    RelioMessage(
      id: 'm3',
      text: '13.7563, 100.5018',
      time: '10:22',
      outgoing: false,
      type: MessageType.location,
    ),
    RelioMessage(
      id: 'm4',
      text: 'กำลังเดินทางไปครับ อีกประมาณ 10 นาที',
      time: '10:24',
      outgoing: true,
      type: MessageType.text,
      status: DeliveryStatus.delivered,
    ),
  ];
}
