import 'dart:async';
import 'dart:typed_data';

import '../../data/models/prototype_models.dart';
import '../domain/relio_entities.dart';
import '../nearby/nearby_transport.dart';
import '../nearby/relio_packet.dart';
import '../repositories/local_repositories.dart';
import 'relay_models.dart';
import 'relay_repository.dart';

typedef RelayPeers = Iterable<NearbyPeer> Function();
typedef RelayEndpointDeviceId = String? Function(String endpointId);

enum RelayResult { stored, forwarded, delivered, duplicate, blocked, expired }

class RelayEngine {
  RelayEngine({
    required this.transport,
    required this.identity,
    required this.repository,
    this.messages,
    this.conversations,
    this.sos,
    this.connectedPeers,
    this.deviceIdForEndpoint,
    RelayPolicy? policy,
  }) : policy = policy ?? const RelayPolicy();

  final NearbyTransport transport;
  final RelioDeviceIdentityRepository identity;
  final RelayRepository repository;
  final MessageRepository? messages;
  final ConversationRepository? conversations;
  final SOSRepository? sos;
  final RelayPeers? connectedPeers;
  final RelayEndpointDeviceId? deviceIdForEndpoint;
  final RelayPolicy policy;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void>? _forwardOperation;
  bool _initialized = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _subscriptions.add(
      transport.connectionEvents.listen((event) {
        if (event.state == NearbyConnectionState.connected) {
          unawaited(forwardPending());
        }
      }),
    );
    await repository.expirePackets(DateTime.now().toUtc());
  }

  Future<RelayResult> enqueuePayload(
    RelioPacket packet, {
    required String destinationDeviceId,
    Duration? ttl,
    int? maxHops,
    int priority = 0,
  }) async {
    final envelope = RelayEnvelope.fromPayloadPacket(
      packet: packet,
      destinationDeviceId: destinationDeviceId,
      ttl: ttl,
      maxHops: maxHops,
      priority: priority,
    );
    return enqueueEnvelope(envelope);
  }

  Future<RelayResult> enqueueEnvelope(RelayEnvelope envelope) async {
    final invalid = policy.validate(envelope);
    if (invalid != null) {
      await repository.storePacket(envelope);
      await repository.updatePacketState(
        envelope.packetId,
        invalid == 'expired'
            ? RelayPacketState.expired
            : RelayPacketState.blocked,
      );
      return invalid == 'expired' ? RelayResult.expired : RelayResult.blocked;
    }
    final inserted = await repository.storePacket(envelope);
    if (!inserted) return RelayResult.duplicate;
    await forwardPending();
    return RelayResult.stored;
  }

  Future<RelayResult> handleIncomingBytes(
    String endpointId,
    Uint8List bytes,
  ) async {
    final packet = RelioPacket.fromBytes(bytes);
    return handleIncomingPacket(endpointId, packet);
  }

  Future<RelayResult> handleIncomingPacket(
    String endpointId,
    RelioPacket packet,
  ) async {
    if (packet.type == RelioPacketType.relayAck) {
      return _handleRelayAck(endpointId, packet);
    }
    if (packet.type != RelioPacketType.relayEnvelope) {
      return RelayResult.blocked;
    }
    final envelope = RelayEnvelope.fromJson(
      packet.payload.cast<String, dynamic>(),
    );
    final invalid = policy.validate(envelope);
    if (invalid != null) {
      await repository.storePacket(envelope);
      await repository.updatePacketState(
        envelope.packetId,
        invalid == 'expired'
            ? RelayPacketState.expired
            : RelayPacketState.blocked,
      );
      await _sendRelayAck(endpointId, envelope.packetId, invalid);
      return invalid == 'expired' ? RelayResult.expired : RelayResult.blocked;
    }

    // ใช้ sender จาก transport เป็น previous hop สำหรับ routing เท่านั้น
    // ไม่เปลี่ยน origin หรือ identity ของ payload เดิม
    final storedEnvelope = envelope.previousHopDeviceId == null
        ? envelope.copyWith(previousHopDeviceId: packet.senderDeviceId)
        : envelope;
    final inserted = await repository.storePacket(storedEnvelope);
    if (!inserted) {
      await _sendRelayAck(endpointId, envelope.packetId, 'stored');
      return RelayResult.duplicate;
    }
    final localDeviceId = await identity.getDeviceId();
    if (storedEnvelope.destinationDeviceId == localDeviceId) {
      try {
        await _materialize(storedEnvelope);
        await repository.updatePacketState(
          storedEnvelope.packetId,
          RelayPacketState.delivered,
        );
        await _sendRelayAck(endpointId, storedEnvelope.packetId, 'delivered');
        return RelayResult.delivered;
      } on Object {
        await repository.updatePacketState(
          storedEnvelope.packetId,
          RelayPacketState.blocked,
        );
        await _sendRelayAck(endpointId, storedEnvelope.packetId, 'blocked');
        return RelayResult.blocked;
      }
    }

    // SOS is safety-visible at a relay node, while private text/location stay
    // in the relay store until the destination consumes them.
    if (storedEnvelope.payloadType == RelioPacketType.sos.name) {
      try {
        await _materialize(storedEnvelope);
      } on Object {
        // Forwarding remains possible even when local SOS presentation is not
        // available; the destination still receives the original envelope.
      }
    }
    await _sendRelayAck(endpointId, storedEnvelope.packetId, 'stored');
    if (storedEnvelope.hopCount >= storedEnvelope.maxHops) {
      await repository.updatePacketState(
        storedEnvelope.packetId,
        RelayPacketState.blocked,
      );
      return RelayResult.blocked;
    }
    await forwardPending();
    return RelayResult.stored;
  }

  Future<void> forwardPending() {
    if (_disposed) return Future<void>.value();
    if (_forwardOperation != null) return _forwardOperation!;
    final operation = _forwardAll();
    _forwardOperation = operation;
    return operation.whenComplete(() => _forwardOperation = null);
  }

  Future<void> _forwardAll() async {
    await repository.expirePackets(DateTime.now().toUtc());
    final self = await identity.getDeviceId();
    final peers = connectedPeers?.call().toList(growable: false) ?? const [];
    if (peers.isEmpty) return;
    for (final record in await repository.listForwardable(
      DateTime.now().toUtc(),
    )) {
      final envelope = record.envelope;
      if (envelope.destinationDeviceId == self) {
        await _materializeIfPresent(record);
        continue;
      }
      if (envelope.hopCount >= envelope.maxHops) {
        await repository.updatePacketState(
          envelope.packetId,
          RelayPacketState.blocked,
        );
        continue;
      }
      final candidate = _choosePeer(envelope, self, peers);
      if (candidate == null) continue;
      final targetDeviceId = _deviceId(candidate);
      if (targetDeviceId == null) continue;
      final existing = await repository.getForwardRecord(
        envelope.packetId,
        targetDeviceId,
      );
      if (existing != null &&
          (existing.status == 'sent' || existing.status == 'delivered')) {
        continue;
      }
      final forwarded = envelope.copyWith(
        hopCount: envelope.hopCount + 1,
        previousHopDeviceId: self,
      );
      final packet = RelioPacket.relayEnvelope(
        senderDeviceId: self,
        senderUserId: 'relay',
        relayPacketId: forwarded.packetId,
        relayPayload: forwarded.toJson(),
      );
      await repository.recordForwardAttempt(
        packetId: envelope.packetId,
        targetDeviceId: targetDeviceId,
        targetEndpointId: candidate.endpointId,
      );
      try {
        // บันทึก SQLite และ forward history ก่อนส่ง Nearby เพื่อให้ crash แล้วกู้ต่อได้
        await transport.sendBytes(
          packet.toBytes(),
          peerId: candidate.endpointId,
        );
        await repository.recordForwardResult(
          packetId: envelope.packetId,
          targetDeviceId: targetDeviceId,
          status: 'sent',
        );
        await repository.updatePacketState(
          envelope.packetId,
          RelayPacketState.forwarded,
        );
      } on Object {
        await repository.recordForwardResult(
          packetId: envelope.packetId,
          targetDeviceId: targetDeviceId,
          status: 'failed',
        );
      }
    }
  }

  NearbyPeer? _choosePeer(
    RelayEnvelope envelope,
    String self,
    List<NearbyPeer> peers,
  ) {
    final eligible = peers
        .where((peer) {
          final deviceId = _deviceId(peer);
          if (deviceId == null || deviceId == self) return false;
          if (deviceId == envelope.originDeviceId ||
              deviceId == envelope.previousHopDeviceId) {
            return false;
          }
          if (peer.capabilities.isNotEmpty &&
              !peer.capabilities.contains('relay-v1')) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    for (final peer in eligible) {
      if (_deviceId(peer) == envelope.destinationDeviceId) return peer;
    }
    return eligible.isEmpty ? null : eligible.first;
  }

  String? _deviceId(NearbyPeer peer) =>
      peer.deviceId ?? deviceIdForEndpoint?.call(peer.endpointId);

  Future<void> _materializeIfPresent(RelayPacketRecord record) async {
    try {
      await _materialize(record.envelope);
      await repository.updatePacketState(
        record.envelope.packetId,
        RelayPacketState.delivered,
      );
    } on Object {
      await repository.updatePacketState(
        record.envelope.packetId,
        RelayPacketState.blocked,
      );
    }
  }

  Future<void> _materialize(RelayEnvelope envelope) async {
    final packet = envelope.toPayloadPacket();
    switch (packet.type) {
      case RelioPacketType.textMessage:
        if (messages == null || conversations == null) {
          throw StateError('Message repositories are unavailable.');
        }
        final conversationId = packet.payload['conversationId']! as String;
        await conversations!.ensureConversation(
          id: conversationId,
          participantId: envelope.originDeviceId,
          displayName: envelope.originDeviceId,
          participantStatus: DeviceStatus.normal,
        );
        await messages!.createIncomingText(
          conversationId: conversationId,
          senderId: packet.senderUserId,
          senderDeviceId: envelope.originDeviceId,
          messageId: envelope.payloadId,
          text: packet.payload['text']! as String,
          createdAt: DateTime.parse(packet.payload['timestamp']! as String),
        );
      case RelioPacketType.locationMessage:
        if (messages == null || conversations == null) {
          throw StateError('Message repositories are unavailable.');
        }
        final conversationId = packet.payload['conversationId']! as String;
        await conversations!.ensureConversation(
          id: conversationId,
          participantId: envelope.originDeviceId,
          displayName: envelope.originDeviceId,
          participantStatus: DeviceStatus.normal,
        );
        await messages!.createIncomingLocation(
          conversationId: conversationId,
          senderId: packet.senderUserId,
          senderDeviceId: envelope.originDeviceId,
          messageId: envelope.payloadId,
          location: LocationData(
            latitude: (packet.payload['latitude']! as num).toDouble(),
            longitude: (packet.payload['longitude']! as num).toDouble(),
            accuracyMeters: (packet.payload['accuracyMeters'] as num?)
                ?.toDouble(),
            capturedAt: DateTime.parse(packet.payload['capturedAt']! as String),
          ),
        );
      case RelioPacketType.sos:
        if (sos == null) throw StateError('SOS repository is unavailable.');
        await sos!.createIncoming(
          id: envelope.payloadId,
          ownerDeviceId: envelope.originDeviceId,
          ownerUserId: packet.payload['ownerUserId']! as String,
          message: packet.payload['message'] as String?,
          latitude: (packet.payload['latitude'] as num?)?.toDouble(),
          longitude: (packet.payload['longitude'] as num?)?.toDouble(),
          locationAccuracy: (packet.payload['accuracyMeters'] as num?)
              ?.toDouble(),
          locationCapturedAt: packet.payload['locationCapturedAt'] == null
              ? null
              : DateTime.parse(packet.payload['locationCapturedAt']! as String),
          createdAt: DateTime.parse(packet.payload['createdAt']! as String),
          isActive: packet.payload['isActive']! as bool,
        );
      case RelioPacketType.hello ||
          RelioPacketType.deviceStatus ||
          RelioPacketType.ack ||
          RelioPacketType.mediaMetadata ||
          RelioPacketType.mediaAck ||
          RelioPacketType.relayEnvelope ||
          RelioPacketType.relayAck:
        throw StateError('Unsupported relay payload.');
    }
  }

  Future<RelayResult> _handleRelayAck(
    String endpointId,
    RelioPacket packet,
  ) async {
    final packetId = packet.payload['relayPacketId']! as String;
    final status = packet.payload['status']! as String;
    final local = await identity.getDeviceId();
    final peers = connectedPeers?.call() ?? const <NearbyPeer>[];
    final target = peers.where((peer) => peer.endpointId == endpointId);
    final targetDeviceId = target.isEmpty
        ? deviceIdForEndpoint?.call(endpointId)
        : _deviceId(target.first);
    if (targetDeviceId != null) {
      await repository.recordForwardResult(
        packetId: packetId,
        targetDeviceId: targetDeviceId,
        status: status == 'delivered' ? 'delivered' : 'sent',
      );
    }
    if (local.isEmpty) return RelayResult.blocked;
    return status == 'delivered' ? RelayResult.delivered : RelayResult.stored;
  }

  Future<void> _sendRelayAck(
    String endpointId,
    String relayPacketId,
    String status,
  ) async {
    try {
      final packet = RelioPacket.relayAck(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: 'relay',
        relayPacketId: relayPacketId,
        status: status == 'expired'
            ? 'expired'
            : status == 'blocked'
            ? 'blocked'
            : status == 'delivered'
            ? 'delivered'
            : 'stored',
      );
      await transport.sendBytes(packet.toBytes(), peerId: endpointId);
    } on Object {
      // A hop ACK is best effort; SQLite still contains the authoritative row.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
  }
}
