import 'dart:async';
import 'dart:typed_data';

import '../../app/environment.dart';
import '../../data/models/prototype_models.dart';
import '../diagnostics/diagnostics_log_service.dart';
import '../domain/relio_entities.dart';
import '../nearby/nearby_transport.dart';
import '../nearby/relio_packet.dart';
import '../repositories/local_repositories.dart';
import 'relay_models.dart';
import 'relay_repository.dart';

typedef RelayPeers = Iterable<NearbyPeer> Function();
typedef RelayEndpointDeviceId = String? Function(String endpointId);
typedef RelayNextHopReachability =
    Future<bool> Function(
      String nextHopDeviceId,
      String destinationDeviceId,
      int maxHops,
    );

enum RelayResult { stored, forwarded, delivered, duplicate, blocked, expired }

// ประสานการรับซอง relay-v1 กับการจัดเก็บซ้ำ การส่งต่อแบบจำกัด hop และ ACK
// Repository เก็บสถานะที่อยู่รอดหลังปิดแอป; ผลส่งต่อหนึ่ง hop ยังไม่ใช่ ACK ส่งถึงผู้รับสุดท้าย
class RelayEngine {
  RelayEngine({
    required this.transport,
    required this.identity,
    required this.repository,
    this.messages,
    this.conversations,
    this.sos,
    this.connectedPeers,
    this.receiptPeers,
    this.deviceIdForEndpoint,
    this.nextHopHasRoute,
    this.diagnostics,
    this.forwardingAllowed,
    this.relayParticipationAllowed,
    this.secureRelayEnabled,
    this.qaPlaintextTextAllowed,
    this.qaTextForwardingPaused,
    this.verifyRelayedOrigin,
    this.receiveRelayedSos,
    this.receiveRelayedRescue,
    RelayPolicy? policy,
  }) : policy =
           policy ??
           (RelioBuildInfo.isTest
               ? const RelayPolicy(
                   maxHops: RelayPolicy.qaAutomaticTextMaxHops,
                   maxTextHops: RelayPolicy.qaAutomaticTextMaxHops,
                 )
               : const RelayPolicy());

  final NearbyTransport transport;
  final RelioDeviceIdentityRepository identity;
  final RelayRepository repository;
  final MessageRepository? messages;
  final ConversationRepository? conversations;
  final SOSRepository? sos;
  final RelayPeers? connectedPeers;
  final RelayPeers? receiptPeers;
  final RelayEndpointDeviceId? deviceIdForEndpoint;
  final RelayNextHopReachability? nextHopHasRoute;
  final DiagnosticsLogService? diagnostics;
  final bool Function()? forwardingAllowed;
  final Future<bool> Function()? relayParticipationAllowed;
  final bool Function()? secureRelayEnabled;
  final bool Function()? qaPlaintextTextAllowed;
  final bool Function()? qaTextForwardingPaused;
  final Future<bool> Function(RelayEnvelope envelope, RelioPacket packet)?
  verifyRelayedOrigin;
  final Future<void> Function(String endpointId, RelioPacket packet)?
  receiveRelayedSos;
  final Future<void> Function(String endpointId, RelioPacket packet)?
  receiveRelayedRescue;
  final RelayPolicy policy;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void>? _forwardOperation;
  bool _forwardRequested = false;
  bool _initialized = false;
  bool _disposed = false;
  final _receiptEndpoints = <String, String>{};

  bool _isText(RelayEnvelope envelope) =>
      envelope.payloadType == RelioPacketType.textMessage.name;

  bool get _qaPlaintextEnabled =>
      RelioBuildInfo.isTest && qaPlaintextTextAllowed?.call() == true;

  bool _plaintextBlocked(RelayEnvelope envelope) =>
      _isText(envelope) &&
      qaPlaintextTextAllowed != null &&
      !_qaPlaintextEnabled;

  Future<bool> _mayForwardThirdParty(RelayEnvelope envelope) async =>
      (secureRelayEnabled?.call() != false ||
          envelope.payloadType == RelioPacketType.sos.name ||
          envelope.payloadType == RelioPacketType.rescueStatus.name ||
          (_isText(envelope) && _qaPlaintextEnabled)) &&
      (relayParticipationAllowed == null || await relayParticipationAllowed!());

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _subscriptions.add(
      transport.connectionEvents.listen((event) {
        if (event.state != NearbyConnectionState.connected) {
          _receiptEndpoints.removeWhere(
            (_, endpoint) => endpoint == event.peer.endpointId,
          );
        }
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

  // บันทึกซองและตรวจซ้ำจาก Repository ก่อนส่งต่อ เพื่อให้คิวอยู่ต่อได้เมื่อการเชื่อมต่อหาย
  Future<RelayResult> enqueueEnvelope(RelayEnvelope envelope) async {
    if (_plaintextBlocked(envelope)) return RelayResult.blocked;
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
    _recordRelay('packet_enqueued', envelope, fields: {'state': 'stored'});
    await forwardPending();
    return RelayResult.stored;
  }

  /// จุดเริ่ม QA สำหรับ probe ที่บังคับ hop แรกตามเส้นทางที่เลือก
  /// ค่า firstHop ผูกกับซองนี้และถูกล้างหลังส่ง hop แรก
  Future<RelayResult> enqueueQaEnvelopeVia(
    RelayEnvelope envelope, {
    required String firstHopDeviceId,
  }) {
    if (!RelioBuildInfo.isTest) {
      throw StateError('Packet-scoped QA relay is available only in TEST.');
    }
    if (firstHopDeviceId == envelope.originDeviceId ||
        firstHopDeviceId == envelope.destinationDeviceId ||
        firstHopDeviceId.isEmpty ||
        firstHopDeviceId.length > 128) {
      throw ArgumentError.value(firstHopDeviceId, 'firstHopDeviceId');
    }
    return enqueueEnvelope(
      envelope.copyWith(firstHopDeviceId: firstHopDeviceId),
    );
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
    if (_plaintextBlocked(envelope)) {
      if (RelioBuildInfo.isTest) {
        await _sendRelayAck(endpointId, envelope.packetId, 'deferred');
      }
      return RelayResult.blocked;
    }
    if (qaPlaintextTextAllowed != null &&
        _isText(envelope) &&
        (envelope.previousHopDeviceId != packet.senderDeviceId ||
            envelope.visitedDeviceIds.lastOrNull != packet.senderDeviceId)) {
      return RelayResult.blocked;
    }
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
    if (envelope.payloadType == RelioPacketType.sos.name ||
        envelope.payloadType == RelioPacketType.rescueStatus.name) {
      final payloadPacket = envelope.toPayloadPacket();
      final verify = verifyRelayedOrigin;
      if (verify == null || !await verify(envelope, payloadPacket)) {
        await _sendRelayAck(endpointId, envelope.packetId, 'blocked');
        _recordRelay('sos_origin_proof_rejected', envelope);
        return RelayResult.blocked;
      }
    }

    // ใช้ sender จาก transport เป็น previous hop สำหรับ routing เท่านั้น
    // ไม่เปลี่ยน origin หรือ identity ของ payload เดิม
    final storedEnvelope = envelope.copyWith(
      previousHopDeviceId:
          envelope.previousHopDeviceId ?? packet.senderDeviceId,
      clearFirstHopDeviceId: true,
    );
    final localDeviceId = await identity.getDeviceId();
    if (storedEnvelope.destinationDeviceId != localDeviceId &&
        !await _mayForwardThirdParty(storedEnvelope)) {
      // Do not accept a new third-party store-and-forward job without consent.
      await _sendRelayAck(
        endpointId,
        storedEnvelope.packetId,
        _isText(storedEnvelope) && _qaPlaintextEnabled ? 'deferred' : 'blocked',
      );
      return RelayResult.blocked;
    }
    if (storedEnvelope.visitedDeviceIds.contains(localDeviceId) &&
        await repository.getPacket(storedEnvelope.packetId) == null) {
      await repository.storePacket(storedEnvelope);
      await repository.updatePacketState(
        storedEnvelope.packetId,
        RelayPacketState.blocked,
      );
      _recordRelay('route_loop_rejected', storedEnvelope);
      await _sendRelayAck(endpointId, storedEnvelope.packetId, 'blocked');
      return RelayResult.blocked;
    }
    final inserted = await repository.storePacket(storedEnvelope);
    if (!inserted) {
      _recordRelay('duplicate_suppressed', storedEnvelope);
      final existing = await repository.getPacket(envelope.packetId);
      final reply =
          RelioBuildInfo.isTest && envelope.payloadType == 'textMessage'
          ? existing?.state.name ?? 'stored'
          : 'stored';
      await _sendRelayAck(
        endpointId,
        envelope.packetId,
        const {'delivered', 'blocked', 'expired'}.contains(reply)
            ? reply
            : 'stored',
      );
      return RelayResult.duplicate;
    }
    _recordRelay(
      'envelope_stored',
      storedEnvelope,
      fields: {
        'nodeRole':
            storedEnvelope.destinationDeviceId == await identity.getDeviceId()
            ? 'destination'
            : 'relay',
      },
    );
    if (storedEnvelope.destinationDeviceId == localDeviceId) {
      try {
        final payload = storedEnvelope.toPayloadPacket();
        if (payload.type == RelioPacketType.sos &&
            receiveRelayedSos != null) {
          await receiveRelayedSos!(endpointId, payload);
        } else if (payload.type == RelioPacketType.rescueStatus) {
          final receive = receiveRelayedRescue;
          if (receive == null) {
            throw StateError('Rescue status receive handler is unavailable.');
          }
          await receive(endpointId, payload);
        } else {
          await _materialize(storedEnvelope);
        }
        await repository.updatePacketState(
          storedEnvelope.packetId,
          RelayPacketState.delivered,
        );
        _recordRelay('payload_delivered', storedEnvelope);
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

    if (storedEnvelope.payloadType == RelioPacketType.sos.name ||
        storedEnvelope.payloadType == RelioPacketType.rescueStatus.name) {
      final receive = storedEnvelope.payloadType == RelioPacketType.sos.name
          ? receiveRelayedSos
          : receiveRelayedRescue;
      if (receive == null) {
        await repository.updatePacketState(
          storedEnvelope.packetId,
          RelayPacketState.blocked,
        );
        await _sendRelayAck(endpointId, storedEnvelope.packetId, 'blocked');
        return RelayResult.blocked;
      }
      try {
        await receive(endpointId, storedEnvelope.toPayloadPacket());
      } on Object {
        await repository.updatePacketState(
          storedEnvelope.packetId,
          RelayPacketState.blocked,
        );
        await _sendRelayAck(endpointId, storedEnvelope.packetId, 'blocked');
        return RelayResult.blocked;
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
    if (_isText(storedEnvelope) && _qaPlaintextEnabled) {
      // ปล่อยคิวรับแพ็กเก็ตให้ประมวลผล ACK/probe ระหว่างส่งต่อ
      unawaited(forwardPending().catchError((Object _) {}));
    } else {
      await forwardPending();
    }
    return RelayResult.stored;
  }

  Future<void> forwardPending() {
    if (_disposed) return Future<void>.value();
    _forwardRequested = true;
    if (_forwardOperation != null) return _forwardOperation!;
    return _forwardOperation = _drainForwardRequests().whenComplete(
      () => _forwardOperation = null,
    );
  }

  Future<void> _drainForwardRequests() async {
    while (_forwardRequested && !_disposed) {
      _forwardRequested = false;
      await _forwardAll();
    }
  }

  Future<void> _forwardAll() async {
    if (forwardingAllowed?.call() == false) return;
    final forwardingOwner = identity.profiles.owners.capture();
    await repository.expirePackets(DateTime.now().toUtc());
    final self = await identity.getDeviceId();
    final peers = connectedPeers?.call().toList(growable: false) ?? const [];
    if (peers.isEmpty) return;
    // ACK ที่ปลายทางยืนยันแล้วต้องกู้จาก SQLite ได้ เมื่อ upstream กลับมา
    if (RelioBuildInfo.isTest) {
      final receipts = await repository.listDeliveredTextReceipts(
        DateTime.now().toUtc(),
      );
      final retained = receipts
          .map((record) => record.envelope.packetId)
          .toSet();
      _receiptEndpoints.removeWhere(
        (packetId, _) => !retained.contains(packetId),
      );
      for (final record in receipts) {
        if (record.envelope.originDeviceId != self) {
          await _propagateFinalAck(record.envelope, 'delivered');
        }
      }
    }
    for (final record in await repository.listForwardable(
      DateTime.now().toUtc(),
    )) {
      if (_disposed) return;
      final envelope = record.envelope;
      if (_plaintextBlocked(envelope)) continue;
      if (envelope.originDeviceId != self &&
          !await _mayForwardThirdParty(envelope)) {
        // Keep already stored work pending until consent returns or TTL expires.
        continue;
      }
      // QA พักเฉพาะ Text ที่รับฝาก ไม่พัก SOS และไม่เปลี่ยน policy ของ PROD
      if (RelioBuildInfo.isTest &&
          qaTextForwardingPaused?.call() == true &&
          envelope.originDeviceId != self &&
          envelope.payloadType == RelioPacketType.textMessage.name) {
        continue;
      }
      if (RelioBuildInfo.isTest &&
          envelope.originDeviceId == self &&
          envelope.payloadType == 'textMessage') {
        final localPrincipal = (await identity.profiles.current()).principalId;
        final sender = envelope.toPayloadPacket().senderPrincipal;
        if (sender != null && sender != localPrincipal) continue;
      }
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
      final candidate = await _choosePeer(envelope, self, peers);
      if (candidate == null) continue;
      final targetDeviceId = _deviceId(candidate);
      if (targetDeviceId == null) continue;
      final existing = await repository.getForwardRecord(
        envelope.packetId,
        targetDeviceId,
      );
      if (existing?.status == 'deferred' &&
          DateTime.now().toUtc().difference(existing!.updatedAt) <
              const Duration(seconds: 3)) {
        continue;
      }
      if (existing != null &&
          (existing.status == 'sent' ||
              existing.status == 'stored' ||
              existing.status == 'delivered')) {
        final retryReceipt =
            RelioBuildInfo.isTest &&
            envelope.payloadType == 'textMessage' &&
            existing.status != 'delivered' &&
            existing.attemptCount < 3 &&
            (existing.targetEndpointId != candidate.endpointId ||
                DateTime.now().toUtc().difference(existing.updatedAt) >=
                    const Duration(seconds: 30));
        if (!retryReceipt) continue;
      }
      final forwarded = envelope.copyWith(
        hopCount: envelope.hopCount + 1,
        previousHopDeviceId: self,
        clearFirstHopDeviceId: true,
        visitedDeviceIds: _routePathForForward(envelope, self),
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
      _recordRelay(
        'forward_attempt',
        forwarded,
        fields: {
          'targetAlias': DiagnosticsLogService.peerAlias(targetDeviceId),
        },
      );
      try {
        if (RelioBuildInfo.isTest &&
            envelope.originDeviceId == self &&
            envelope.payloadType == 'textMessage') {
          identity.profiles.owners.requireCurrent(forwardingOwner);
        }
        if (_plaintextBlocked(envelope) ||
            (envelope.originDeviceId != self &&
                !await _mayForwardThirdParty(envelope))) {
          continue;
        }
        // บันทึก SQLite และ forward history ก่อนส่ง Nearby เพื่อให้ crash แล้วกู้ต่อได้
        await transport.sendBytes(
          packet.toBytes(),
          peerId: candidate.endpointId,
        );
        final latestForward = await repository.getForwardRecord(
          envelope.packetId,
          targetDeviceId,
        );
        if (latestForward?.status == 'attempting') {
          await repository.recordForwardResult(
            packetId: envelope.packetId,
            targetDeviceId: targetDeviceId,
            status: 'sent',
          );
        }
        final latestPacket = await repository.getPacket(envelope.packetId);
        if (latestPacket?.state == RelayPacketState.stored) {
          await repository.updatePacketState(
            envelope.packetId,
            RelayPacketState.forwarded,
          );
        }
        _recordRelay(
          'forward_sent',
          forwarded,
          fields: {
            'targetAlias': DiagnosticsLogService.peerAlias(targetDeviceId),
          },
        );
      } on Object {
        await repository.recordForwardResult(
          packetId: envelope.packetId,
          targetDeviceId: targetDeviceId,
          status: 'failed',
        );
        _recordRelay(
          'forward_failed',
          forwarded,
          fields: {
            'targetAlias': DiagnosticsLogService.peerAlias(targetDeviceId),
          },
        );
      }
    }
  }

  // เลือกเพียงหนึ่ง peer ต่อซอง โดยเคารพ first-hop ของต้นทางก่อนพิจารณาปลายทางที่เชื่อมตรง
  Future<NearbyPeer?> _choosePeer(
    RelayEnvelope envelope,
    String self,
    List<NearbyPeer> peers,
  ) async {
    final eligible =
        peers
            .where((peer) {
              final deviceId = _deviceId(peer);
              if (deviceId == null || deviceId == self) return false;
              if (deviceId == envelope.originDeviceId ||
                  deviceId == envelope.previousHopDeviceId ||
                  envelope.visitedDeviceIds.contains(deviceId)) {
                return false;
              }
              if (peer.capabilities.isNotEmpty &&
                  !peer.capabilities.contains('relay-v1')) {
                return false;
              }
              if (_isText(envelope) &&
                  qaPlaintextTextAllowed != null &&
                  !peer.capabilities.contains(
                    RelayPolicy.qaPlaintextTextCapability,
                  )) {
                return false;
              }
              return true;
            })
            .toList(growable: false)
          ..sort((a, b) => _deviceId(a)!.compareTo(_deviceId(b)!));
    if (envelope.originDeviceId == self && envelope.hopCount == 0) {
      final firstHop = envelope.firstHopDeviceId;
      if (firstHop != null) {
        return eligible
            .where((peer) => _deviceId(peer) == firstHop)
            .firstOrNull;
      }
    }
    for (final peer in eligible) {
      if (_deviceId(peer) == envelope.destinationDeviceId) return peer;
    }
    if (envelope.hopCount + 1 >= envelope.maxHops) return null;
    final hasRoute = nextHopHasRoute;
    if (RelioBuildInfo.isTest &&
        envelope.payloadType == RelioPacketType.textMessage.name &&
        hasRoute != null) {
      final remainingHops = envelope.maxHops - envelope.hopCount - 1;
      if (remainingHops < 1) return null;
      for (final peer in eligible) {
        final deviceId = _deviceId(peer)!;
        try {
          if (await hasRoute(
            deviceId,
            envelope.destinationDeviceId,
            remainingHops,
          )) {
            return peer;
          }
        } on Object {
          // Route probe failure keeps the message queued for a later check.
        }
      }
      return null;
    }
    return eligible.isEmpty ? null : eligible.first;
  }

  String? _deviceId(NearbyPeer peer) =>
      peer.deviceId ?? deviceIdForEndpoint?.call(peer.endpointId);

  List<String> _routePathForForward(RelayEnvelope envelope, String self) {
    final path = envelope.visitedDeviceIds.isEmpty
        ? <String>[envelope.originDeviceId]
        : List<String>.of(envelope.visitedDeviceIds);
    if (!path.contains(self)) path.add(self);
    return path;
  }

  void _recordRelay(
    String event,
    RelayEnvelope envelope, {
    Map<String, Object?> fields = const {},
  }) {
    diagnostics?.record(
      'relay',
      event,
      peerIdentifier: envelope.destinationDeviceId,
      fields: {
        'relayPacketAlias': DiagnosticsLogService.peerAlias(envelope.packetId),
        'payloadAlias': DiagnosticsLogService.peerAlias(envelope.payloadId),
        'originAlias': DiagnosticsLogService.peerAlias(envelope.originDeviceId),
        'destinationAlias': DiagnosticsLogService.peerAlias(
          envelope.destinationDeviceId,
        ),
        'hopCount': envelope.hopCount,
        'maxHops': envelope.maxHops,
        if (envelope.previousHopDeviceId case final previousHop?)
          'previousHopAlias': DiagnosticsLogService.peerAlias(previousHop),
        ...fields,
      },
    );
  }

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

  Future<void> _materialize(RelayEnvelope envelope) =>
      identity.profiles.owners.run(() => _materializeOwned(envelope));

  Future<void> _materializeOwned(RelayEnvelope envelope) async {
    final packet = envelope.toPayloadPacket();
    if (packet.type == RelioPacketType.textMessage ||
        packet.type == RelioPacketType.locationMessage) {
      final local = (await identity.profiles.current()).principalId;
      if (!RelioPacket.validPrincipal(packet.senderPrincipal) ||
          packet.recipientPrincipal != local) {
        throw StateError('Private relay principal is unavailable');
      }
    }
    switch (packet.type) {
      case RelioPacketType.textMessage:
        if (messages == null || conversations == null) {
          throw StateError('Message repositories are unavailable.');
        }
        final conversationId = packet.payload['conversationId']! as String;
        final conversation = await conversations!.ensureConversation(
          id: conversationId,
          participantId: envelope.originDeviceId,
          remotePrincipalId: packet.senderPrincipal,
          displayName: envelope.originDeviceId,
          participantStatus: DeviceStatus.normal,
        );
        await messages!.createIncomingText(
          conversationId: conversation.id,
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
        final conversation = await conversations!.ensureConversation(
          id: conversationId,
          participantId: envelope.originDeviceId,
          remotePrincipalId: packet.senderPrincipal,
          displayName: envelope.originDeviceId,
          participantStatus: DeviceStatus.normal,
        );
        await messages!.createIncomingLocation(
          conversationId: conversation.id,
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
          requesterDisplayName:
              packet.payload['displayName'] as String? ??
              envelope.originDeviceId,
        );
      case RelioPacketType.rescueStatus:
        throw StateError('Rescue status must use the validated receive path.');
      case RelioPacketType.hello ||
          RelioPacketType.identityChallenge ||
          RelioPacketType.identityProof ||
          RelioPacketType.deviceStatus ||
          RelioPacketType.ack ||
          RelioPacketType.readReceipt ||
          RelioPacketType.mediaMetadata ||
          RelioPacketType.mediaAck ||
          RelioPacketType.relayEnvelope ||
          RelioPacketType.reachabilitySnapshot ||
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
    final record = await repository.getPacket(packetId);
    if (record == null) return RelayResult.blocked;
    final local = await identity.getDeviceId();
    final peers = connectedPeers?.call() ?? const <NearbyPeer>[];
    final target = peers.where((peer) => peer.endpointId == endpointId);
    final targetDeviceId = target.isEmpty
        ? deviceIdForEndpoint?.call(endpointId)
        : _deviceId(target.first);
    if (targetDeviceId == null) return RelayResult.blocked;
    final expectedForward = await repository.getForwardRecord(
      packetId,
      targetDeviceId,
    );
    if (expectedForward == null) {
      _recordRelay('unexpected_ack_blocked', record.envelope);
      return RelayResult.blocked;
    }
    final extendedReceipt =
        RelioBuildInfo.isTest && record.envelope.payloadType == 'textMessage';
    if (!extendedReceipt) {
      await repository.recordForwardResult(
        packetId: packetId,
        targetDeviceId: targetDeviceId,
        status: status == 'delivered' ? 'delivered' : 'sent',
      );
      await _recordRelayAck('ack_received', packetId, status, endpointId);
      return status == 'delivered' ? RelayResult.delivered : RelayResult.stored;
    }
    if (record.state == RelayPacketState.delivered && status != 'delivered') {
      return RelayResult.delivered;
    }
    await repository.recordForwardResult(
      packetId: packetId,
      targetDeviceId: targetDeviceId,
      status: status,
    );
    await _recordRelayAck('ack_received', packetId, status, endpointId);
    if (status == 'deferred') return RelayResult.stored;
    if (status == 'delivered') {
      await repository.updatePacketState(packetId, RelayPacketState.delivered);
      if (record.envelope.originDeviceId == local) {
        await _updateOriginText(record.envelope, DeliveryStatus.delivered);
      } else {
        await _propagateFinalAck(record.envelope, status);
      }
      return RelayResult.delivered;
    }
    if (status == 'blocked' || status == 'expired') {
      await repository.updatePacketState(
        packetId,
        status == 'expired'
            ? RelayPacketState.expired
            : RelayPacketState.blocked,
      );
      if (record.envelope.originDeviceId == local) {
        await _updateOriginText(record.envelope, DeliveryStatus.failed);
      } else {
        await _propagateFinalAck(record.envelope, status);
      }
      return status == 'expired' ? RelayResult.expired : RelayResult.blocked;
    }
    if (record.envelope.originDeviceId == local) {
      await _updateOriginText(record.envelope, DeliveryStatus.nearbySent);
    }
    return RelayResult.stored;
  }

  Future<void> _updateOriginText(
    RelayEnvelope envelope,
    DeliveryStatus status,
  ) => identity.profiles.owners.run(() async {
    final principal = (await identity.profiles.current()).principalId;
    if (envelope.toPayloadPacket().senderPrincipal != principal) return;
    final message = await messages?.getMessage(envelope.payloadId);
    if (message == null ||
        !message.outgoing ||
        message.status == DeliveryStatus.delivered ||
        message.status == DeliveryStatus.synced) {
      return;
    }
    await messages?.advanceTextRouteStatus(envelope.payloadId, status);
  });

  Future<void> _propagateFinalAck(RelayEnvelope envelope, String status) async {
    final previous = envelope.previousHopDeviceId;
    if (previous == null) return;
    final upstream =
        ((receiptPeers ?? connectedPeers)?.call() ?? const <NearbyPeer>[])
            .where((peer) => _deviceId(peer) == previous)
            .toList(growable: false);
    if (upstream.length != 1) return;
    final endpoint = upstream.single.endpointId;
    if (_receiptEndpoints[envelope.packetId] == endpoint) return;
    final sent = await _sendRelayAck(
      upstream.single.endpointId,
      envelope.packetId,
      status,
    );
    if (!sent) return;
    _receiptEndpoints[envelope.packetId] = endpoint;
    _recordRelay(
      'final_ack_propagated',
      envelope,
      fields: {'ackStatus': status},
    );
  }

  Future<bool> _sendRelayAck(
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
      await _recordRelayAck('ack_sent', relayPacketId, status, endpointId);
      return true;
    } on Object {
      await _recordRelayAck('ack_failed', relayPacketId, status, endpointId);
      // A hop ACK is best effort; SQLite still contains the authoritative row.
      return false;
    }
  }

  Future<void> _recordRelayAck(
    String event,
    String packetId,
    String status,
    String endpointId,
  ) async {
    if (diagnostics == null) return;
    try {
      final record = await repository.getPacket(packetId);
      if (record == null) return;
      _recordRelay(
        event,
        record.envelope,
        fields: {
          'ackStatus': status,
          'ackEndpointAlias': DiagnosticsLogService.peerAlias(endpointId),
        },
      );
    } on Object {
      // QA logging must not change relay acknowledgement behavior.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    await _forwardOperation?.catchError((Object _) {});
  }
}
