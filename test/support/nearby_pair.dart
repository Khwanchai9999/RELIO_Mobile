import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:relio_mobile/core/media/media_storage_service.dart';
import 'package:relio_mobile/core/notifications/local_notification_service.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';

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
  final LoopbackTransport transportA;
  final LoopbackTransport transportB;
  final TestIdentityCrypto cryptoA;
  final TestIdentityCrypto cryptoB;
  final NearbyService serviceA;
  final NearbyService serviceB;
  final DiagnosticsLogService logsA;
  final DiagnosticsLogService logsB;

  static Future<HandshakePair> create({
    LocalNotificationSink? notificationsA,
    LocalNotificationSink? notificationsB,
    Duration handshakeTimeout = const Duration(seconds: 30),
    bool dropPayloads = false,
    bool corruptSignatureB = false,
  }) async {
    final databaseA = AppDatabase.memory();
    final databaseB = AppDatabase.memory();
    await _setDeviceId(databaseA, 'device-a');
    await _setDeviceId(databaseB, 'device-b');
    await RelioDeviceIdentityRepository(databaseA).setDisplayName('สมชาย');
    final repositoriesA = RelioRepositories(databaseA);
    final repositoriesB = RelioRepositories(databaseB);
    final cryptoA = TestIdentityCrypto('device-a');
    final cryptoB = TestIdentityCrypto(
      'device-b',
      corruptSignatures: corruptSignatureB,
    );
    final transportA = LoopbackTransport(
      localEndpointId: 'endpoint-b',
      remoteEndpointId: 'endpoint-a',
      displayName: 'สมชาย',
      localFingerprint: (await cryptoA.getPublicIdentity()).fingerprint,
      remoteFingerprint: (await cryptoB.getPublicIdentity()).fingerprint,
      dropPayloads: dropPayloads,
    );
    final transportB = LoopbackTransport(
      localEndpointId: 'endpoint-a',
      remoteEndpointId: 'endpoint-b',
      displayName: 'Phone B',
      localFingerprint: (await cryptoB.getPublicIdentity()).fingerprint,
      remoteFingerprint: (await cryptoA.getPublicIdentity()).fingerprint,
      dropPayloads: dropPayloads,
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
      identity: RelioDeviceIdentityRepository(databaseA),
      nearbyDevices: repositoriesA.nearbyDevices,
      identityCrypto: cryptoA,
      diagnostics: logsA,
      handshakeTimeout: handshakeTimeout,
      attachments: repositoriesA.attachments,
      mediaStorage: MediaStorageService(
        rootDirectory: Directory('${logsA.directory!.path}/media'),
      ),
      settings: repositoriesA.settings,
      localNotifications: notificationsA,
    );
    final serviceB = NearbyService(
      transport: transportB,
      messages: repositoriesB.messages,
      conversations: repositoriesB.conversations,
      identity: RelioDeviceIdentityRepository(databaseB),
      nearbyDevices: repositoriesB.nearbyDevices,
      identityCrypto: cryptoB,
      diagnostics: logsB,
      handshakeTimeout: handshakeTimeout,
      attachments: repositoriesB.attachments,
      mediaStorage: MediaStorageService(
        rootDirectory: Directory('${logsB.directory!.path}/media'),
      ),
      settings: repositoriesB.settings,
      localNotifications: notificationsB,
    );
    transportA.incomingDirectory = logsA.directory!;
    transportB.incomingDirectory = logsB.directory!;
    await serviceA.initialize();
    await serviceB.initialize();
    transportA.discoverPeer();
    transportB.discoverPeer();
    return HandshakePair._(
      databaseA: databaseA,
      databaseB: databaseB,
      repositoriesA: repositoriesA,
      repositoriesB: repositoriesB,
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

  @override
  Future<bool> verify({
    required String publicKey,
    required Uint8List message,
    required String signature,
  }) async => signature == _signature(message, publicKey);
}

class LoopbackTransport implements NearbyTransport {
  LoopbackTransport({
    required this.localEndpointId,
    required this.remoteEndpointId,
    required this.displayName,
    required this.localFingerprint,
    required this.remoteFingerprint,
    this.dropPayloads = false,
  });

  final String localEndpointId;
  final String remoteEndpointId;
  final String displayName;
  final String localFingerprint;
  final String remoteFingerprint;
  final bool dropPayloads;
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
  int stopDiscoveryCalls = 0;
  int stopAdvertisingCalls = 0;
  bool omitIncomingFingerprintHint = false;
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

  @override
  String get implementationName => 'IdentityHandshakeLoopback';
  @override
  String get serviceId => relioNearbyServiceId;
  @override
  String get strategyName => relioNearbyStrategyName;
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

  void discoverPeer() => _peers.add(_knownPeers[localEndpointId]!);

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

  void _connectedBoth() {
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
  }) async {}
  @override
  Future<void> stopAdvertising() async => stopAdvertisingCalls++;
  @override
  Future<void> startDiscovery() async {}
  @override
  Future<void> stopDiscovery() async => stopDiscoveryCalls++;
  @override
  Future<void> resetSessionOperations() async {}

  @override
  Future<void> requestConnection(
    String peerId, {
    String? identityFingerprint,
    String? connectionTraceId,
  }) async {
    _connections.add(
      NearbyConnectionEvent(
        peer: _knownPeers[peerId]!,
        state: NearbyConnectionState.connecting,
      ),
    );
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
  }

  @override
  Future<void> acceptConnection(
    String peerId, {
    String? connectionTraceId,
  }) async {
    acceptCalls.add(peerId);
    acceptedConnections.add(peerId);
    _connectedBoth();
  }

  @override
  Future<void> rejectConnection(
    String peerId, {
    String? connectionTraceId,
  }) async {}

  @override
  Future<void> disconnect(String peerId) async {
    disconnectCalls.add(peerId);
    _connected = false;
    final peer =
        _knownPeers[peerId] ?? NearbyPeer(id: peerId, name: displayName);
    _connections.add(
      NearbyConnectionEvent(
        peer: peer,
        state: NearbyConnectionState.disconnected,
      ),
    );
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
