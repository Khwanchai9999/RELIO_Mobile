import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../nearby/relio_packet.dart';

enum RelayPacketState { stored, forwarded, delivered, expired, blocked }

class RelayPolicy {
  const RelayPolicy({
    this.defaultTtl = const Duration(minutes: 15),
    this.maxTtl = const Duration(hours: 1),
    this.defaultMaxHops = 3,
    this.maxHops = 3,
    this.maxPacketBytes = 64 * 1024,
  });

  final Duration defaultTtl;
  final Duration maxTtl;
  final int defaultMaxHops;
  final int maxHops;
  final int maxPacketBytes;

  bool isSupportedPayloadType(String value) =>
      const {'textMessage', 'sos', 'locationMessage'}.contains(value);

  String? validate(RelayEnvelope envelope, {DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    if (envelope.protocol != 'relay-v1') return 'unsupportedProtocol';
    if (envelope.packetId.isEmpty || envelope.payloadId.isEmpty) {
      return 'missingIdentity';
    }
    if (envelope.originDeviceId.isEmpty ||
        envelope.destinationDeviceId.isEmpty) {
      return 'missingRoute';
    }
    if (!isSupportedPayloadType(envelope.payloadType)) {
      return 'unsupportedPayload';
    }
    if (envelope.hopCount < 0 ||
        envelope.maxHops < 0 ||
        envelope.hopCount > envelope.maxHops ||
        envelope.maxHops > maxHops) {
      return 'invalidHopCount';
    }
    if (envelope.expiresAt.isBefore(envelope.createdAt) ||
        envelope.expiresAt.isBefore(current)) {
      return 'expired';
    }
    if (envelope.expiresAt.difference(envelope.createdAt) > maxTtl) {
      return 'ttlTooLong';
    }
    if (envelope.toBytes().length > maxPacketBytes) return 'packetTooLarge';
    return null;
  }
}

class RelayEnvelope {
  RelayEnvelope({
    required this.packetId,
    required this.originDeviceId,
    required this.destinationDeviceId,
    required this.payloadType,
    required this.payloadId,
    required this.createdAt,
    required this.expiresAt,
    required this.hopCount,
    required this.maxHops,
    required this.priority,
    required this.previousHopDeviceId,
    required this.payload,
    this.protocol = 'relay-v1',
  });

  final String packetId;
  final String originDeviceId;
  final String destinationDeviceId;
  final String payloadType;
  final String payloadId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int hopCount;
  final int maxHops;
  final int priority;
  final String? previousHopDeviceId;
  final Map<String, Object?> payload;
  final String protocol;

  factory RelayEnvelope.fromPayloadPacket({
    required RelioPacket packet,
    required String destinationDeviceId,
    DateTime? now,
    Duration? ttl,
    int? maxHops,
    int priority = 0,
  }) {
    final payloadId = _payloadId(packet);
    final createdAt = now?.toUtc() ?? DateTime.now().toUtc();
    const policy = RelayPolicy();
    return RelayEnvelope(
      packetId: const Uuid().v4(),
      originDeviceId: packet.senderDeviceId,
      destinationDeviceId: destinationDeviceId,
      payloadType: packet.type.name,
      payloadId: payloadId,
      createdAt: createdAt,
      expiresAt: createdAt.add(ttl ?? policy.defaultTtl),
      hopCount: 0,
      maxHops: maxHops ?? policy.defaultMaxHops,
      priority: priority,
      previousHopDeviceId: null,
      payload: {
        'senderDeviceId': packet.senderDeviceId,
        'senderUserId': packet.senderUserId,
        'createdAt': packet.createdAt.toUtc().toIso8601String(),
        'payload': packet.payload,
      },
    );
  }

  factory RelayEnvelope.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const FormatException('Relay payload must be an object.');
    }
    final payload = <String, Object?>{};
    rawPayload.forEach((key, value) => payload[key.toString()] = value);
    final createdAt = DateTime.tryParse(_string(json, 'createdAt'));
    final expiresAt = DateTime.tryParse(_string(json, 'expiresAt'));
    if (createdAt == null || expiresAt == null) {
      throw const FormatException('Relay timestamps are invalid.');
    }
    final hopCount = json['hopCount'];
    final maxHops = json['maxHops'];
    final priority = json['priority'];
    if (hopCount is! int || maxHops is! int || priority is! int) {
      throw const FormatException('Relay hop fields are invalid.');
    }
    return RelayEnvelope(
      packetId: _string(json, 'packetId'),
      originDeviceId: _string(json, 'originDeviceId'),
      destinationDeviceId: _string(json, 'destinationDeviceId'),
      payloadType: _string(json, 'payloadType'),
      payloadId: _string(json, 'payloadId'),
      createdAt: createdAt,
      expiresAt: expiresAt,
      hopCount: hopCount,
      maxHops: maxHops,
      priority: priority,
      previousHopDeviceId: json['previousHopDeviceId'] as String?,
      payload: payload,
      protocol: _string(json, 'protocol'),
    );
  }

  Map<String, Object?> toJson() => {
    'protocol': protocol,
    'packetId': packetId,
    'originDeviceId': originDeviceId,
    'destinationDeviceId': destinationDeviceId,
    'payloadType': payloadType,
    'payloadId': payloadId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'hopCount': hopCount,
    'maxHops': maxHops,
    'priority': priority,
    ...?(previousHopDeviceId == null
        ? null
        : {'previousHopDeviceId': previousHopDeviceId}),
    'payload': payload,
  };

  List<int> toBytes() => utf8.encode(jsonEncode(toJson()));

  RelayEnvelope copyWith({int? hopCount, String? previousHopDeviceId}) =>
      RelayEnvelope(
        packetId: packetId,
        originDeviceId: originDeviceId,
        destinationDeviceId: destinationDeviceId,
        payloadType: payloadType,
        payloadId: payloadId,
        createdAt: createdAt,
        expiresAt: expiresAt,
        hopCount: hopCount ?? this.hopCount,
        maxHops: maxHops,
        priority: priority,
        previousHopDeviceId: previousHopDeviceId ?? this.previousHopDeviceId,
        payload: payload,
        protocol: protocol,
      );

  RelioPacket toPayloadPacket() {
    final nested = payload['payload'];
    final senderDeviceId = payload['senderDeviceId'];
    final senderUserId = payload['senderUserId'];
    final createdAt = payload['createdAt'];
    if (nested is! Map ||
        senderDeviceId is! String ||
        senderUserId is! String ||
        createdAt is! String) {
      throw const FormatException('Relay payload identity is incomplete.');
    }
    return RelioPacket.fromJson({
      'protocolVersion': 1,
      'packetId': payloadId,
      'type': payloadType,
      'senderDeviceId': senderDeviceId,
      'senderUserId': senderUserId,
      'createdAt': createdAt,
      'payload': nested.map((key, value) => MapEntry(key.toString(), value)),
    });
  }

  static String _payloadId(RelioPacket packet) {
    final key = switch (packet.type) {
      RelioPacketType.textMessage ||
      RelioPacketType.locationMessage => 'messageId',
      RelioPacketType.sos => 'sosId',
      _ => throw ArgumentError('Packet type cannot be relayed.'),
    };
    final value = packet.payload[key];
    if (value is! String || value.isEmpty) {
      throw ArgumentError('Relay payload identity is missing.');
    }
    return value;
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Missing relay field: $key');
    }
    return value;
  }
}

class RelayPacketRecord {
  const RelayPacketRecord({
    required this.envelope,
    required this.state,
    required this.storedAt,
  });

  final RelayEnvelope envelope;
  final RelayPacketState state;
  final DateTime storedAt;
}

class RelayForwardRecord {
  const RelayForwardRecord({
    required this.packetId,
    required this.targetDeviceId,
    required this.targetEndpointId,
    required this.status,
    required this.attemptCount,
    required this.updatedAt,
  });

  final String packetId;
  final String targetDeviceId;
  final String targetEndpointId;
  final String status;
  final int attemptCount;
  final DateTime updatedAt;
}
