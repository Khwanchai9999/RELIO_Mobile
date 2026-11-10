import 'package:flutter/material.dart';
import '../../core/presentation/peer_connection_presence.dart';

enum DeviceStatus { normal, sos, rescue, offline }

enum PeerPresence {
  demo,
  discovered,
  connecting,
  connected,
  disconnected,
  failed,
  stale,
}

extension DeviceStatusX on DeviceStatus {
  String get label => switch (this) {
    DeviceStatus.normal => 'ปกติ',
    DeviceStatus.sos => 'SOS',
    DeviceStatus.rescue => 'Rescue',
    DeviceStatus.offline => 'ออฟไลน์',
  };

  Color get color => switch (this) {
    DeviceStatus.normal => const Color(0xFF14B8A6),
    DeviceStatus.sos => const Color(0xFFEF4444),
    DeviceStatus.rescue => const Color(0xFF3B82F6),
    DeviceStatus.offline => const Color(0xFF94A3B8),
  };
}

class RelioDevice {
  const RelioDevice({
    required this.id,
    required this.name,
    required this.status,
    this.distanceMetersApprox,
    required this.signalQuality,
    this.isConnected = true,
    this.isDemo = true,
    this.presence = PeerPresence.demo,
    this.reportedConnectionPresence,
    this.lastSeenAt,
    this.batteryLevel,
    this.isCharging,
    this.peerDeviceModel,
    this.locationLatitude,
    this.locationLongitude,
    this.locationAccuracyMeters,
    this.locationCapturedAt,
    this.avatarPath,
  });

  final String id;
  final String name;
  final DeviceStatus status;

  /// Nearby Connections does not provide a trustworthy physical distance.
  /// This value is optional and is only populated by explicit mock data.
  final int? distanceMetersApprox;
  final int signalQuality;
  final bool isConnected;
  final bool isDemo;
  final PeerPresence presence;
  final PeerConnectionPresence? reportedConnectionPresence;
  final DateTime? lastSeenAt;
  final int? batteryLevel;
  final bool? isCharging;
  final String? peerDeviceModel;
  final double? locationLatitude;
  final double? locationLongitude;
  final double? locationAccuracyMeters;
  final DateTime? locationCapturedAt;
  final String? avatarPath;

  PeerConnectionPresence get connectionPresence =>
      reportedConnectionPresence ??
      switch (presence) {
        PeerPresence.connected => PeerConnectionPresence.online,
        PeerPresence.discovered ||
        PeerPresence.disconnected ||
        PeerPresence.failed ||
        PeerPresence.stale => PeerConnectionPresence.offline,
        PeerPresence.demo ||
        PeerPresence.connecting => PeerConnectionPresence.unknown,
      };

  String get approximateDistance => distanceMetersApprox == null
      ? 'อยู่ใกล้เคียง'
      : '≈ $distanceMetersApprox ม.';
}

class RelioChatPreview {
  const RelioChatPreview({
    required this.id,
    required this.name,
    required this.message,
    required this.time,
    required this.status,
    required this.unread,
    this.isDemo = false,
    this.identityKey = '',
    this.presence = PeerConnectionPresence.unknown,
    this.avatarPath,
  });

  final String id;
  final String name;
  final String message;
  final String time;
  final DeviceStatus status;
  final int unread;
  final bool isDemo;
  final String identityKey;
  final PeerConnectionPresence presence;
  final String? avatarPath;
}

enum DeliveryStatus { pending, nearbySent, delivered, synced, failed }

extension DeliveryStatusX on DeliveryStatus {
  String get label => switch (this) {
    DeliveryStatus.pending => 'ค้างส่ง',
    DeliveryStatus.nearbySent => 'ส่งผ่าน Nearby แล้ว',
    DeliveryStatus.delivered => 'ส่งแล้ว',
    DeliveryStatus.synced => 'ซิงก์แล้ว',
    DeliveryStatus.failed => 'ส่งไม่สำเร็จ',
  };

  Color get color => switch (this) {
    DeliveryStatus.pending => const Color(0xFFF59E0B),
    DeliveryStatus.nearbySent => const Color(0xFF14B8A6),
    DeliveryStatus.delivered => const Color(0xFF3B82F6),
    DeliveryStatus.synced => const Color(0xFF22C55E),
    DeliveryStatus.failed => const Color(0xFFEF4444),
  };
}

enum MessageType { text, image, video, location, system }

class RelioMessage {
  const RelioMessage({
    required this.id,
    required this.text,
    required this.time,
    required this.outgoing,
    required this.type,
    this.status,
    this.conversationId,
    this.senderId,
    this.senderDeviceId,
    this.createdAt,
    this.localFilePath,
    this.latitude,
    this.longitude,
    this.nearbyMessageId,
    this.cloudSyncStatus = 'notQueued',
    this.readAt,
  });

  final String id;
  final String text;
  final String time;
  final bool outgoing;
  final MessageType type;
  final DeliveryStatus? status;
  final String? conversationId;
  final String? senderId;
  final String? senderDeviceId;
  final DateTime? createdAt;
  final String? localFilePath;
  final double? latitude;
  final double? longitude;
  final String? nearbyMessageId;
  final String cloudSyncStatus;
  final DateTime? readAt;
}
