import '../../data/models/prototype_models.dart';

enum MediaTransferState {
  pending,
  preparing,
  transferring,
  received,
  completed,
  failed,
  cancelled,
}

enum MediaType { image, video }

class LocationData {
  const LocationData({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyMeters,
    this.source,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime capturedAt;
  final String? source;
}

class RelioMediaAttachment {
  const RelioMediaAttachment({
    required this.id,
    required this.messageId,
    required this.transferId,
    required this.mediaType,
    required this.fileName,
    required this.mimeType,
    required this.localPath,
    required this.byteSize,
    required this.bytesTransferred,
    required this.transferStatus,
    required this.createdAt,
    required this.updatedAt,
    this.remoteFileName,
    this.width,
    this.height,
    this.durationMs,
    this.errorCode,
    this.checksumSha256,
    this.cloudMetadataStatus = 'notQueued',
    this.cloudFileStatus = 'notQueued',
  });

  final String id;
  final String messageId;
  final String transferId;
  final MediaType mediaType;
  final String fileName;
  final String mimeType;
  final String localPath;
  final String? remoteFileName;
  final int byteSize;
  final int bytesTransferred;
  final MediaTransferState transferStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? errorCode;
  final String? checksumSha256;
  final String cloudMetadataStatus;
  final String cloudFileStatus;

  double? get progress => byteSize <= 0
      ? null
      : (bytesTransferred / byteSize).clamp(0, 1).toDouble();
}

class RelioConversation {
  const RelioConversation({
    required this.id,
    required this.participantId,
    required this.displayName,
    required this.participantStatus,
    required this.lastMessageText,
    required this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String participantId;
  final String displayName;
  final DeviceStatus participantStatus;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class RelioNearbyDevice {
  const RelioNearbyDevice({
    required this.deviceId,
    required this.displayName,
    required this.status,
    required this.lastSeenAt,
    this.signalQuality,
    this.approxDistance,
    this.endpointId,
    this.connected = false,
  });

  final String deviceId;
  final String displayName;
  final DeviceStatus status;
  final DateTime lastSeenAt;
  final int? signalQuality;
  final int? approxDistance;
  final String? endpointId;
  final bool connected;
}

class RelioSosEvent {
  const RelioSosEvent({
    required this.id,
    required this.ownerDeviceId,
    required this.ownerUserId,
    required this.message,
    required this.latitude,
    required this.longitude,
    this.locationAccuracy,
    this.locationCapturedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.isActive,
    required this.deliveryStatus,
  });

  final String id;
  final String ownerDeviceId;
  final String ownerUserId;
  final String? message;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracy;
  final DateTime? locationCapturedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final DeliveryStatus deliveryStatus;
}

class RelioQueueItem {
  const RelioQueueItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.status,
    required this.ownerUserId,
    required this.attemptCount,
    required this.lastError,
    required this.createdAt,
    required this.updatedAt,
    required this.nextAttemptAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String operation;
  final String status;
  final String? ownerUserId;
  final int attemptCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nextAttemptAt;
}
