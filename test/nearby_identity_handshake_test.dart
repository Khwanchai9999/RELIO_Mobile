import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/diagnostics/diagnostics_log_service.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/peer_identity_crypto.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'first contact enrolls both identities after consent and survives',
    () async {
      final pair = await _HandshakePair.create();
      addTearDown(pair.close);

      await pair.serviceA.connect('endpoint-b');
      await _waitFor(
        () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
      );
      await pair.serviceB.acceptConnectionRequest('endpoint-a');
      await _waitFor(
        () =>
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
            pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
      );

      expect(
        pair.serviceA.peerStates['endpoint-b'],
        NearbyConnectionState.connected,
      );
      expect(
        pair.serviceB.peerStates['endpoint-a'],
        NearbyConnectionState.connected,
      );
      expect(
        (await pair.repositoriesA.nearbyDevices.getDevice(
          'device-b',
        ))?.isTrusted,
        isTrue,
      );
      expect(
        (await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        ))?.isTrusted,
        isTrue,
      );
      expect(
        pair.transportA.sentPackets.where(
          (packet) => packet == 'identityChallenge',
        ),
        hasLength(1),
      );
      expect(
        pair.transportB.sentPackets.where(
          (packet) => packet == 'identityChallenge',
        ),
        hasLength(1),
      );
      final eventsA = await _readEvents(pair.logsA);
      final eventsB = await _readEvents(pair.logsB);
      for (final event in [
        'identity_handshake_started',
        'identity_challenge_created',
        'identity_challenge_sent',
        'identity_response_received',
        'identity_public_key_received',
        'identity_signature_verify_started',
        'identity_signature_verify_success',
        'identity_enrollment_started',
        'identity_fingerprint_pinned',
        'identity_enrollment_completed',
        'identity_handshake_completed',
        'identity_hello_sent',
        'identity_hello_received',
      ]) {
        expect(eventsA.map((entry) => entry['event']), contains(event));
        expect(eventsB.map((entry) => entry['event']), contains(event));
      }
      final stage = eventsA.firstWhere(
        (entry) => entry['event'] == 'identity_handshake_started',
      );
      expect(stage['protocolVersion'], 2);
      expect(stage['handshakeState'], 'identity_handshake_started');
      expect(stage['elapsedMs'], isA<int>());
      expect(stage['connectionTraceId'], isNotEmpty);
      expect(stage['peerAlias'], DiagnosticsLogService.peerAlias('endpoint-b'));
    },
  );

  test('wrong identity signature fails closed and is attributed', () async {
    final pair = await _HandshakePair.create(corruptSignatureB: true);
    addTearDown(pair.close);

    await pair.serviceA.connect('endpoint-b');
    await _waitFor(
      () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
    );
    await pair.serviceB.acceptConnectionRequest('endpoint-a');
    await _waitFor(
      () => pair.serviceA.peerErrors['endpoint-b'] == 'identity_proof_invalid',
    );
    await pair.logsA.flush();
    final events = await _readEvents(pair.logsA);
    expect(
      events.map((entry) => entry['event']),
      contains('identity_signature_verify_failed'),
    );
    expect(
      events.map((entry) => entry['event']),
      contains('identity_handshake_failed'),
    );
    expect(
      events.map((entry) => entry['event']),
      contains('disconnect_requested_by_app'),
    );
    expect(
      events.map((entry) => entry['event']),
      contains('disconnect_requested_reason'),
    );
    expect(pair.serviceA.deviceIdForEndpoint('endpoint-b'), isNull);
    expect(
      await pair.repositoriesA.nearbyDevices.getDevice('device-b'),
      isNull,
    );
  });

  test('trusted reconnect auto-accepts only a uniquely pinned key', () async {
    final pair = await _HandshakePair.create();
    addTearDown(pair.close);

    await pair.serviceA.connect('endpoint-b');
    await _waitFor(
      () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
    );
    await pair.serviceB.acceptConnectionRequest('endpoint-a');
    await _waitFor(
      () =>
          pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
          pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
    );

    await pair.serviceA.disconnect('endpoint-b', reason: 'test_reconnect');
    await _waitFor(
      () =>
          pair.serviceA.peerStates['endpoint-b'] ==
          NearbyConnectionState.disconnected,
    );

    pair.transportA.discoverPeer();
    pair.transportB.discoverPeer();
    await _waitFor(
      () =>
          pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
          pair.serviceA.peerStates['endpoint-b'] ==
              NearbyConnectionState.connected,
    );

    expect(pair.transportA.acceptedConnections, contains('endpoint-b'));
    expect(pair.serviceA.pendingConnectionRequests, isEmpty);
  });

  test(
    'simultaneous challenges do not overwrite either pending nonce',
    () async {
      final pair = await _HandshakePair.create();
      addTearDown(pair.close);

      await pair.serviceA.connect('endpoint-b');
      await _waitFor(
        () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
      );
      await pair.serviceB.acceptConnectionRequest('endpoint-a');
      await _waitFor(
        () =>
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
            pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
      );

      expect(pair.transportA.sentPackets, contains('identityProof'));
      expect(pair.transportB.sentPackets, contains('identityProof'));
      expect(
        pair.serviceA.peerStates['endpoint-b'],
        NearbyConnectionState.connected,
      );
      expect(
        pair.serviceB.peerStates['endpoint-a'],
        NearbyConnectionState.connected,
      );
    },
  );

  test(
    'identity timeout race is logged and attributes both disconnect sides',
    () async {
      final pair = await _HandshakePair.create(
        handshakeTimeout: const Duration(milliseconds: 500),
        dropPayloads: true,
      );
      addTearDown(pair.close);

      await pair.serviceA.connect('endpoint-b');
      await _waitFor(
        () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
      );
      await pair.serviceB.acceptConnectionRequest('endpoint-a');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        pair.serviceA.peerStates['endpoint-b'],
        isNot(NearbyConnectionState.connecting),
      );
      expect(
        pair.serviceB.peerStates['endpoint-a'],
        isNot(NearbyConnectionState.connecting),
      );

      final eventsA = await _readEvents(pair.logsA);
      final eventsB = await _readEvents(pair.logsB);
      final allEvents = [...eventsA, ...eventsB];
      expect(
        allEvents.map((event) => event['event']),
        contains('identity_handshake_timeout'),
      );
      expect(
        allEvents.map((event) => event['event']),
        contains('disconnect_requested_by_app'),
      );
      expect(
        allEvents.map((event) => event['event']),
        contains('disconnect_requested_reason'),
      );
      final nativeDisconnects = allEvents.where(
        (event) => event['event'] == 'native_endpoint_disconnected',
      );
      expect(nativeDisconnects.length, greaterThanOrEqualTo(2));
      expect(
        nativeDisconnects.map((event) => event['disconnectRequester']),
        containsAll(['app', 'nearby_or_remote']),
      );
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for identity handshake state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<List<Map<String, dynamic>>> _readEvents(
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

class _HandshakePair {
  _HandshakePair._({
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
  final _LoopbackTransport transportA;
  final _LoopbackTransport transportB;
  final _TestIdentityCrypto cryptoA;
  final _TestIdentityCrypto cryptoB;
  final NearbyService serviceA;
  final NearbyService serviceB;
  final DiagnosticsLogService logsA;
  final DiagnosticsLogService logsB;

  static Future<_HandshakePair> create({
    Duration handshakeTimeout = const Duration(seconds: 30),
    bool dropPayloads = false,
    bool corruptSignatureB = false,
  }) async {
    final databaseA = AppDatabase.memory();
    final databaseB = AppDatabase.memory();
    await _setDeviceId(databaseA, 'device-a');
    await _setDeviceId(databaseB, 'device-b');
    final repositoriesA = RelioRepositories(databaseA);
    final repositoriesB = RelioRepositories(databaseB);
    final cryptoA = _TestIdentityCrypto('device-a');
    final cryptoB = _TestIdentityCrypto(
      'device-b',
      corruptSignatures: corruptSignatureB,
    );
    final transportA = _LoopbackTransport(
      localEndpointId: 'endpoint-b',
      remoteEndpointId: 'endpoint-a',
      displayName: 'Phone A',
      localFingerprint: (await cryptoA.getPublicIdentity()).fingerprint,
      remoteFingerprint: (await cryptoB.getPublicIdentity()).fingerprint,
      dropPayloads: dropPayloads,
    );
    final transportB = _LoopbackTransport(
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
    );
    await serviceA.initialize();
    await serviceB.initialize();
    transportA.discoverPeer();
    transportB.discoverPeer();
    return _HandshakePair._(
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

class _TestIdentityCrypto implements PeerIdentityCrypto {
  _TestIdentityCrypto(this.deviceId, {this.corruptSignatures = false})
    : _publicKey = 'test-public-key:$deviceId';

  final String deviceId;
  final bool corruptSignatures;
  final String _publicKey;
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

class _LoopbackTransport implements NearbyTransport {
  _LoopbackTransport({
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
  final _files = StreamController<NearbyFilePayloadEvent>.broadcast();
  final _transfers = StreamController<NearbyTransferEvent>.broadcast();
  final List<String> sentPackets = [];
  final Set<String> acceptedConnections = {};
  late final Map<String, NearbyPeer> _knownPeers = {
    localEndpointId: NearbyPeer(
      id: localEndpointId,
      name: displayName,
      identityFingerprintHint: remoteFingerprint,
    ),
  };
  _LoopbackTransport? other;
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

  void discoverPeer() => _peers.add(_knownPeers[localEndpointId]!);

  void simulateIncomingRequest({
    required String name,
    required String fingerprint,
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
  Future<void> stopAdvertising() async {}
  @override
  Future<void> startDiscovery() async {}
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> resetSessionOperations() async {}

  @override
  Future<void> requestConnection(String peerId) async {
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
          identityFingerprintHint: localFingerprint,
        ),
        state: NearbyConnectionState.incomingRequest,
        isIncomingRequest: true,
      ),
    );
  }

  @override
  Future<void> acceptConnection(String peerId) async {
    acceptedConnections.add(peerId);
    _connectedBoth();
  }

  @override
  Future<void> rejectConnection(String peerId) async {}

  @override
  Future<void> disconnect(String peerId) async {
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
    if (!dropPayloads) {
      other!._payloads.add(
        NearbyPayloadEvent(peerId: other!.localEndpointId, bytes: bytes),
      );
    }
  }

  @override
  Future<String> sendFile(String filePath, {String? peerId}) async => 'unused';
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait([
      _peers.close(),
      _payloads.close(),
      _connections.close(),
      _files.close(),
      _transfers.close(),
    ]);
  }
}
