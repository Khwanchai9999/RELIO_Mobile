import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../data/models/prototype_models.dart';

enum RelioPacketType {
  hello,
  textMessage,
  deviceStatus,
  ack,
  sos,
  mediaMetadata,
  mediaAck,
  locationMessage,
  relayEnvelope,
  relayAck,
}

class RelioPacketException implements Exception {
  const RelioPacketException(this.message);
  final String message;

  @override
  String toString() => 'RelioPacketException: $message';
}

class RelioPacket {
  const RelioPacket({
    required this.protocolVersion,
    required this.packetId,
    required this.type,
    required this.senderDeviceId,
    required this.senderUserId,
    required this.createdAt,
    required this.payload,
  });

  final int protocolVersion;
  final String packetId;
  final RelioPacketType type;
  final String senderDeviceId;
  final String senderUserId;
  final DateTime createdAt;
  final Map<String, Object?> payload;

  factory RelioPacket.hello({
    required String senderDeviceId,
    required String senderUserId,
    required String displayName,
    DeviceStatus status = DeviceStatus.normal,
    List<String> capabilities = const [
      'textMessage',
      'deviceStatus',
      'ack',
      'relay-v1',
    ],
  }) => RelioPacket(
    protocolVersion: 1,
    packetId: const Uuid().v4(),
    type: RelioPacketType.hello,
    senderDeviceId: senderDeviceId,
    senderUserId: senderUserId,
    createdAt: DateTime.now().toUtc(),
    payload: {
      'displayName': displayName,
      'status': status.name,
      'capabilities': capabilities,
    },
  );

  factory RelioPacket.textMessage({
    required String senderDeviceId,
    required String senderUserId,
    required String messageId,
    required String conversationId,
    required String text,
    required DateTime timestamp,
  }) => RelioPacket(
    protocolVersion: 1,
    packetId: const Uuid().v4(),
    type: RelioPacketType.textMessage,
    senderDeviceId: senderDeviceId,
    senderUserId: senderUserId,
    createdAt: DateTime.now().toUtc(),
    payload: {
      'messageId': messageId,
      'conversationId': conversationId,
      'text': text,
      'timestamp': timestamp.toUtc().toIso8601String(),
    },
  );

  factory RelioPacket.ack({
    required String senderDeviceId,
    required String senderUserId,
    required String acknowledgedPacketId,
    String? messageId,
  }) => RelioPacket(
    protocolVersion: 1,
    packetId: const Uuid().v4(),
    type: RelioPacketType.ack,
    senderDeviceId: senderDeviceId,
    senderUserId: senderUserId,
    createdAt: DateTime.now().toUtc(),
    payload: {
      'packetId': acknowledgedPacketId,
      ...?(messageId == null ? null : {'messageId': messageId}),
    },
  );

  factory RelioPacket.deviceStatus({
    required String senderDeviceId,
    required String senderUserId,
    required String displayName,
    required DeviceStatus status,
    DateTime? updatedAt,
  }) => RelioPacket(
    protocolVersion: 1,
    packetId: const Uuid().v4(),
    type: RelioPacketType.deviceStatus,
    senderDeviceId: senderDeviceId,
    senderUserId: senderUserId,
    createdAt: DateTime.now().toUtc(),
    payload: {
      'deviceId': senderDeviceId,
      'displayName': displayName,
      'status': status.name,
      'updatedAt': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    },
  );

  factory RelioPacket.sos({
    required String senderDeviceId,
    required String senderUserId,
    required String displayName,
    required String sosId,
    String? message,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    DateTime? locationCapturedAt,
    required DateTime createdAt,
    required bool isActive,
  }) => RelioPacket(
    protocolVersion: 1,
    packetId: const Uuid().v4(),
    type: RelioPacketType.sos,
    senderDeviceId: senderDeviceId,
    senderUserId: senderUserId,
    createdAt: DateTime.now().toUtc(),
    payload: {
      'sosId': sosId,
      'ownerDeviceId': senderDeviceId,
      'ownerUserId': senderUserId,
      'displayName': displayName,
      ...?(message == null ? null : {'message': message}),
      ...?(latitude == null ? null : {'latitude': latitude}),
      ...?(longitude == null ? null : {'longitude': longitude}),
      ...?(accuracyMeters == null ? null : {'accuracyMeters': accuracyMeters}),
      ...?(locationCapturedAt == null
          ? null
          : {
              'locationCapturedAt': locationCapturedAt
                  .toUtc()
                  .toIso8601String(),
            }),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'isActive': isActive,
    },
  );

  factory RelioPacket.mediaMetadata({
    required String senderDeviceId,
    required String senderUserId,
    required String messageId,
    required String attachmentId,
    required String transferId,
    required String mediaType,
    required String fileName,
    required String mimeType,
    required int byteSize,
    String? payloadId,
    DateTime? mediaCreatedAt,
    int? width,
    int? height,
    int? durationMs,
  }) => RelioPacket(
    protocolVersion: 1,
    packetId: const Uuid().v4(),
    type: RelioPacketType.mediaMetadata,
    senderDeviceId: senderDeviceId,
    senderUserId: senderUserId,
    createdAt: DateTime.now().toUtc(),
    payload: {
      'messageId': messageId,
      'attachmentId': attachmentId,
      'transferId': transferId,
      'mediaType': mediaType,
      'fileName': fileName,
      'mimeType': mimeType,
      'byteSize': byteSize,
      'createdAt': (mediaCreatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      ...?(payloadId == null ? null : {'payloadId': payloadId}),
      ...?(width == null ? null : {'width': width}),
      ...?(height == null ? null : {'height': height}),
      ...?(durationMs == null ? null : {'durationMs': durationMs}),
    },
  );

  factory RelioPacket.mediaAck({
    required String senderDeviceId,
    required String senderUserId,
    required String messageId,
    required String attachmentId,
    required String transferId,
    required String status,
    String? errorCode,
  }) => RelioPacket(
    protocolVersion: 1,
    packetId: const Uuid().v4(),
    type: RelioPacketType.mediaAck,
    senderDeviceId: senderDeviceId,
    senderUserId: senderUserId,
    createdAt: DateTime.now().toUtc(),
    payload: {
      'messageId': messageId,
      'attachmentId': attachmentId,
      'transferId': transferId,
      'status': status,
      ...?(errorCode == null ? null : {'errorCode': errorCode}),
    },
  );

  factory RelioPacket.locationMessage({
    required String senderDeviceId,
    required String senderUserId,
    required String messageId,
    required String conversationId,
    required double latitude,
    required double longitude,
    required DateTime capturedAt,
    double? accuracyMeters,
  }) => RelioPacket(
    protocolVersion: 1,
    packetId: const Uuid().v4(),
    type: RelioPacketType.locationMessage,
    senderDeviceId: senderDeviceId,
    senderUserId: senderUserId,
    createdAt: DateTime.now().toUtc(),
    payload: {
      'messageId': messageId,
      'conversationId': conversationId,
      'latitude': latitude,
      'longitude': longitude,
      'capturedAt': capturedAt.toUtc().toIso8601String(),
      ...?(accuracyMeters == null ? null : {'accuracyMeters': accuracyMeters}),
    },
  );

  factory RelioPacket.relayEnvelope({
    required String senderDeviceId,
    required String senderUserId,
    required String relayPacketId,
    required Map<String, Object?> relayPayload,
  }) => RelioPacket(
    protocolVersion: 1,
    packetId: relayPacketId,
    type: RelioPacketType.relayEnvelope,
    senderDeviceId: senderDeviceId,
    senderUserId: senderUserId,
    createdAt: DateTime.now().toUtc(),
    payload: relayPayload,
  );

  factory RelioPacket.relayAck({
    required String senderDeviceId,
    required String senderUserId,
    required String relayPacketId,
    required String status,
  }) => RelioPacket(
    protocolVersion: 1,
    packetId: const Uuid().v4(),
    type: RelioPacketType.relayAck,
    senderDeviceId: senderDeviceId,
    senderUserId: senderUserId,
    createdAt: DateTime.now().toUtc(),
    payload: {'relayPacketId': relayPacketId, 'status': status},
  );

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'packetId': packetId,
    'type': type.name,
    'senderDeviceId': senderDeviceId,
    'senderUserId': senderUserId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'payload': payload,
  };

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory RelioPacket.fromBytes(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const RelioPacketException('Packet root must be an object.');
      }
      return RelioPacket.fromJson(decoded);
    } on RelioPacketException {
      rethrow;
    } on Object catch (error) {
      throw RelioPacketException('Malformed UTF-8 JSON packet: $error');
    }
  }

  factory RelioPacket.fromJson(Map<String, dynamic> json) {
    final version = json['protocolVersion'];
    if (version is! int || version != 1) {
      throw RelioPacketException('Unsupported protocol version: $version');
    }
    final packetId = _requiredString(json, 'packetId');
    final typeName = _requiredString(json, 'type');
    final type = RelioPacketType.values.where((item) => item.name == typeName);
    if (type.isEmpty) {
      throw RelioPacketException('Unknown packet type: $typeName');
    }
    final createdAt = DateTime.tryParse(_requiredString(json, 'createdAt'));
    if (createdAt == null) {
      throw const RelioPacketException('Invalid createdAt.');
    }
    final rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const RelioPacketException('Packet payload must be an object.');
    }
    final payload = <String, Object?>{};
    rawPayload.forEach((key, value) => payload[key.toString()] = value);
    final packet = RelioPacket(
      protocolVersion: version,
      packetId: packetId,
      type: type.first,
      senderDeviceId: _requiredString(json, 'senderDeviceId'),
      senderUserId: _requiredString(json, 'senderUserId'),
      createdAt: createdAt,
      payload: payload,
    );
    packet._validatePayload();
    return packet;
  }

  void _validatePayload() {
    switch (type) {
      case RelioPacketType.hello:
        _payloadString('displayName');
        // v0.2 hello packets did not carry status. Treat that older shape as
        // normal while emitting the richer v0.3 handshake going forward.
        if (payload.containsKey('status')) _statusField();
      case RelioPacketType.textMessage:
        _payloadString('messageId');
        _payloadString('conversationId');
        _payloadString('text');
        _payloadString('timestamp');
      case RelioPacketType.deviceStatus:
        _payloadString('deviceId');
        _payloadString('displayName');
        _statusField();
        _payloadString('updatedAt');
      case RelioPacketType.ack:
        _payloadString('packetId');
        if (payload.containsKey('messageId')) _payloadString('messageId');
      case RelioPacketType.sos:
        _payloadString('sosId');
        _payloadString('ownerDeviceId');
        _payloadString('ownerUserId');
        _payloadString('displayName');
        _payloadString('createdAt');
        if (payload.containsKey('payloadId')) _payloadString('payloadId');
        _payloadBool('isActive');
        _optionalNumber('latitude');
        _optionalNumber('longitude');
        _optionalNumber('accuracyMeters');
        if (payload.containsKey('locationCapturedAt')) {
          _payloadString('locationCapturedAt');
        }
      case RelioPacketType.mediaMetadata:
        _payloadString('messageId');
        _payloadString('attachmentId');
        _payloadString('transferId');
        final mediaType = _payloadString('mediaType');
        if (!{'image', 'video'}.contains(mediaType)) {
          throw RelioPacketException('Unsupported media type: $mediaType');
        }
        _payloadString('fileName');
        _payloadString('mimeType');
        _requiredNumber('byteSize');
        _payloadString('createdAt');
        _optionalNumber('width');
        _optionalNumber('height');
        _optionalNumber('durationMs');
      case RelioPacketType.mediaAck:
        _payloadString('messageId');
        _payloadString('attachmentId');
        _payloadString('transferId');
        final ackStatus = _payloadString('status');
        if (!{'received', 'completed', 'failed'}.contains(ackStatus)) {
          throw RelioPacketException(
            'Unknown media acknowledgement: $ackStatus',
          );
        }
        if (payload.containsKey('errorCode')) _payloadString('errorCode');
      case RelioPacketType.locationMessage:
        _payloadString('messageId');
        _payloadString('conversationId');
        _requiredNumber('latitude');
        _requiredNumber('longitude');
        _optionalNumber('accuracyMeters');
        _payloadString('capturedAt');
      case RelioPacketType.relayEnvelope:
        _payloadString('protocol');
        if (payload['protocol'] != 'relay-v1') {
          throw const RelioPacketException('Unsupported relay protocol.');
        }
        _payloadString('packetId');
        _payloadString('originDeviceId');
        _payloadString('destinationDeviceId');
        _payloadString('payloadType');
        _payloadString('payloadId');
        _payloadString('createdAt');
        _payloadString('expiresAt');
        final hopCount = payload['hopCount'];
        final maxHops = payload['maxHops'];
        final priority = payload['priority'];
        if (hopCount is! int || maxHops is! int || priority is! int) {
          throw const RelioPacketException('Invalid relay hop fields.');
        }
        if (payload['payload'] is! Map) {
          throw const RelioPacketException('Invalid relay payload.');
        }
      case RelioPacketType.relayAck:
        _payloadString('relayPacketId');
        final relayStatus = _payloadString('status');
        if (!{
          'stored',
          'delivered',
          'expired',
          'blocked',
        }.contains(relayStatus)) {
          throw RelioPacketException(
            'Unknown relay acknowledgement: $relayStatus',
          );
        }
    }
  }

  String _statusField() {
    final status = _payloadString('status');
    if (!{'normal', 'sos', 'rescue'}.contains(status)) {
      throw RelioPacketException('Unknown device status: $status');
    }
    return status;
  }

  bool _payloadBool(String key) {
    final value = payload[key];
    if (value is! bool) {
      throw RelioPacketException('Invalid payload field: $key');
    }
    return value;
  }

  void _optionalNumber(String key) {
    final value = payload[key];
    if (value != null && value is! num) {
      throw RelioPacketException('Invalid payload field: $key');
    }
  }

  num _requiredNumber(String key) {
    final value = payload[key];
    if (value is! num || !value.isFinite) {
      throw RelioPacketException('Missing or invalid payload field: $key');
    }
    return value;
  }

  String _payloadString(String key) {
    final value = payload[key];
    if (value is! String || value.isEmpty) {
      throw RelioPacketException('Missing payload field: $key');
    }
    return value;
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw RelioPacketException('Missing field: $key');
    }
    return value;
  }
}
