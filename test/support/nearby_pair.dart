import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:relio_mobile/core/media/media_storage_service.dart';
import 'package:relio_mobile/core/notifications/local_notification_service.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/device/battery_info_service.dart';

import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/diagnostics/diagnostics_log_service.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/peer_identity_crypto.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';

Future<void> waitFor(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Expected state was not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<List<Map<String, dynamic>>> readEvents(
  DiagnosticsLogService logs,
) async {
  await logs.flush();
  final logFile = File(
    '${logs.directory!.path}${Platform.pathSeparator}diagnostics.jsonl',
  );
  return (await logFile.readAsLines())
      .where((line) => line.isNotEmpty)
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList();
}

class HandshakePair {
  HandshakePair._({
    required this.databaseA,
    required this.databaseB,
    required this.repositoriesA,
    required this.repositoriesB,
    required this.identityA,
    required this.identityB,
    required this.transportA,
    required this.transportB,
    required this.cryptoA,
    required this.cryptoB,
    required this.serviceA,
    required this.serviceB,
    required this.logsA,
    required this.logsB,
  });

  final AppDatabase databaseA;
  final AppDatabase databaseB;
  final RelioRepositories repositoriesA;
  final RelioRepositories repositoriesB;
  final RelioDeviceIdentityRepository identityA;
  final RelioDeviceIdentityRepository identityB;
  LoopbackTransport transportA;
  LoopbackTransport transportB;
  final TestIdentityCrypto cryptoA;
  final TestIdentityCrypto cryptoB;
  NearbyService serviceA;
  NearbyService serviceB;
  final DiagnosticsLogService logsA;
  final DiagnosticsLogService logsB;

  static Future<HandshakePair> create({
    LocalNotificationSink? notificationsA,
    LocalNotificationSink? notificationsB,
    Duration handshakeTimeout = const Duration(seconds: 30),
    Duration hardNegotiationTimeout = const Duration(seconds: 90),
    Duration incomingApprovalTimeout = const Duration(minutes: 2),
    bool dropPayloads = false,
    bool corruptSignatureB = false,
    String displayNameA = 'สมชาย',
    String? displayNameB,
    BatteryInfoService? batteryInfoA,
    BatteryInfoService? batteryInfoB,
    bool requireBothNativeAccepts = false,
    String? Function()? currentUserIdProviderA,
    Stream<Object?>? ownerChangesA,
  }) async {
    final databaseA = AppDatabase.memory();
    final databaseB = AppDatabase.memory();
    await _setDeviceId(databaseA, 'device-a');
    await _setDeviceId(databaseB, 'device-b');
    final repositoriesA = RelioRepositories(
      databaseA,
      ownerUserIdProvider: currentUserIdProviderA,
      ownerScopeChanges: ownerChangesA,
    );
    final repositoriesB = RelioRepositories(databaseB);
    final identityA = RelioDeviceIdentityRepository(
      databaseA,
      profiles: repositoriesA.profiles,
    );
    final identityB = RelioDeviceIdentityRepository(
      databaseB,
      profiles: repositoriesB.profiles,
    );
    await identityA.setDisplayName(displayNameA);
    if (displayNameB != null) await identityB.setDisplayName(displayNameB);
    final cryptoA = TestIdentityCrypto('device-a');
    final cryptoB = TestIdentityCrypto(
      'device-b',
      corruptSignatures: corruptSignatureB,
    );
    final transportA = LoopbackTransport(
      localEndpointId: 'endpoint-b',
      remoteEndpointId: 'endpoint-a',
      displayName: displayNameA,
      localFingerprint: (await cryptoA.getPublicIdentity()).fingerprint,
      remoteFingerprint: (await cryptoB.getPublicIdentity()).fingerprint,
      dropPayloads: dropPayloads,
      requireBothNativeAccepts: requireBothNativeAccepts,
    );
    final transportB = LoopbackTransport(
      localEndpointId: 'endpoint-a',
      remoteEndpointId: 'endpoint-b',
      displayName: displayNameB ?? 'Phone B',
      localFingerprint: (await cryptoB.getPublicIdentity()).fingerprint,
      remoteFingerprint: (await cryptoA.getPublicIdentity()).fingerprint,
      dropPayloads: dropPayloads,
      requireBothNativeAccepts: requireBothNativeAccepts,
    );
    transportA.other = transportB;
    transportB.other = transportA;
    final logsA = DiagnosticsLogService(
      directory: await Directory.systemTemp.createTemp('relio-identity-a-'),
    );
    final logsB = DiagnosticsLogService(
      directory: await Directory.systemTemp.createTemp('relio-identity-b-'),
    );
    await logsA.initialize();
    await logsB.initialize();
    final serviceA = NearbyService(
      transport: transportA,
      messages: repositoriesA.messages,
      conversations: repositoriesA.conversations,
      identity: identityA,
      nearbyDevices: repositoriesA.nearbyDevices,
      identityCrypto: cryptoA,
      currentUserIdProvider: currentUserIdProviderA,
      diagnostics: logsA,
      handshakeTimeout: handshakeTimeout,
      hardNegotiationTimeout: hardNegotiationTimeout,
      incomingApprovalTimeout: incomingApprovalTimeout,
      attachments: repositoriesA.attachments,
      mediaStorage: MediaStorageService(
        rootDirectory: Directory('${logsA.directory!.path}/media'),
      ),
      settings: repositoriesA.settings,
      localNotifications: notificationsA,
      batteryInfo: batteryInfoA,
    );
    final serviceB = NearbyService(
      transport: transportB,
      messages: repositoriesB.messages,
      conversations: repositoriesB.conversations,
      identity: identityB,
      nearbyDevices: repositoriesB.nearbyDevices,
      identityCrypto: cryptoB,
      diagnostics: logsB,
      handshakeTimeout: handshakeTimeout,
      hardNegotiationTimeout: hardNegotiationTimeout,
      incomingApprovalTimeout: incomingApprovalTimeout,
      attachments: repositoriesB.attachments,
      mediaStorage: MediaStorageService(
        rootDirectory: Directory('${logsB.directory!.path}/media'),
      ),
      settings: repositoriesB.settings,
      localNotifications: notificationsB,
      batteryInfo: batteryInfoB,
    );
    transportA.incomingDirectory = logsA.directory!;
    transportB.incomingDirectory = logsB.directory!;
    await serviceA.initialize();
    await serviceB.initialize();
    // Pair creation represents endpoints already visible in this test harness.
    transportA.discoverPeer();
    transportB.discoverPeer();
    await Future<void>.delayed(Duration.zero);
    return HandshakePair._(
      databaseA: databaseA,
      databaseB: databaseB,
      repositoriesA: repositoriesA,
      repositoriesB: repositoriesB,
      identityA: identityA,
      identityB: identityB,
      transportA: transportA,
      transportB: transportB,
      cryptoA: cryptoA,
      cryptoB: cryptoB,
      serviceA: serviceA,
      serviceB: serviceB,
      logsA: logsA,
      logsB: logsB,
    );
  }

  Future<RelioPacket> packetFromA(RelioPacket packet) async =>
      packet.withPrincipals(
        (await repositoriesA.profiles.current()).principalId,
        (await repositoriesB.profiles.current()).principalId,
      );

  Future<void> restartServices() async {
    final oldA = transportA;
    final oldB = transportB;
    final accountA = serviceA.currentUserIdProvider;
    final timeout = serviceA.handshakeTimeout;
    await serviceA.close();
    await serviceB.close();
    transportA = LoopbackTransport(
      localEndpointId: oldA.localEndpointId,
      remoteEndpointId: oldA.remoteEndpointId,
      displayName: await identityA.getDisplayName(),
      localFingerprint: (await cryptoA.getPublicIdentity()).fingerprint,
      remoteFingerprint: (await cryptoB.getPublicIdentity()).fingerprint,
      requireBothNativeAccepts: oldA.requireBothNativeAccepts,
    );
    transportB = LoopbackTransport(
      localEndpointId: oldB.localEndpointId,
      remoteEndpointId: oldB.remoteEndpointId,
      displayName: await identityB.getDisplayName(),
      localFingerprint: (await cryptoB.getPublicIdentity()).fingerprint,
      remoteFingerprint: (await cryptoA.getPublicIdentity()).fingerprint,
      requireBothNativeAccepts: oldB.requireBothNativeAccepts,
    );
    transportA.other = transportB;
    transportB.other = transportA;
    transportA.incomingDirectory = logsA.directory!;
    transportB.incomingDirectory = logsB.directory!;
    serviceA = NearbyService(
      transport: transportA,
      messages: repositoriesA.messages,
      conversations: repositoriesA.conversations,
      identity: identityA,
      nearbyDevices: repositoriesA.nearbyDevices,
      identityCrypto: cryptoA,
      diagnostics: logsA,
      handshakeTimeout: timeout,
      attachments: repositoriesA.attachments,
      mediaStorage: MediaStorageService(
        rootDirectory: Directory('${logsA.directory!.path}/media'),
      ),
      settings: repositoriesA.settings,
      currentUserIdProvider: accountA,
    );
    serviceB = NearbyService(
      transport: transportB,
      messages: repositoriesB.messages,
      conversations: repositoriesB.conversations,
      identity: identityB,
      nearbyDevices: repositoriesB.nearbyDevices,
      identityCrypto: cryptoB,
      diagnostics: logsB,
      handshakeTimeout: timeout,
      attachments: repositoriesB.attachments,
      mediaStorage: MediaStorageService(
        rootDirectory: Directory('${logsB.directory!.path}/media'),
      ),
      settings: repositoriesB.settings,
    );
    await serviceA.initialize();
    await serviceB.initialize();
    transportA.discoverPeer();
    transportB.discoverPeer();
  }

  Future<void> close() async {
    await serviceA.close();
    await serviceB.close();
    await databaseA.close();
    await databaseB.close();
    await logsA.flush();
    await logsB.flush();
    await logsA.directory?.delete(recursive: true);
    await logsB.directory?.delete(recursive: true);
  }
}

Future<void> _setDeviceId(AppDatabase database, String id) => database
    .into(database.appSettings)
    .insert(
      AppSettingsCompanion.insert(
        key: 'device_id',
        value: id,
        updatedAt: DateTime.now(),
      ),
    );

class TestIdentityCrypto implements PeerIdentityCrypto {
  TestIdentityCrypto(this.deviceId, {this.corruptSignatures = false})
    : _publicKey = 'test-public-key:$deviceId';

  final String deviceId;
  final bool corruptSignatures;
  String _publicKey;
  void rotateIdentity() => _publicKey = 'test-public-key:$deviceId-rotated';
  String _signature(Uint8List message, String publicKey) =>
      sha256.convert([...utf8.encode(publicKey), 0, ...message]).toString();

  @override
  Future<PeerPublicIdentity> getPublicIdentity() async => PeerPublicIdentity(
    publicKey: _publicKey,
    fingerprint: sha256.convert(utf8.encode(_publicKey)).toString(),
  );

  @override
  Future<String> sign(Uint8List message) async =>
      corruptSignatures ? 'invalid-signature' : _signature(message, _publicKey);

  @override
  Future<String> fingerprint(String publicKey) async =>
      sha256.convert(utf8.encode(publicKey)).toString();

  int verifyCalls = 0;
  Completer<void>? verificationGate;

  @override
  Future<bool> verify({
    required String publicKey,
    required Uint8List message,
    required String signature,
  }) async {
    verifyCalls++;
    await verificationGate?.future;
    return signature == _signature(message, publicKey);
  }
}

class LoopbackTransport implements NearbyTransport, NearbyIdleSessionRecovery {
  LoopbackTransport({
    required this.localEndpointId,
    required this.remoteEndpointId,
    required this.displayName,
    required this.localFingerprint,
    required this.remoteFingerprint,
    this.dropPayloads = false,
    this.requireBothNativeAccepts = false,
  });

  String localEndpointId;
  String remoteEndpointId;
  final String displayName;
  final String localFingerprint;
  final String remoteFingerprint;
  final bool dropPayloads;
  final bool requireBothNativeAccepts;
  final _peers = StreamController<NearbyPeer>.broadcast();
  final _payloads = StreamController<NearbyPayloadEvent>.broadcast();
  final _connections = StreamController<NearbyConnectionEvent>.broadcast();
  final _nativeDiagnostics =
      StreamController<NearbyNativeDiagnostic>.broadcast();
  final _files = StreamController<NearbyFilePayloadEvent>.broadcast();
  final _transfers = StreamController<NearbyTransferEvent>.broadcast();
  final List<String> sentPackets = [];
  final List<RelioPacket> packets = [];
  final Map<String, Uint8List> pendingFiles = {};
  late Directory incomingDirectory;
  bool fileBeforeMetadata = false;
  bool holdFiles = false;
  bool corruptFile = false;
  int fileSequence = 0;

  void receivePacket(RelioPacket packet) => _payloads.add(
    NearbyPayloadEvent(peerId: localEndpointId, bytes: packet.toBytes()),
  );

  Future<void> deliverFiles() async {
    for (final entry in pendingFiles.entries.toList()) {
      final bytes = Uint8List.fromList(entry.value);
      if (corruptFile) bytes[bytes.length - 1] ^= 1;
      final file = File(
        '${other!.incomingDirectory.path}/payload-${entry.key}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      other!._files.add(
        NearbyFilePayloadEvent(
          peerId: other!.localEndpointId,
          payloadId: entry.key,
          filePath: file.path,
        ),
      );
      pendingFiles.remove(entry.key);
    }
  }

  void failTransfers() {
    for (final entry in pendingFiles.entries) {
      _transfers.add(
        NearbyTransferEvent(
          peerId: localEndpointId,
          payloadId: entry.key,
          status: NearbyTransferStatus.failure,
          bytesTransferred: entry.value.length ~/ 2,
          totalBytes: entry.value.length,
          error: 'test_interrupted',
        ),
      );
    }
    pendingFiles.clear();
  }

  final Set<String> acceptedConnections = {};
  final List<String> acceptCalls = [];
  final List<String> disconnectCalls = [];
  int requestCalls = 0;
  int idleEndpointClearCalls = 0;
  int stopDiscoveryCalls = 0;
  int startDiscoveryCalls = 0;
  int startAdvertisingCalls = 0;
  int _discoveryEpoch = 0;
  NearbyTransportTestMode _testMode = NearbyTransportTestMode.clusterBaseline;
  int stopAdvertisingCalls = 0;
  bool omitIncomingFingerprintHint = false;
  bool failNextRequest = false;
  late final Map<String, NearbyPeer> _knownPeers = {
    localEndpointId: NearbyPeer(
      id: localEndpointId,
      name: displayName,
      identityFingerprintHint: remoteFingerprint,
    ),
  };
  LoopbackTransport? other;
  bool _connected = false;
  bool _disposed = false;
  bool isDiscovering = false;
  bool isAdvertising = false;

  @override
  String get implementationName => 'IdentityHandshakeLoopback';
  @override
  String get serviceId => relioNearbyServiceId;
  @override
  String get strategyName => _testMode.strategyName;
  @override
  NearbyTransportTestMode get testMode => _testMode;
  @override
  int get discoveryEpoch => _discoveryEpoch;
  @override
  Stream<NearbyPeer> get discoveredPeers => _peers.stream;
  @override
  Stream<NearbyPayloadEvent> get incomingPayloads => _payloads.stream;
  @override
  Stream<NearbyFilePayloadEvent> get incomingFilePayloads => _files.stream;
  @override
  Stream<NearbyTransferEvent> get transferEvents => _transfers.stream;
  @override
  Stream<NearbyConnectionEvent> get connectionEvents => _connections.stream;
  @override
  Stream<NearbyNativeDiagnostic> get nativeDiagnostics =>
      _nativeDiagnostics.stream;
  @override
  Future<Map<String, Object?>> diagnosticSnapshot() async => const {};

  @override
  Future<void> configureTestMode(NearbyTransportTestMode mode) async {
    _testMode = mode;
  }

  void discoverPeer() {
    final now = DateTime.now().toUtc();
    final previous = _knownPeers[localEndpointId]!;
    final refreshed = NearbyPeer(
      id: previous.id,
      name: previous.name,
      identityFingerprintHint: previous.identityFingerprintHint,
      discoveryEpoch: _discoveryEpoch,
      foundAt: previous.discoveryEpoch == _discoveryEpoch
          ? previous.foundAt ?? now
          : now,
      lastSeenAt: now,
      isCurrent: true,
    );
    _knownPeers[localEndpointId] = refreshed;
    _peers.add(refreshed);
  }

  void discoverAlias(NearbyPeer peer) => _peers.add(peer);
  bool omitLocalDisconnectCallback = false;
  Completer<void>? requestGate;
  Completer<void>? acceptGate;
  Completer<void>? disconnectGate;
  bool holdConnectionResult = false;

  void completeConnection() => _connectedBoth();

  void emitConnectionEvent(NearbyConnectionEvent event) =>
      _connections.add(event);

  void changeEndpointIds({required String local, required String remote}) {
    localEndpointId = local;
    remoteEndpointId = remote;
    _knownPeers
      ..clear()
      ..[local] = NearbyPeer(
        id: local,
        name: displayName,
        identityFingerprintHint: remoteFingerprint,
      );
    acceptedConnections.clear();
  }

  void refreshPeerName(String name) {
    final peer = _knownPeers[localEndpointId]!;
    final refreshed = NearbyPeer(
      id: peer.id,
      name: name,
      identityFingerprintHint: peer.identityFingerprintHint,
      discoveryEpoch: _discoveryEpoch,
      foundAt: peer.foundAt,
      lastSeenAt: DateTime.now().toUtc(),
      isCurrent: true,
    );
    _knownPeers[localEndpointId] = refreshed;
    _peers.add(refreshed);
  }

  void clearDiscoveredFingerprintHint() {
    final peer = _knownPeers[localEndpointId]!;
    _knownPeers[localEndpointId] = NearbyPeer(id: peer.id, name: peer.name);
  }

  void simulateIncomingRequest({
    required String name,
    required String? fingerprint,
  }) {
    _connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(
          id: localEndpointId,
          name: name,
          identityFingerprintHint: fingerprint,
        ),
        state: NearbyConnectionState.incomingRequest,
        isIncomingRequest: true,
      ),
    );
  }

  void failConnection() {
    acceptedConnections.clear();
    other!.acceptedConnections.clear();
    for (final transport in [this, other!]) {
      transport._connections.add(
        NearbyConnectionEvent(
          peer: transport._knownPeers[transport.localEndpointId]!,
          state: NearbyConnectionState.failed,
          rawStatusCode: 13,
          rawStatusName: 'ERROR',
          error: 'ERROR',
        ),
      );
    }
  }

  void repeatDisconnectedCallback([String? endpointId]) {
    final id = endpointId ?? localEndpointId;
    _connections.add(
      NearbyConnectionEvent(
        peer: _knownPeers[id] ?? NearbyPeer(id: id, name: displayName),
        state: NearbyConnectionState.disconnected,
      ),
    );
  }

  void _connectedBoth() {
    if (_connected) return;
    _connected = true;
    final peer = _knownPeers[localEndpointId]!;
    _connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(id: peer.id, name: peer.name, connected: true),
        state: NearbyConnectionState.connected,
      ),
    );
    final remote = other!;
    remote._connected = true;
    final remotePeer = remote._knownPeers[remote.localEndpointId]!;
    remote._connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(
          id: remotePeer.id,
          name: remotePeer.name,
          connected: true,
        ),
        state: NearbyConnectionState.connected,
      ),
    );
  }

  @override
  Future<void> startAdvertising({
    required String displayName,
    String? identityFingerprint,
  }) async {
    if (isAdvertising) return;
    startAdvertisingCalls++;
    isAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    stopAdvertisingCalls++;
    isAdvertising = false;
  }

  @override
  Future<void> startDiscovery() async {
    if (isDiscovering) return;
    _discoveryEpoch++;
    startDiscoveryCalls++;
    isDiscovering = true;
  }

  @override
  Future<void> stopDiscovery() async {
    stopDiscoveryCalls++;
    _discoveryEpoch++;
    isDiscovering = false;
  }

  @override
  Future<void> resetSessionOperations() async {
    _discoveryEpoch++;
    isDiscovering = false;
    isAdvertising = false;
  }

  @override
  Future<void> clearIdleEndpoints() async {
    if (isAdvertising || isDiscovering || _connected) {
      throw StateError('Cannot clear an active loopback transport.');
    }
    idleEndpointClearCalls++;
  }

  @override
  Future<void> requestConnection(
    String peerId, {
    String? identityFingerprint,
    String? connectionTraceId,
  }) async {
    requestCalls++;
    if (failNextRequest) {
      failNextRequest = false;
      throw const NearbyTransportException('Simulated native request failure.');
    }
    acceptedConnections.clear();
    other!.acceptedConnections.clear();
    _connections.add(
      NearbyConnectionEvent(
        peer: _knownPeers[peerId]!,
        state: NearbyConnectionState.connecting,
      ),
    );
    if (requireBothNativeAccepts) {
      _connections.add(
        NearbyConnectionEvent(
          peer: _knownPeers[peerId]!,
          state: NearbyConnectionState.incomingRequest,
          isIncomingRequest: false,
        ),
      );
    }
    final remote = other!;
    remote._connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(
          id: remote.localEndpointId,
          name: displayName,
          identityFingerprintHint: remote.omitIncomingFingerprintHint
              ? null
              : (identityFingerprint ?? localFingerprint),
        ),
        state: NearbyConnectionState.incomingRequest,
        isIncomingRequest: true,
      ),
    );
    await requestGate?.future;
  }

  @override
  Future<void> acceptConnection(
    String peerId, {
    String? connectionTraceId,
  }) async {
    acceptCalls.add(peerId);
    await acceptGate?.future;
    acceptedConnections.add(peerId);
    if (requireBothNativeAccepts &&
        !other!.acceptedConnections.contains(other!.localEndpointId)) {
      return;
    }
    if (!holdConnectionResult) _connectedBoth();
  }

  @override
  Future<void> rejectConnection(
    String peerId, {
    String? connectionTraceId,
  }) async {}

  @override
  Future<void> disconnect(String peerId) async {
    if (disconnectGate != null) await disconnectGate!.future;
    disconnectCalls.add(peerId);
    acceptedConnections.clear();
    other!.acceptedConnections.clear();
    _connected = false;
    final peer =
        _knownPeers[peerId] ?? NearbyPeer(id: peerId, name: displayName);
    if (!omitLocalDisconnectCallback) {
      _connections.add(
        NearbyConnectionEvent(
          peer: peer,
          state: NearbyConnectionState.disconnected,
        ),
      );
    }
    final remote = other!;
    remote._connected = false;
    final remotePeer = remote._knownPeers[remote.localEndpointId]!;
    remote._connections.add(
      NearbyConnectionEvent(
        peer: remotePeer,
        state: NearbyConnectionState.disconnected,
      ),
    );
  }

  @override
  Future<void> sendBytes(Uint8List bytes, {String? peerId}) async {
    if (!_connected) throw StateError('Loopback endpoint is not connected.');
    final packet = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    sentPackets.add(packet['type'] as String);
    packets.add(RelioPacket.fromBytes(bytes));
    if (!dropPayloads) {
      other!._payloads.add(
        NearbyPayloadEvent(peerId: other!.localEndpointId, bytes: bytes),
      );
    }
    if (packet['type'] == 'mediaMetadata' &&
        !holdFiles &&
        !fileBeforeMetadata) {
      await deliverFiles();
    }
  }

  @override
  Future<String> sendFile(String filePath, {String? peerId}) async {
    if (!_connected) throw StateError('File endpoint is not connected');
    final id = '$remoteEndpointId-${++fileSequence}';
    pendingFiles[id] = await File(filePath).readAsBytes();
    if (!holdFiles && fileBeforeMetadata) await deliverFiles();
    return id;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait([
      _peers.close(),
      _payloads.close(),
      _connections.close(),
      _nativeDiagnostics.close(),
      _files.close(),
      _transfers.close(),
    ]);
  }
}
