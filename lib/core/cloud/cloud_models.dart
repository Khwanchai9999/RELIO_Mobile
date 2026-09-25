import '../../data/models/prototype_models.dart';

enum CloudState { notConfigured, signedOut, ready, offline, error }

enum AuthState { guest, authenticated, expired, loading, error }

class CloudIdentity {
  const CloudIdentity({
    required this.userId,
    required this.email,
    this.displayName,
  });
  final String userId;
  final String email;
  final String? displayName;
}

class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});
  const SupabaseConfig.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
  final String url;
  final String anonKey;
  bool get isConfigured =>
      url.startsWith('https://') &&
      anonKey.isNotEmpty &&
      !anonKey.contains('service_role');
}

class CloudException implements Exception {
  const CloudException(this.message, {this.code = 'unknown'});
  final String message;
  final String code;
  @override
  String toString() => 'CloudException($code): $message';
}

class CloudMessageDto {
  const CloudMessageDto({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderDeviceId,
    required this.messageType,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.deliveryStatus,
    required this.isOutgoing,
  });
  final String id;
  final String conversationId;
  final String senderId;
  final String senderDeviceId;
  final String messageType;
  final String? content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deliveryStatus;
  final bool isOutgoing;
  Map<String, dynamic> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'sender_device_id': senderDeviceId,
    'message_type': messageType,
    'content': content,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'delivery_status': deliveryStatus,
    'is_outgoing': isOutgoing,
  };
  factory CloudMessageDto.fromJson(Map<String, dynamic> json) =>
      CloudMessageDto(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        senderDeviceId: json['sender_device_id'] as String,
        messageType: json['message_type'] as String,
        content: json['content'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        deliveryStatus: json['delivery_status'] as String? ?? 'pending',
        isOutgoing: json['is_outgoing'] as bool? ?? false,
      );
}

class CloudConversationDto {
  const CloudConversationDto({
    required this.id,
    required this.participantId,
    required this.displayName,
    required this.updatedAt,
  });
  final String id;
  final String participantId;
  final String displayName;
  final DateTime updatedAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
  factory CloudConversationDto.fromJson(Map<String, dynamic> json) =>
      CloudConversationDto(
        id: json['id'] as String,
        participantId: json['participant_id'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class CloudAttachmentDto {
  const CloudAttachmentDto({
    required this.id,
    required this.messageId,
    required this.storagePath,
    required this.mediaType,
    required this.mimeType,
    required this.fileName,
    required this.byteSize,
    required this.transferStatus,
  });
  final String id;
  final String messageId;
  final String storagePath;
  final String mediaType;
  final String mimeType;
  final String fileName;
  final int byteSize;
  final String transferStatus;
  Map<String, dynamic> toJson() => {
    'id': id,
    'message_id': messageId,
    'storage_path': storagePath,
    'media_type': mediaType,
    'mime_type': mimeType,
    'file_name': fileName,
    'byte_size': byteSize,
    'transfer_status': transferStatus,
  };
  factory CloudAttachmentDto.fromJson(Map<String, dynamic> json) =>
      CloudAttachmentDto(
        id: json['id'] as String,
        messageId: json['message_id'] as String,
        storagePath: json['storage_path'] as String,
        mediaType: json['media_type'] as String,
        mimeType: json['mime_type'] as String,
        fileName: json['file_name'] as String,
        byteSize: (json['byte_size'] as num).toInt(),
        transferStatus: json['transfer_status'] as String,
      );
}

class CloudSosDto {
  const CloudSosDto({
    required this.id,
    required this.ownerDeviceId,
    required this.message,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.isActive,
  });
  final String id;
  final String ownerDeviceId;
  final String? message;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final bool isActive;
  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_device_id': ownerDeviceId,
    'message': message,
    'latitude': latitude,
    'longitude': longitude,
    'created_at': createdAt.toUtc().toIso8601String(),
    'is_active': isActive,
  };
  factory CloudSosDto.fromJson(Map<String, dynamic> json) => CloudSosDto(
    id: json['id'] as String,
    ownerDeviceId: json['owner_device_id'] as String,
    message: json['message'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    createdAt: DateTime.parse(json['created_at'] as String),
    isActive: json['is_active'] as bool? ?? true,
  );
}

String stableStatus(DeviceStatus status) => status.name;
