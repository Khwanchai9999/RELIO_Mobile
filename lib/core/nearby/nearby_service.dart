import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/prototype_models.dart';
import '../domain/relio_entities.dart';
import '../media/media_storage_service.dart';
import '../repositories/local_repositories.dart';
import '../relay/relay_engine.dart';
import 'nearby_transport.dart';
import 'relio_packet.dart';

enum NearbyApplicationState {
  idle,
  advertising,
  discovering,
  connecting,
  connected,
  disconnected,
  failed,
}

class NearbyService extends ChangeNotifier {
  NearbyService({
    required this.transport,
    required this.messages,
    required this.conversations,
    required this.identity,
    required this.nearbyDevices,
    this.sos,
    this.settings,
    this.attachments,
    this.mediaStorage,
    this.relayEngine,
  });

  final NearbyTransport transport;
  final MessageRepository messages;
  final ConversationRepository conversations;
  final RelioDeviceIdentityRepository identity;
  final NearbyDeviceRepository nearbyDevices;
  final SOSRepository? sos;
  final RelioSettingsRepository? settings;
  final AttachmentRepository? attachments;
  final MediaStorageService? mediaStorage;
  final RelayEngine? relayEngine;
  final List<NearbyPeer> discoveredPeers = [];
  final List<String> eventLog = [];
  final Map<String, String> _packetMessageIds = {};
  final Map<String, RelioPacket> _mediaMetadataByPayload = {};
  final Map<String, NearbyFilePayloadEvent> _mediaFilesByPayload = {};
  final Map<String, String> _payloadTransferIds = {};
  final Map<String, String> endpointToDeviceId = {};
  final Map<String, String> deviceToEndpointId = {};
  final Map<String, NearbyConnectionState> peerStates = {};
  final Map<String, String> peerErrors = {};
  final Map<String, DeviceStatus> peerStatuses = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _closed = false;
  String? lastSentPacket;
  String? lastReceivedPacket;
  String? lastError;
  bool isAdvertising = false;
  bool isDiscovering = false;
  bool initialized = false;
  int acknowledgementCount = 0;
  int protocolErrorCount = 0;
  int transportErrorCount = 0;

  NearbyApplicationState get applicationState {
    if (lastError != null && transportErrorCount > 0) {
      return NearbyApplicationState.failed;
    }
    if (peerStates.values.contains(NearbyConnectionState.connecting)) {
      return NearbyApplicationState.connecting;
    }
    if (peerStates.values.contains(NearbyConnectionState.connected)) {
      return NearbyApplicationState.connected;
    }
    if (isDiscovering) return NearbyApplicationState.discovering;
    if (isAdvertising) return NearbyApplicationState.advertising;
    if (peerStates.values.contains(NearbyConnectionState.disconnected)) {
      return NearbyApplicationState.disconnected;
    }
    return NearbyApplicationState.idle;
  }

  List<NearbyPeer> get connectedPeers => discoveredPeers
      .where(
        (peer) =>
            peerStates[peer.endpointId] == NearbyConnectionState.connected,
      )
      .toList(growable: false);

  String? deviceIdForEndpoint(String endpointId) =>
      endpointToDeviceId[endpointId];

  Future<void> initialize() async {
    if (initialized) return;
    initialized = true;
    _subscriptions.add(transport.discoveredPeers.listen(_onPeer));
    _subscriptions.add(transport.incomingPayloads.listen(_onPayload));
    _subscriptions.add(transport.incomingFilePayloads.listen(_onFilePayload));
    _subscriptions.add(transport.transferEvents.listen(_onTransfer));
    _subscriptions.add(transport.connectionEvents.listen(_onConnection));
    _log('ใช้ transport: ${transport.implementationName}');
    notifyListeners();
  }

  Future<void> startAdvertising() async {
    if (isAdvertising) return;
    try {
      await transport.startAdvertising(
        displayName: await identity.getDisplayName(),
      );
      isAdvertising = true;
      _log('เริ่ม Advertising แล้ว');
      notifyListeners();
    } on Object catch (error) {
      _fail('เริ่ม Advertising ไม่สำเร็จ: $error');
    }
  }

  Future<void> stopAdvertising() async {
    if (!isAdvertising) return;
    try {
      await transport.stopAdvertising();
      isAdvertising = false;
      _log('หยุด Advertising แล้ว');
      notifyListeners();
    } on Object catch (error) {
      _fail('หยุด Advertising ไม่สำเร็จ: $error');
    }
  }

  Future<void> startDiscovery() async {
    if (isDiscovering) return;
    try {
      await transport.startDiscovery();
      isDiscovering = true;
      _log('เริ่ม Discovery แล้ว');
      notifyListeners();
    } on Object catch (error) {
      _fail('เริ่ม Discovery ไม่สำเร็จ: $error');
    }
  }

  Future<void> stopDiscovery() async {
    if (!isDiscovering) return;
    try {
      await transport.stopDiscovery();
      isDiscovering = false;
      _log('หยุด Discovery แล้ว');
      notifyListeners();
    } on Object catch (error) {
      _fail('หยุด Discovery ไม่สำเร็จ: $error');
    }
  }

  Future<void> connect(String peerId) async {
    final currentState = peerStates[peerId];
    if (currentState == NearbyConnectionState.connected ||
        currentState == NearbyConnectionState.connecting) {
      return;
    }
    peerStates[peerId] = NearbyConnectionState.connecting;
    notifyListeners();
    try {
      await transport.requestConnection(peerId);
      _log('ส่งคำขอเชื่อมต่อไปยัง $peerId');
    } on Object catch (error) {
      peerStates[peerId] = NearbyConnectionState.failed;
      peerErrors[peerId] = _safeError(error);
      _fail('เชื่อมต่อไม่สำเร็จ: $error');
    }
  }

  Future<void> disconnect(String peerId) async {
    try {
      await transport.disconnect(peerId);
      peerStates[peerId] = NearbyConnectionState.disconnected;
      _log('ตัดการเชื่อมต่อ $peerId');
    } on Object catch (error) {
      _fail('ตัดการเชื่อมต่อไม่สำเร็จ: $error');
    }
  }

  Future<DeviceStatus> currentStatus() async {
    final deviceId = await identity.getDeviceId();
    if (sos != null && await sos!.readActive(ownerDeviceId: deviceId) != null) {
      return DeviceStatus.sos;
    }
    if (settings != null &&
        await settings!.getBool('rescue_mode', defaultValue: false)) {
      return DeviceStatus.rescue;
    }
    return DeviceStatus.normal;
  }

  Future<void> sendHello({String? peerId}) async {
    final packet = RelioPacket.hello(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: 'minnie',
      displayName: await identity.getDisplayName(),
      status: await currentStatus(),
    );
    await _sendPacket(packet, description: 'Hello RELIO', peerId: peerId);
  }

  Future<void> propagateCurrentStatus() async {
    final deviceId = await identity.getDeviceId();
    final status = await currentStatus();
    await _sendPacket(
      RelioPacket.deviceStatus(
        senderDeviceId: deviceId,
        senderUserId: 'minnie',
        displayName: await identity.getDisplayName(),
        status: status,
      ),
      description: 'deviceStatus ${status.name}',
    );
    final active = await sos?.readActive(ownerDeviceId: deviceId);
    if (active != null) await sendSos(active);
  }

  Future<void> sendSos(RelioSosEvent event) async {
    await _sendPacket(
      RelioPacket.sos(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: event.ownerUserId,
        displayName: await identity.getDisplayName(),
        sosId: event.id,
        message: event.message,
        latitude: event.latitude,
        longitude: event.longitude,
        accuracyMeters: event.locationAccuracy,
        locationCapturedAt: event.locationCapturedAt,
        createdAt: event.createdAt,
        isActive: event.isActive,
      ),
      description: 'SOS ${event.id}',
    );
  }

  Future<void> sendTestText() async {
    await _sendPacket(
      RelioPacket.textMessage(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: 'minnie',
        messageId: const Uuid().v4(),
        conversationId: 'diagnostics',
        text: 'Hello RELIO',
        timestamp: DateTime.now(),
      ),
      description: 'test text',
      allowEmptyMock: true,
    );
  }

  Future<void> sendTestSos() async {
    await _sendPacket(
      RelioPacket.sos(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: 'minnie',
        displayName: await identity.getDisplayName(),
        sosId: const Uuid().v4(),
        message: 'TEST SOS จาก diagnostics',
        latitude: 13.7563,
        longitude: 100.5018,
        createdAt: DateTime.now(),
        isActive: true,
      ),
      description: 'test SOS',
      allowEmptyMock: true,
    );
  }

  Future<void> sendTestRescue() async {
    await _sendPacket(
      RelioPacket.deviceStatus(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: 'minnie',
        displayName: await identity.getDisplayName(),
        status: DeviceStatus.rescue,
      ),
      description: 'test Rescue status',
      allowEmptyMock: true,
    );
  }

  Future<void> sendMessage(RelioMessage message) async {
    final packet = RelioPacket.textMessage(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: message.senderId ?? 'minnie',
      messageId: message.id,
      conversationId: message.conversationId ?? 'somchai',
      text: message.text,
      timestamp: message.createdAt ?? DateTime.now(),
    );
    _packetMessageIds[packet.packetId] = message.id;
    final peerId = await _endpointForMessage(message);
    if (peerId == null && transport is! MockNearbyTransport) {
      lastError = 'ยังไม่พบการเชื่อมต่อของผู้รับข้อความ';
      _log('เก็บข้อความ ${message.id} ไว้ pending: peer ยังไม่ connected');
      notifyListeners();
      return;
    }
    try {
      await transport.sendBytes(packet.toBytes(), peerId: peerId);
      await messages.updateDeliveryStatus(
        message.id,
        DeliveryStatus.nearbySent,
      );
      lastSentPacket = _diagnosticPacket(packet);
      _log('ส่ง textMessage ${message.id} แล้ว');
      notifyListeners();
      if (transport is MockNearbyTransport &&
          (transport as MockNearbyTransport).autoAcknowledge) {
        final ack = RelioPacket.ack(
          senderDeviceId: await identity.getDeviceId(),
          senderUserId: 'mock-peer',
          acknowledgedPacketId: packet.packetId,
          messageId: message.id,
        );
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          (transport as MockNearbyTransport).simulateIncoming(
            peerId: peerId ?? 'mock-peer',
            bytes: ack.toBytes(),
          );
        });
      }
    } on Object catch (error) {
      await messages.markFailed(message.id, '$error');
      _fail('ส่งข้อความไม่สำเร็จ: $error');
    }
  }

  Future<void> sendLocationMessage(RelioMessage message) async {
    if (message.latitude == null || message.longitude == null) {
      await messages.markFailed(message.id, 'location_unavailable');
      return;
    }
    final peerId = await _endpointForMessage(message);
    if (peerId == null && transport is! MockNearbyTransport) return;
    final packet = RelioPacket.locationMessage(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: message.senderId ?? 'minnie',
      messageId: message.id,
      conversationId: message.conversationId ?? 'unknown',
      latitude: message.latitude!,
      longitude: message.longitude!,
      capturedAt: message.createdAt ?? DateTime.now(),
    );
    _packetMessageIds[packet.packetId] = message.id;
    try {
      await transport.sendBytes(packet.toBytes(), peerId: peerId);
      await messages.updateDeliveryStatus(
        message.id,
        DeliveryStatus.nearbySent,
      );
      lastSentPacket = _diagnosticPacket(packet);
      _log('ส่ง locationMessage ${message.id} แล้ว');
      if (transport is MockNearbyTransport &&
          (transport as MockNearbyTransport).autoAcknowledge) {
        final ack = RelioPacket.ack(
          senderDeviceId: await identity.getDeviceId(),
          senderUserId: 'mock-peer',
          acknowledgedPacketId: packet.packetId,
          messageId: message.id,
        );
        Future<void>.delayed(const Duration(milliseconds: 80), () {
          (transport as MockNearbyTransport).simulateIncoming(
            peerId: peerId ?? 'mock-peer',
            bytes: ack.toBytes(),
          );
        });
      }
    } on Object catch (error) {
      await messages.markFailed(message.id, '$error');
      _fail('ส่งตำแหน่งไม่สำเร็จ: $error');
    }
  }

  Future<void> sendMediaMessage(
    RelioMessage message,
    RelioMediaAttachment attachment,
  ) async {
    if (attachments == null || mediaStorage == null) return;
    final peerId = await _endpointForMessage(message);
    if (peerId == null && transport is! MockNearbyTransport) return;
    try {
      final payloadId = await transport.sendFile(
        attachment.localPath,
        peerId: peerId,
      );
      _payloadTransferIds[payloadId] = attachment.transferId;
      final packet = RelioPacket.mediaMetadata(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: message.senderId ?? 'minnie',
        messageId: message.id,
        attachmentId: attachment.id,
        transferId: attachment.transferId,
        mediaType: attachment.mediaType.name,
        fileName: attachment.fileName,
        mimeType: attachment.mimeType,
        byteSize: attachment.byteSize,
        payloadId: payloadId,
      );
      await transport.sendBytes(packet.toBytes(), peerId: peerId);
      await attachments!.updateProgress(
        attachment.id,
        status: MediaTransferState.transferring,
        bytesTransferred: 0,
      );
      await messages.updateDeliveryStatus(
        message.id,
        DeliveryStatus.nearbySent,
      );
      lastSentPacket = _diagnosticPacket(packet);
      _log('ส่ง mediaMetadata ${attachment.transferId} แล้ว');
      if (transport is MockNearbyTransport &&
          (transport as MockNearbyTransport).autoAcknowledge) {
        final ack = RelioPacket.mediaAck(
          senderDeviceId: await identity.getDeviceId(),
          senderUserId: 'mock-peer',
          messageId: message.id,
          attachmentId: attachment.id,
          transferId: attachment.transferId,
          status: 'completed',
        );
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          (transport as MockNearbyTransport).simulateIncoming(
            peerId: peerId ?? 'mock-peer',
            bytes: ack.toBytes(),
          );
        });
      }
    } on Object catch (error) {
      await attachments!.markFailed(attachment.id, 'send_failed');
      await messages.markFailed(message.id, '$error');
      _fail('ส่งสื่อไม่สำเร็จ: $error');
    }
  }

  Future<void> retryMessage(String messageId) async {
    final message = await messages.getMessage(messageId);
    if (message == null) return;
    await messages.updateDeliveryStatus(messageId, DeliveryStatus.pending);
    await sendMessage(message);
  }

  Future<String?> _endpointForMessage(RelioMessage message) async {
    final conversationId = message.conversationId;
    if (conversationId == null) return null;
    final conversation = await conversations.getConversation(conversationId);
    final deviceId = conversation?.participantId ?? conversationId;
    final exact = deviceToEndpointId[deviceId];
    if (exact != null) return exact;
    for (final peer in connectedPeers) {
      if (peer.endpointId == deviceId ||
          peer.name == conversation?.displayName) {
        return peer.endpointId;
      }
    }
    if (transport is MockNearbyTransport && connectedPeers.length == 1) {
      return connectedPeers.single.endpointId;
    }
    return null;
  }

  Future<void> _sendPacket(
    RelioPacket packet, {
    required String description,
    String? peerId,
    bool allowEmptyMock = false,
  }) async {
    try {
      if (peerId == null &&
          transport is! MockNearbyTransport &&
          connectedPeers.isEmpty) {
        throw const NearbyTransportException('No connected Nearby peer.');
      }
      if (peerId == null &&
          transport is MockNearbyTransport &&
          !allowEmptyMock &&
          packet.type != RelioPacketType.hello &&
          connectedPeers.isEmpty) {
        throw const NearbyTransportException('No connected mock peer.');
      }
      await transport.sendBytes(packet.toBytes(), peerId: peerId);
      lastSentPacket = _diagnosticPacket(packet);
      _log('ส่ง $description แล้ว');
      notifyListeners();
    } on Object catch (error) {
      _fail('ส่ง packet ไม่สำเร็จ: $error');
    }
  }

  void clearLog() {
    eventLog.clear();
    lastError = null;
    notifyListeners();
  }

  void _onPeer(NearbyPeer peer) {
    final index = discoveredPeers.indexWhere((item) => item.id == peer.id);
    if (index == -1) {
      discoveredPeers.add(peer);
    } else {
      discoveredPeers[index] = peer;
    }
    peerStates.putIfAbsent(
      peer.endpointId,
      () => peer.connected
          ? NearbyConnectionState.connected
          : NearbyConnectionState.disconnected,
    );
    _log('พบ peer ${peer.name} (${peer.endpointId})');
    notifyListeners();
  }

  void _onConnection(NearbyConnectionEvent event) {
    final endpointId = event.peer.endpointId;
    peerStates[endpointId] = event.state;
    if (event.state == NearbyConnectionState.connected) {
      final index = discoveredPeers.indexWhere((item) => item.id == endpointId);
      final peer = NearbyPeer(
        id: endpointId,
        name: event.peer.name,
        connected: true,
        deviceId: endpointToDeviceId[endpointId],
      );
      if (index == -1) {
        discoveredPeers.add(peer);
      } else {
        discoveredPeers[index] = peer;
      }
      if (sos != null && settings != null) {
        unawaited(sendHello(peerId: endpointId));
      }
    } else if (event.state == NearbyConnectionState.disconnected) {
      final deviceId = endpointToDeviceId.remove(endpointId);
      if (deviceId != null) deviceToEndpointId.remove(deviceId);
    } else if (event.state == NearbyConnectionState.failed) {
      peerErrors[endpointId] = event.error ?? 'connection failed';
    }
    if (event.error != null) peerErrors[endpointId] = event.error!;
    _log('${event.peer.name}: ${event.state.name}');
    notifyListeners();
  }

  void _onPayload(NearbyPayloadEvent event) {
    unawaited(_handlePayload(event));
  }

  void _onFilePayload(NearbyFilePayloadEvent event) {
    _mediaFilesByPayload[event.payloadId] = event;
    unawaited(_tryCompleteIncomingMedia(event.payloadId));
  }

  void _onTransfer(NearbyTransferEvent event) {
    final transferId = _payloadTransferIds[event.payloadId];
    if (transferId == null || attachments == null) return;
    unawaited(_updateOutgoingTransfer(transferId, event));
  }

  Future<void> _updateOutgoingTransfer(
    String transferId,
    NearbyTransferEvent event,
  ) async {
    final attachment = await attachments!.getByTransferId(transferId);
    if (attachment == null) return;
    final status = switch (event.status) {
      NearbyTransferStatus.started ||
      NearbyTransferStatus.inProgress => MediaTransferState.transferring,
      NearbyTransferStatus.success => MediaTransferState.transferring,
      NearbyTransferStatus.failure => MediaTransferState.failed,
      NearbyTransferStatus.cancelled => MediaTransferState.cancelled,
    };
    await attachments!.updateProgress(
      attachment.id,
      status: status,
      bytesTransferred: event.bytesTransferred,
      errorCode: event.error,
    );
    if (status == MediaTransferState.failed ||
        status == MediaTransferState.cancelled) {
      await messages.markFailed(
        attachment.messageId,
        event.error ?? 'transfer_failed',
      );
    }
    notifyListeners();
  }

  Future<void> _handlePayload(NearbyPayloadEvent event) async {
    try {
      final packet = RelioPacket.fromBytes(event.bytes);
      endpointToDeviceId[event.peerId] = packet.senderDeviceId;
      deviceToEndpointId[packet.senderDeviceId] = event.peerId;
      // Packet อาจมีข้อความ/SOS/พิกัดส่วนตัว จึงเก็บ diagnostics แค่ type กับ ID
      // และไม่เปิดเผย payload ใน log ปกติ
      lastReceivedPacket = _diagnosticPacket(packet);
      _log('รับ ${packet.type.name} จาก ${event.peerId}');
      switch (packet.type) {
        case RelioPacketType.hello:
          await _handleHello(event.peerId, packet);
        case RelioPacketType.textMessage:
          await _handleText(event.peerId, packet);
        case RelioPacketType.deviceStatus:
          await _handleDeviceStatus(packet);
        case RelioPacketType.ack:
          await _handleAck(packet);
        case RelioPacketType.sos:
          await _handleSos(event.peerId, packet);
        case RelioPacketType.mediaMetadata:
          await _handleMediaMetadata(event.peerId, packet);
        case RelioPacketType.mediaAck:
          await _handleMediaAck(packet);
        case RelioPacketType.locationMessage:
          await _handleLocation(event.peerId, packet);
        case RelioPacketType.relayEnvelope:
          await relayEngine?.handleIncomingPacket(event.peerId, packet);
        case RelioPacketType.relayAck:
          await relayEngine?.handleIncomingPacket(event.peerId, packet);
      }
      notifyListeners();
    } on RelioPacketException catch (error) {
      protocolErrorCount += 1;
      _fail('packet ไม่ถูกต้อง: ${error.message}');
    } on Object catch (error) {
      _fail('ประมวลผล packet ไม่สำเร็จ: $error');
    }
  }

  Future<void> _handleMediaMetadata(
    String endpointId,
    RelioPacket packet,
  ) async {
    final payloadId = packet.payload['payloadId'] as String?;
    if (payloadId == null || payloadId.isEmpty) {
      _fail('mediaMetadata ไม่มี payloadId');
      return;
    }
    _mediaMetadataByPayload[payloadId] = packet;
    await _tryCompleteIncomingMedia(payloadId);
  }

  Future<void> _tryCompleteIncomingMedia(String payloadId) async {
    final packet = _mediaMetadataByPayload[payloadId];
    final file = _mediaFilesByPayload[payloadId];
    if (packet == null ||
        file == null ||
        attachments == null ||
        mediaStorage == null) {
      return;
    }
    final payload = packet.payload;
    try {
      final storedPath = await mediaStorage!.storeIncomingFile(
        sourcePath: file.filePath,
        fileName: payload['fileName']! as String,
        expectedMimeType: payload['mimeType']! as String,
        expectedBytes: (payload['byteSize']! as num).toInt(),
      );
      final conversationId = await _conversationIdForDevice(
        packet.senderDeviceId,
        packet.senderDeviceId,
      );
      await conversations.ensureConversation(
        id: conversationId,
        participantId: packet.senderDeviceId,
        displayName: _peerName(file.peerId, packet.senderUserId),
        participantStatus: DeviceStatus.normal,
      );
      final message = await messages.createIncomingMedia(
        conversationId: conversationId,
        senderId: packet.senderUserId,
        senderDeviceId: packet.senderDeviceId,
        messageId: payload['messageId']! as String,
        type: _mediaMessageType(payload['mediaType']! as String),
        fileName: payload['fileName']! as String,
        localPath: storedPath,
      );
      final attachmentId = payload['attachmentId']! as String;
      if (await attachments!.getById(attachmentId) == null) {
        await attachments!.createPending(
          id: attachmentId,
          messageId: message.id,
          transferId: payload['transferId']! as String,
          mediaType: _mediaType(payload['mediaType']! as String),
          fileName: payload['fileName']! as String,
          mimeType: payload['mimeType']! as String,
          localPath: storedPath,
          byteSize: (payload['byteSize']! as num).toInt(),
        );
      }
      await attachments!.markCompleted(attachmentId, localPath: storedPath);
      await _sendMediaAck(file.peerId, packet, 'completed');
      _mediaMetadataByPayload.remove(payloadId);
      _mediaFilesByPayload.remove(payloadId);
    } on Object catch (error) {
      _fail('รับไฟล์ไม่สำเร็จ: $error');
      await _sendMediaAck(
        file.peerId,
        packet,
        'failed',
        errorCode: 'invalid_file',
      );
    }
  }

  Future<void> _handleMediaAck(RelioPacket packet) async {
    final transferId = packet.payload['transferId']! as String;
    final attachment = await attachments?.getByTransferId(transferId);
    if (attachment == null) return;
    final status = packet.payload['status']! as String;
    if (status == 'completed') {
      await attachments?.markCompleted(attachment.id);
      await messages.updateDeliveryStatus(
        attachment.messageId,
        DeliveryStatus.delivered,
      );
      acknowledgementCount += 1;
    } else if (status == 'failed') {
      await attachments?.markFailed(
        attachment.id,
        packet.payload['errorCode'] as String? ?? 'remote_failed',
      );
      await messages.markFailed(attachment.messageId, 'remote_failed');
    }
  }

  Future<void> _handleLocation(String endpointId, RelioPacket packet) async {
    final payload = packet.payload;
    final conversationId = await _conversationIdForDevice(
      packet.senderDeviceId,
      payload['conversationId']! as String,
    );
    await conversations.ensureConversation(
      id: conversationId,
      participantId: packet.senderDeviceId,
      displayName: _peerName(endpointId, packet.senderUserId),
      participantStatus: DeviceStatus.normal,
    );
    await messages.createIncomingLocation(
      conversationId: conversationId,
      senderId: packet.senderUserId,
      senderDeviceId: packet.senderDeviceId,
      messageId: payload['messageId']! as String,
      location: LocationData(
        latitude: (payload['latitude']! as num).toDouble(),
        longitude: (payload['longitude']! as num).toDouble(),
        accuracyMeters: (payload['accuracyMeters'] as num?)?.toDouble(),
        capturedAt: DateTime.parse(payload['capturedAt']! as String),
        source: 'nearby',
      ),
    );
    await _sendAck(endpointId, packet);
  }

  Future<void> _sendMediaAck(
    String endpointId,
    RelioPacket source,
    String status, {
    String? errorCode,
  }) async {
    final payload = source.payload;
    final ack = RelioPacket.mediaAck(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: 'minnie',
      messageId: payload['messageId']! as String,
      attachmentId: payload['attachmentId']! as String,
      transferId: payload['transferId']! as String,
      status: status,
      errorCode: errorCode,
    );
    await transport.sendBytes(ack.toBytes(), peerId: endpointId);
    lastSentPacket = _diagnosticPacket(ack);
    acknowledgementCount += 1;
  }

  Future<void> _handleHello(String endpointId, RelioPacket packet) async {
    final status = _statusFrom(packet.payload['status'] as String);
    peerStatuses[packet.senderDeviceId] = status;
    final displayName = packet.payload['displayName']! as String;
    await nearbyDevices.upsert(
      deviceId: packet.senderDeviceId,
      displayName: displayName,
      status: status,
    );
    await conversations.updateParticipantStatus(packet.senderDeviceId, status);
    _updatePeerIdentity(
      endpointId,
      packet.senderDeviceId,
      displayName: displayName,
      capabilities: _capabilitiesFrom(packet.payload['capabilities']),
    );
    _log('จับคู่ endpoint $endpointId ↔ ${packet.senderDeviceId}');
  }

  Future<void> _handleText(String endpointId, RelioPacket packet) async {
    final conversationId = await _conversationIdForDevice(
      packet.senderDeviceId,
      packet.payload['conversationId']! as String,
    );
    await conversations.ensureConversation(
      id: conversationId,
      participantId: packet.senderDeviceId,
      displayName: _peerName(endpointId, packet.senderUserId),
      participantStatus: DeviceStatus.normal,
    );
    await messages.createIncomingText(
      conversationId: conversationId,
      senderId: packet.senderUserId,
      senderDeviceId: packet.senderDeviceId,
      messageId: packet.payload['messageId']! as String,
      text: packet.payload['text']! as String,
      createdAt: DateTime.parse(packet.payload['timestamp']! as String),
    );
    await _sendAck(endpointId, packet);
  }

  Future<void> _handleDeviceStatus(RelioPacket packet) async {
    final status = _statusFrom(packet.payload['status']! as String);
    peerStatuses[packet.senderDeviceId] = status;
    final displayName = packet.payload['displayName']! as String;
    await nearbyDevices.upsert(
      deviceId: packet.senderDeviceId,
      displayName: displayName,
      status: status,
    );
    await conversations.updateParticipantStatus(packet.senderDeviceId, status);
    _updatePeerIdentity(
      deviceToEndpointId[packet.senderDeviceId],
      packet.senderDeviceId,
      displayName: displayName,
    );
  }

  Future<void> _handleAck(RelioPacket packet) async {
    final messageId =
        packet.payload['messageId'] as String? ??
        _packetMessageIds[packet.payload['packetId']];
    if (messageId == null) return;
    final message = await messages.getMessage(messageId);
    if (message == null || message.status == DeliveryStatus.delivered) return;
    await messages.updateDeliveryStatus(messageId, DeliveryStatus.delivered);
    acknowledgementCount += 1;
    _log('รับ ACK ของข้อความ $messageId');
  }

  Future<void> _handleSos(String endpointId, RelioPacket packet) async {
    if (sos == null) {
      _fail('รับ SOS ไม่ได้: SOS repository ไม่พร้อมใช้งาน');
      return;
    }
    final payload = packet.payload;
    final event = await sos!.createIncoming(
      id: payload['sosId']! as String,
      ownerDeviceId: payload['ownerDeviceId']! as String,
      ownerUserId: payload['ownerUserId']! as String,
      message: payload['message'] as String?,
      latitude: (payload['latitude'] as num?)?.toDouble(),
      longitude: (payload['longitude'] as num?)?.toDouble(),
      locationAccuracy: (payload['accuracyMeters'] as num?)?.toDouble(),
      locationCapturedAt: payload['locationCapturedAt'] == null
          ? null
          : DateTime.tryParse(payload['locationCapturedAt']! as String),
      createdAt: DateTime.parse(payload['createdAt']! as String),
      isActive: payload['isActive']! as bool,
    );
    final displayName = payload['displayName']! as String;
    final status = event.isActive ? DeviceStatus.sos : DeviceStatus.normal;
    peerStatuses[event.ownerDeviceId] = status;
    await nearbyDevices.upsert(
      deviceId: event.ownerDeviceId,
      displayName: displayName,
      status: status,
    );
    final conversationId = await _conversationIdForDevice(
      event.ownerDeviceId,
      event.ownerDeviceId,
    );
    await conversations.ensureConversation(
      id: conversationId,
      participantId: event.ownerDeviceId,
      displayName: displayName,
      participantStatus: status,
    );
    _updatePeerIdentity(
      endpointId,
      event.ownerDeviceId,
      displayName: displayName,
    );
    _log(
      event.isActive
          ? 'SOS RECEIVED จาก $displayName'
          : 'SOS cleared จาก $displayName',
    );
    await _sendAck(endpointId, packet);
  }

  Future<void> _sendAck(String endpointId, RelioPacket packet) async {
    final ack = RelioPacket.ack(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: 'minnie',
      acknowledgedPacketId: packet.packetId,
      messageId: packet.payload['messageId'] as String?,
    );
    await transport.sendBytes(ack.toBytes(), peerId: endpointId);
    lastSentPacket = _diagnosticPacket(ack);
    acknowledgementCount += 1;
  }

  Future<String> _conversationIdForDevice(
    String deviceId,
    String fallback,
  ) async {
    final existing = (await conversations.listConversations())
        .where((conversation) => conversation.participantId == deviceId)
        .toList();
    return existing.isEmpty ? fallback : existing.first.id;
  }

  String _peerName(String endpointId, String fallback) {
    final matches = discoveredPeers.where((peer) => peer.id == endpointId);
    return matches.isEmpty ? fallback : matches.first.name;
  }

  void _updatePeerIdentity(
    String? endpointId,
    String deviceId, {
    String? displayName,
    List<String>? capabilities,
  }) {
    if (endpointId == null) return;
    endpointToDeviceId[endpointId] = deviceId;
    deviceToEndpointId[deviceId] = endpointId;
    final index = discoveredPeers.indexWhere((peer) => peer.id == endpointId);
    if (index == -1) return;
    final peer = discoveredPeers[index];
    discoveredPeers[index] = NearbyPeer(
      id: endpointId,
      name: displayName ?? peer.name,
      connected:
          peer.connected ||
          peerStates[endpointId] == NearbyConnectionState.connected,
      deviceId: deviceId,
      capabilities: capabilities ?? peer.capabilities,
    );
  }

  List<String> _capabilitiesFrom(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  DeviceStatus _statusFrom(String value) => DeviceStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => DeviceStatus.normal,
  );

  MessageType _mediaMessageType(String value) => switch (value) {
    'video' => MessageType.video,
    _ => MessageType.image,
  };

  MediaType _mediaType(String value) => switch (value) {
    'video' => MediaType.video,
    _ => MediaType.image,
  };

  String _safeError(Object error) => error is NearbyTransportException
      ? error.message
      : error.toString().replaceFirst('Exception: ', '');

  String _diagnosticPacket(RelioPacket packet) => jsonEncode({
    'type': packet.type.name,
    'packetId': packet.packetId,
    'senderDeviceId': packet.senderDeviceId,
  });

  void _log(String message) {
    eventLog.insert(0, '${DateTime.now().toIso8601String()} $message');
    if (eventLog.length > 80) eventLog.removeLast();
  }

  void _fail(String message) {
    lastError = message;
    _log('ERROR: $message');
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    unawaited(close());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    await transport.dispose();
  }
}
