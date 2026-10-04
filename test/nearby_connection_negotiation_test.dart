import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/diagnostics/diagnostics_log_service.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/peer_identity_crypto.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  late _Rig rig;

  setUp(() async {
    rig = await _Rig.create(
      softTimeout: const Duration(milliseconds: 20),
      hardTimeout: const Duration(milliseconds: 220),
    );
  });

  tearDown(() => rig.close());

  test('soft timeout does not disconnect a later native success', () async {
    rig.transport.holdConnectionRequests = true;
    rig.transport.simulatePeer(id: 'peer-b', name: 'Peer B');
    await Future<void>.delayed(Duration.zero);

    await rig.service.connect('peer-b');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(rig.service.peerErrors['peer-b'], 'connection_slow');
    expect(rig.service.peerStates['peer-b'], NearbyConnectionState.connecting);
    expect(rig.transport.disconnectCount, 0);

    rig.transport.resolveConnectionRequest('peer-b', connected: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(rig.service.peerStates['peer-b'], NearbyConnectionState.connected);
    expect(rig.transport.disconnectCount, 0);
    expect(await rig.logText(), contains('connection_soft_timeout'));
  });

  test('native failure wins over a pending application timeout', () async {
    rig.transport.holdConnectionRequests = true;
    rig.transport.simulatePeer(id: 'peer-failure', name: 'Peer');
    await Future<void>.delayed(Duration.zero);

    await rig.service.connect('peer-failure');
    rig.transport.resolveConnectionRequest(
      'peer-failure',
      connected: false,
      rawStatusCode: 13,
      rawStatusName: 'ERROR',
      rawStatusMessage: 'native failure',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      rig.service.peerStates['peer-failure'],
      NearbyConnectionState.failed,
    );
    expect(rig.service.lastNativeConnectionFailure?.rawStatusCode, 13);
    final log = await rig.logText();
    expect(log, contains('GOOGLE_NEARBY_NATIVE_FAILURE'));
    expect(log, isNot(contains('RELIO_HARD_NEGOTIATION_TIMEOUT')));
  });

  test('hard watchdog cleans up a missing native callback', () async {
    await rig.service.close();
    await rig.database.close();
    rig = await _Rig.create(
      softTimeout: const Duration(milliseconds: 15),
      hardTimeout: const Duration(milliseconds: 100),
    );
    rig.transport.holdConnectionRequests = true;
    rig.transport.simulatePeer(id: 'stale-peer', name: 'Peer');
    await Future<void>.delayed(Duration.zero);

    await rig.service.connect('stale-peer');
    await Future<void>.delayed(const Duration(milliseconds: 260));

    expect(rig.service.peerStates['stale-peer'], NearbyConnectionState.failed);
    expect(rig.transport.disconnectCount, 1);
    expect(await rig.logText(), contains('RELIO_HARD_NEGOTIATION_TIMEOUT'));
  });

  test(
    'request and accept Task success do not mean transport connected',
    () async {
      rig.transport.holdConnectionRequests = true;
      rig.transport.simulatePeer(id: 'request-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      await rig.service.connect('request-peer');
      expect(
        rig.service.peerStates['request-peer'],
        NearbyConnectionState.connecting,
      );

      rig.transport.simulateIncomingConnection(id: 'accept-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      await rig.service.acceptConnectionRequest('accept-peer');
      expect(rig.transport.acceptConnectionCount, 1);
      expect(
        rig.service.peerStates['accept-peer'],
        NearbyConnectionState.connecting,
      );
    },
  );

  test(
    'user cancel and endpoint loss have distinct cleanup attribution',
    () async {
      rig.transport.holdConnectionRequests = true;
      rig.transport.simulatePeer(id: 'cancel-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      await rig.service.connect('cancel-peer');
      await rig.service.cancelConnection('cancel-peer');
      expect(rig.transport.disconnectCount, 1);
      expect(await rig.logText(), contains('USER_CANCELLED_CONNECTION'));

      rig.transport.simulatePeer(id: 'lost-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      await rig.service.connect('lost-peer');
      rig.transport.simulateEndpointLoss('lost-peer');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(rig.service.peerStates['lost-peer'], NearbyConnectionState.failed);
      expect(await rig.logText(), contains('ENDPOINT_LOST_DURING_NEGOTIATION'));
    },
  );

  test(
    'two peers survive delayed resolution, exchange text, ACK, and reconnect',
    () async {
      final pair = await _TwoPeerPair.create(
        resultDelay: const Duration(milliseconds: 80),
        softTimeout: const Duration(milliseconds: 25),
        hardTimeout: const Duration(milliseconds: 300),
      );
      addTearDown(pair.close);

      pair.transportA.discoverPeer();
      pair.transportB.discoverPeer();
      await Future<void>.delayed(Duration.zero);
      await pair.serviceA.connect('endpoint-b');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await pair.serviceB.acceptConnectionRequest('endpoint-a');
      await Future<void>.delayed(const Duration(milliseconds: 140));

      expect(
        pair.serviceA.peerStates['endpoint-b'],
        NearbyConnectionState.connected,
      );
      expect(
        pair.serviceB.peerStates['endpoint-a'],
        NearbyConnectionState.connected,
      );
      expect(pair.serviceA.peerErrors['endpoint-b'], isNull);

      final deviceA = await pair.identityA.getDeviceId();
      final deviceB = await pair.identityB.getDeviceId();
      final message = await pair.repositoriesA.messages.createOutgoingText(
        conversationId: deviceB,
        senderId: deviceA,
        senderDeviceId: deviceA,
        text: 'delayed nearby text',
      );
      await pair.serviceA.sendMessage(message);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final received = await pair.repositoriesB.messages.listMessages(deviceA);
      expect(received.single.text, 'delayed nearby text');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        (await pair.repositoriesA.messages.getMessage(message.id))?.status,
        DeliveryStatus.delivered,
      );

      await pair.serviceA.disconnect('endpoint-b');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      pair.transportA.resultDelay = Duration.zero;
      pair.transportB.resultDelay = Duration.zero;
      await pair.serviceA.connect('endpoint-b');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pair.serviceB.acceptConnectionRequest('endpoint-a');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        pair.serviceA.peerStates['endpoint-b'],
        NearbyConnectionState.connected,
      );
    },
  );
}

class _Rig {
  _Rig._(
    this.database,
    this.repositories,
    this.transport,
    this.service,
    this.logs,
  );

  final AppDatabase database;
  final RelioRepositories repositories;
  final MockNearbyTransport transport;
  final NearbyService service;
  final DiagnosticsLogService logs;

  static Future<_Rig> create({
    required Duration softTimeout,
    required Duration hardTimeout,
  }) async {
    final database = AppDatabase.memory();
    final repositories = RelioRepositories(database);
    final transport = MockNearbyTransport();
    final logs = DiagnosticsLogService(
      directory: await Directory.systemTemp.createTemp('relio-negotiation-'),
    );
    await logs.initialize();
    final service = NearbyService(
      transport: transport,
      messages: repositories.messages,
      conversations: repositories.conversations,
      identity: RelioDeviceIdentityRepository(database),
      nearbyDevices: repositories.nearbyDevices,
      diagnostics: logs,
      identityCrypto: MockPeerIdentityCrypto('test-device'),
      connectionAttemptTimeout: softTimeout,
      hardNegotiationTimeout: hardTimeout,
    );
    await service.initialize();
    return _Rig._(database, repositories, transport, service, logs);
  }

  Future<String> logText() async {
    await logs.flush();
    final root = logs.directory!;
    final files = await root
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.jsonl'))
        .toList();
    return files.map((entry) => File(entry.path).readAsStringSync()).join();
  }

  Future<void> close() async {
    await service.close();
    await database.close();
    await logs.flush();
    if (await logs.directory!.exists()) {
      await logs.directory!.delete(recursive: true);
    }
  }
}

class _TwoPeerPair {
  _TwoPeerPair._(
    this.databaseA,
    this.databaseB,
    this.repositoriesA,
    this.repositoriesB,
    this.identityA,
    this.identityB,
    this.transportA,
    this.transportB,
    this.serviceA,
    this.serviceB,
  );

  final AppDatabase databaseA;
  final AppDatabase databaseB;
  final RelioRepositories repositoriesA;
  final RelioRepositories repositoriesB;
  final RelioDeviceIdentityRepository identityA;
  final RelioDeviceIdentityRepository identityB;
  final _TwoPeerTransport transportA;
  final _TwoPeerTransport transportB;
  final NearbyService serviceA;
  final NearbyService serviceB;

  static Future<_TwoPeerPair> create({
    required Duration resultDelay,
    required Duration softTimeout,
    required Duration hardTimeout,
  }) async {
    final databaseA = AppDatabase.memory();
    final databaseB = AppDatabase.memory();
    final repositoriesA = RelioRepositories(databaseA);
    final repositoriesB = RelioRepositories(databaseB);
    final identityA = RelioDeviceIdentityRepository(databaseA);
    final identityB = RelioDeviceIdentityRepository(databaseB);
    final cryptoA = MockPeerIdentityCrypto('device-a');
    final cryptoB = MockPeerIdentityCrypto('device-b');
    final fingerprintA = (await cryptoA.getPublicIdentity()).fingerprint;
    final fingerprintB = (await cryptoB.getPublicIdentity()).fingerprint;
    final transportA = _TwoPeerTransport(
      localEndpointId: 'endpoint-a',
      remoteEndpointId: 'endpoint-b',
      remoteName: 'Device B',
      remoteFingerprint: fingerprintB,
      resultDelay: resultDelay,
    );
    final transportB = _TwoPeerTransport(
      localEndpointId: 'endpoint-b',
      remoteEndpointId: 'endpoint-a',
      remoteName: 'Device A',
      remoteFingerprint: fingerprintA,
      resultDelay: resultDelay,
    );
    transportA.other = transportB;
    transportB.other = transportA;
    final serviceA = NearbyService(
      transport: transportA,
      messages: repositoriesA.messages,
      conversations: repositoriesA.conversations,
      identity: identityA,
      nearbyDevices: repositoriesA.nearbyDevices,
      identityCrypto: cryptoA,
      connectionAttemptTimeout: softTimeout,
      hardNegotiationTimeout: hardTimeout,
    );
    final serviceB = NearbyService(
      transport: transportB,
      messages: repositoriesB.messages,
      conversations: repositoriesB.conversations,
      identity: identityB,
      nearbyDevices: repositoriesB.nearbyDevices,
      identityCrypto: cryptoB,
      connectionAttemptTimeout: softTimeout,
      hardNegotiationTimeout: hardTimeout,
    );
    await serviceA.initialize();
    await serviceB.initialize();
    return _TwoPeerPair._(
      databaseA,
      databaseB,
      repositoriesA,
      repositoriesB,
      identityA,
      identityB,
      transportA,
      transportB,
      serviceA,
      serviceB,
    );
  }

  Future<void> close() async {
    await serviceA.close();
    await serviceB.close();
    await databaseA.close();
    await databaseB.close();
  }
}

class _TwoPeerTransport implements NearbyTransport {
  _TwoPeerTransport({
    required this.localEndpointId,
    required this.remoteEndpointId,
    required this.remoteName,
    required this.remoteFingerprint,
    required this.resultDelay,
  });

  final String localEndpointId;
  final String remoteEndpointId;
  final String remoteName;
  final String remoteFingerprint;
  late _TwoPeerTransport other;
  Duration resultDelay;
  final _peers = StreamController<NearbyPeer>.broadcast();
  final _payloads = StreamController<NearbyPayloadEvent>.broadcast();
  final _connections = StreamController<NearbyConnectionEvent>.broadcast();
  final _files = StreamController<NearbyFilePayloadEvent>.broadcast();
  final _transfers = StreamController<NearbyTransferEvent>.broadcast();
  final _nativeDiagnostics =
      StreamController<NearbyNativeDiagnostic>.broadcast();
  bool requested = false;
  bool accepted = false;
  bool connected = false;
  bool resultScheduled = false;
  int requestCount = 0;

  @override
  String get implementationName => 'TwoPeerNativeHarness';
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

  void discoverPeer() => _peers.add(
    NearbyPeer(
      id: remoteEndpointId,
      name: remoteName,
      identityFingerprintHint: remoteFingerprint,
    ),
  );

  void simulateIncomingConnection({required String id, required String name}) =>
      _connections.add(
        NearbyConnectionEvent(
          peer: NearbyPeer(id: id, name: name),
          state: NearbyConnectionState.incomingRequest,
          isIncomingRequest: true,
        ),
      );

  void _maybeResolve() {
    if (resultScheduled || !accepted || !other.requested) return;
    resultScheduled = true;
    Future<void>.delayed(resultDelay, () {
      connected = true;
      other.connected = true;
      _emitConnected();
      other._emitConnected();
    });
  }

  void _emitConnected() => _connections.add(
    NearbyConnectionEvent(
      peer: NearbyPeer(
        id: remoteEndpointId,
        name: remoteName,
        connected: true,
        identityFingerprintHint: remoteFingerprint,
      ),
      state: NearbyConnectionState.connected,
      rawStatusCode: 0,
      rawStatusName: 'SUCCESS',
      operation: 'onConnectionResult',
    ),
  );

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
  Future<void> requestConnection(
    String peerId, {
    String? identityFingerprint,
    String? connectionTraceId,
  }) async {
    requestCount++;
    requested = true;
    _connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(id: remoteEndpointId, name: remoteName),
        state: NearbyConnectionState.connecting,
      ),
    );
    other.simulateIncomingConnection(id: localEndpointId, name: 'Device A');
  }

  @override
  Future<void> acceptConnection(
    String peerId, {
    String? connectionTraceId,
  }) async {
    accepted = true;
    _maybeResolve();
  }

  @override
  Future<void> rejectConnection(
    String peerId, {
    String? connectionTraceId,
  }) async {}

  @override
  Future<void> disconnect(String peerId) async {
    connected = false;
    resultScheduled = false;
    requested = false;
    accepted = false;
    _connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(id: remoteEndpointId, name: remoteName),
        state: NearbyConnectionState.disconnected,
      ),
    );
    if (other.connected) {
      other.connected = false;
      other.resultScheduled = false;
      other.requested = false;
      other.accepted = false;
      other._connections.add(
        NearbyConnectionEvent(
          peer: NearbyPeer(id: localEndpointId, name: 'RELIO'),
          state: NearbyConnectionState.disconnected,
        ),
      );
    }
  }

  @override
  Future<void> sendBytes(Uint8List bytes, {String? peerId}) async {
    if (!connected) throw StateError('peer is not connected');
    other._payloads.add(
      NearbyPayloadEvent(peerId: localEndpointId, bytes: bytes),
    );
  }

  @override
  Future<String> sendFile(String filePath, {String? peerId}) async =>
      'two-peer-file';

  @override
  Future<void> dispose() async {
    await Future.wait([
      _peers.close(),
      _payloads.close(),
      _connections.close(),
      _files.close(),
      _transfers.close(),
      _nativeDiagnostics.close(),
    ]);
  }
}
