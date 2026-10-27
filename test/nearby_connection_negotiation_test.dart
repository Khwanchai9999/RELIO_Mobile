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

  test('repeated connect tap submits only one native request', () async {
    rig.transport.holdConnectionRequests = true;
    rig.transport.simulatePeer(id: 'paired-peer', name: 'Paired peer');
    await Future<void>.delayed(Duration.zero);

    await rig.service.connect('paired-peer');
    await rig.service.connect('paired-peer');

    expect(rig.transport.connectionRequestCount, 1);
    expect(
      rig.service.peerStates['paired-peer'],
      NearbyConnectionState.connecting,
    );
  });

  test(
    'already-connected native status resumes identity handshake instead of failing',
    () async {
      rig.transport.holdConnectionRequests = true;
      rig.transport.simulatePeer(id: 'already-connected-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);

      await rig.service.connect('already-connected-peer');
      rig.transport.resolveConnectionRequest(
        'already-connected-peer',
        connected: false,
        rawStatusCode: 8003,
        rawStatusName: 'STATUS_ALREADY_CONNECTED_TO_ENDPOINT',
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        rig.service.peerStates['already-connected-peer'],
        NearbyConnectionState.connected,
      );
      expect(
        rig.service.connectionPhaseForEndpoint('already-connected-peer'),
        NearbyConnectionPhase.identityHandshake,
      );
      expect(rig.transport.disconnectCount, 0);
      expect(
        await rig.logText(),
        contains('already_connected_status_reconciled'),
      );
    },
  );

  test(
    'already-connected task exception resumes identity handshake instead of failing',
    () async {
      rig.transport.requestConnectionFailure = const NearbyTransportException(
        'Endpoint is already connected.',
        apiStatusCode: 8003,
        apiStatusName: 'STATUS_ALREADY_CONNECTED_TO_ENDPOINT',
      );
      rig.transport.simulatePeer(
        id: 'already-connected-task-peer',
        name: 'Peer',
      );
      await Future<void>.delayed(Duration.zero);

      await rig.service.connect('already-connected-task-peer');
      await Future<void>.delayed(Duration.zero);

      expect(
        rig.service.peerStates['already-connected-task-peer'],
        NearbyConnectionState.connected,
      );
      expect(
        rig.service.connectionPhaseForEndpoint('already-connected-task-peer'),
        NearbyConnectionPhase.identityHandshake,
      );
      expect(rig.transport.disconnectCount, 0);
      expect(
        await rig.logText(),
        contains('already_connected_task_exception_reconciled'),
      );
    },
  );

  test(
    'initiator accepts transport without an auth-code approval prompt',
    () async {
      final fingerprint = List.filled(64, 'c').join();
      rig.transport.holdConnectionRequests = true;
      rig.transport.simulatePeer(
        id: 'initiated-peer',
        name: 'Peer',
        identityFingerprintHint: fingerprint,
      );
      await Future<void>.delayed(Duration.zero);

      await rig.service.connect('initiated-peer');
      rig.transport.simulateIncomingConnection(
        id: 'initiated-peer',
        name: 'Peer',
        identityFingerprintHint: fingerprint,
        authenticationToken: '543210',
        isIncomingRequest: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      rig.transport.simulateIncomingConnection(
        id: 'initiated-peer',
        name: 'Peer',
        identityFingerprintHint: fingerprint,
        authenticationToken: '543210',
        isIncomingRequest: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(rig.transport.connectionRequestCount, 1);
      expect(rig.transport.acceptConnectionCount, 1);
      expect(
        rig.service.pendingConnectionRequests,
        isNot(contains('initiated-peer')),
      );
      final logs = await rig.logText();
      expect(logs, isNot(contains('initiator_verification_prompt_queued')));
    },
  );

  test(
    'QA Nearby roles start only their selected Google Nearby side',
    () async {
      await rig.service.startSession();

      await rig.service.configureDiagnosticRole(
        NearbyDiagnosticRole.advertiserOnly,
      );
      expect(rig.transport.isAdvertising, isTrue);
      expect(rig.transport.isDiscovering, isFalse);
      await rig.service.stopSession(reason: 'test_lifecycle_restart');
      await rig.service.startSession();
      expect(rig.transport.isAdvertising, isTrue);
      expect(rig.transport.isDiscovering, isFalse);

      await rig.service.configureDiagnosticRole(
        NearbyDiagnosticRole.discovererOnly,
      );
      expect(rig.transport.isAdvertising, isFalse);
      expect(rig.transport.isDiscovering, isTrue);
      await rig.service.stopSession(reason: 'test_lifecycle_restart');
      await rig.service.startSession();
      expect(rig.transport.isAdvertising, isFalse);
      expect(rig.transport.isDiscovering, isTrue);

      await rig.service.configureDiagnosticRole(NearbyDiagnosticRole.stopped);
      expect(rig.transport.isAdvertising, isFalse);
      expect(rig.transport.isDiscovering, isFalse);
      await rig.service.startSession();
      expect(rig.transport.isAdvertising, isFalse);
      expect(rig.transport.isDiscovering, isFalse);

      await rig.service.configureDiagnosticRole(NearbyDiagnosticRole.auto);
      expect(rig.transport.isAdvertising, isTrue);
      expect(rig.transport.isDiscovering, isTrue);
    },
  );

  test('old discovery epoch is rejected before native request', () async {
    await rig.service.startDiscovery();
    final oldEpoch = rig.transport.discoveryEpoch;
    rig.transport.simulatePeer(
      id: 'old-endpoint',
      name: 'Peer',
      epoch: oldEpoch,
    );
    await Future<void>.delayed(Duration.zero);
    await rig.service.stopDiscovery();
    await rig.service.startDiscovery();

    await rig.service.connect('old-endpoint');

    expect(rig.transport.connectionRequestCount, 0);
    expect(
      rig.service.peerErrors['old-endpoint'],
      'waiting_for_fresh_endpoint',
    );
  });

  test('lost endpoint cannot be reused from the old visible row', () async {
    rig.transport.simulatePeer(id: 'lost-before-tap', name: 'Peer');
    await Future<void>.delayed(Duration.zero);
    rig.transport.simulateEndpointLoss('lost-before-tap');
    await Future<void>.delayed(Duration.zero);

    await rig.service.connect('lost-before-tap');

    expect(rig.transport.connectionRequestCount, 0);
    expect(rig.service.isEndpointCurrent('lost-before-tap'), isFalse);
  });

  test(
    'discovery loss during native negotiation does not own the attempt',
    () async {
      rig.transport.holdConnectionRequests = true;
      rig.transport.simulatePeer(id: 'negotiating-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);

      await rig.service.connect('negotiating-peer');
      expect(
        rig.service.connectionPhaseForEndpoint('negotiating-peer'),
        NearbyConnectionPhase.nativeNegotiating,
      );

      rig.transport.simulateEndpointLoss('negotiating-peer');
      await Future<void>.delayed(Duration.zero);

      expect(
        rig.service.peerStates['negotiating-peer'],
        NearbyConnectionState.connecting,
      );
      expect(
        rig.service.connectionPhaseForEndpoint('negotiating-peer'),
        NearbyConnectionPhase.nativeNegotiating,
      );
      expect(rig.transport.disconnectCount, 0);
      expect(rig.service.transportAttemptResults, isEmpty);

      rig.transport.simulatePeer(id: 'negotiating-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);
      expect(rig.transport.connectionRequestCount, 1);
      expect(
        rig.service.peerStates['negotiating-peer'],
        NearbyConnectionState.connecting,
      );

      rig.transport.resolveConnectionRequest(
        'negotiating-peer',
        connected: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        rig.service.peerStates['negotiating-peer'],
        NearbyConnectionState.connected,
      );
      final log = await rig.logText();
      expect(log, contains('endpoint_visibility_lost'));
      expect(log, contains('endpoint_loss_ignored_for_active_negotiation'));
      expect(log, isNot(contains('ENDPOINT_LOST_DURING_NEGOTIATION')));
    },
  );

  test('native failure owns an endpoint loss during negotiation', () async {
    rig.transport.holdConnectionRequests = true;
    rig.transport.simulatePeer(id: 'native-failure-peer', name: 'Peer');
    await Future<void>.delayed(Duration.zero);

    await rig.service.connect('native-failure-peer');
    rig.transport.simulateEndpointLoss('native-failure-peer');
    await Future<void>.delayed(Duration.zero);
    expect(
      rig.service.peerStates['native-failure-peer'],
      NearbyConnectionState.connecting,
    );

    rig.transport.resolveConnectionRequest(
      'native-failure-peer',
      connected: false,
      rawStatusCode: 13,
      rawStatusName: 'ERROR',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      rig.service.peerStates['native-failure-peer'],
      NearbyConnectionState.failed,
    );
    final log = await rig.logText();
    expect(log, contains('GOOGLE_NEARBY_NATIVE_FAILURE'));
    expect(log, contains('connection_resolution_applied'));
    expect(log, isNot(contains('ENDPOINT_LOST_DURING_NEGOTIATION')));
  });

  test(
    'hard watchdog still owns a lost endpoint with no native result',
    () async {
      rig.transport.holdConnectionRequests = true;
      rig.transport.simulatePeer(id: 'watchdog-lost-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);

      await rig.service.connect('watchdog-lost-peer');
      rig.transport.simulateEndpointLoss('watchdog-lost-peer');
      await Future<void>.delayed(const Duration(milliseconds: 260));

      expect(
        rig.service.peerStates['watchdog-lost-peer'],
        NearbyConnectionState.failed,
      );
      expect(rig.transport.disconnectCount, 1);
      final log = await rig.logText();
      expect(log, contains('RELIO_HARD_NEGOTIATION_TIMEOUT'));
      expect(log, isNot(contains('ENDPOINT_LOST_DURING_NEGOTIATION')));
    },
  );

  test(
    'Nearby event log exposes endpoint aliases rather than raw ids',
    () async {
      const endpointId = 'private-endpoint-identifier';
      rig.transport.simulatePeer(id: endpointId, name: 'Peer');
      await Future<void>.delayed(Duration.zero);

      final events = rig.service.eventLog.join('\n');
      expect(events, isNot(contains(endpointId)));
      expect(events, contains(DiagnosticsLogService.peerAlias(endpointId)));
    },
  );

  test('duplicate endpoint aliases share one stable-peer flight', () async {
    rig.transport.holdConnectionRequests = true;
    final fingerprint = List.filled(64, 'b').join();
    rig.transport.simulatePeer(
      id: 'alias-x',
      name: 'Peer',
      identityFingerprintHint: fingerprint,
    );
    rig.transport.simulatePeer(
      id: 'alias-y',
      name: 'Peer',
      identityFingerprintHint: fingerprint,
    );
    await Future<void>.delayed(Duration.zero);

    await rig.service.connect('alias-x');
    await rig.service.connect('alias-y');

    expect(rig.transport.connectionRequestCount, 1);
    expect(rig.service.peerStates['alias-x'], NearbyConnectionState.connecting);
    expect(
      rig.service.peerStates['alias-y'],
      isNot(NearbyConnectionState.connecting),
    );
  });

  test('8011 waits for one fresh endpoint and never retries old id', () async {
    rig.transport.holdConnectionRequests = true;
    final fingerprint = List.filled(64, 'a').join();
    rig.transport.simulatePeer(
      id: 'endpoint-x',
      name: 'Peer',
      identityFingerprintHint: fingerprint,
    );
    await Future<void>.delayed(Duration.zero);

    await rig.service.connect('endpoint-x');
    rig.transport.resolveConnectionRequest(
      'endpoint-x',
      connected: false,
      rawStatusCode: 8011,
      rawStatusName: 'STATUS_ENDPOINT_UNKNOWN',
    );
    await Future<void>.delayed(Duration.zero);
    expect(rig.transport.connectionRequestCount, 1);
    expect(rig.service.isEndpointCurrent('endpoint-x'), isFalse);

    rig.transport.simulatePeer(
      id: 'endpoint-y',
      name: 'Peer',
      identityFingerprintHint: fingerprint,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(rig.transport.connectionRequestCount, 2);
    expect(
      rig.service.peerStates['endpoint-y'],
      NearbyConnectionState.connecting,
    );
    expect(rig.service.transportAttemptResults, hasLength(1));

    rig.transport.resolveConnectionRequest(
      'endpoint-y',
      connected: false,
      rawStatusCode: 8011,
      rawStatusName: 'STATUS_ENDPOINT_UNKNOWN',
    );
    await Future<void>.delayed(Duration.zero);
    rig.transport.simulatePeer(
      id: 'endpoint-z',
      name: 'Peer',
      identityFingerprintHint: fingerprint,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rig.transport.connectionRequestCount, 2);
  });

  test(
    'pause-discovery mode pauses only discovery and resumes after failure',
    () async {
      await rig.service.configureTransportTestMode(
        NearbyTransportTestMode.clusterPauseDiscovery,
      );
      await rig.service.startSession();
      rig.transport.holdConnectionRequests = true;
      rig.transport.simulatePeer(id: 'pause-peer', name: 'Peer');
      await Future<void>.delayed(Duration.zero);

      await rig.service.connect('pause-peer');
      expect(rig.service.isDiscovering, isFalse);
      expect(rig.service.isAdvertising, isTrue);
      expect(rig.transport.disconnectCount, 0);

      rig.transport.resolveConnectionRequest(
        'pause-peer',
        connected: false,
        rawStatusCode: 13,
        rawStatusName: 'ERROR',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(rig.service.isDiscovering, isTrue);
      expect(rig.service.isAdvertising, isTrue);
      expect(rig.transport.disconnectCount, 0);
    },
  );

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
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (rig.service.peerStates['stale-peer'] !=
            NearbyConnectionState.failed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

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
      expect(
        rig.service.peerStates['lost-peer'],
        NearbyConnectionState.connecting,
      );
      final log = await rig.logText();
      expect(log, contains('endpoint_loss_ignored_for_active_negotiation'));
      expect(log, isNot(contains('ENDPOINT_LOST_DURING_NEGOTIATION')));
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
      // A transport may re-emit a bonded/discovered endpoint after the
      // identity handshake. That refresh must not erase authenticated mapping.
      pair.transportA.discoverPeer();
      await Future<void>.delayed(Duration.zero);
      final refreshedPeer = pair.serviceA.discoveredPeers.singleWhere(
        (peer) => peer.endpointId == 'endpoint-b',
      );
      expect(refreshedPeer.deviceId, deviceB);
      expect(pair.serviceA.isDeviceConnected(deviceB), isTrue);
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
  int _discoveryEpoch = 0;
  bool isDiscovering = false;
  bool isAdvertising = false;
  NearbyTransportTestMode _testMode = NearbyTransportTestMode.clusterBaseline;

  @override
  String get implementationName => 'TwoPeerNativeHarness';
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

  void discoverPeer() => _peers.add(
    NearbyPeer(
      id: remoteEndpointId,
      name: remoteName,
      identityFingerprintHint: remoteFingerprint,
      discoveryEpoch: _discoveryEpoch,
      foundAt: DateTime.now().toUtc(),
      lastSeenAt: DateTime.now().toUtc(),
    ),
  );

  void simulateIncomingConnection({
    required String id,
    required String name,
    String? identityFingerprintHint,
    bool isIncomingRequest = true,
  }) => _connections.add(
    NearbyConnectionEvent(
      peer: NearbyPeer(
        id: id,
        name: name,
        identityFingerprintHint: identityFingerprintHint,
      ),
      state: NearbyConnectionState.incomingRequest,
      isIncomingRequest: isIncomingRequest,
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
  }) async {
    isAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    isAdvertising = false;
  }

  @override
  Future<void> startDiscovery() async {
    if (!isDiscovering) _discoveryEpoch++;
    isDiscovering = true;
  }

  @override
  Future<void> stopDiscovery() async {
    if (isDiscovering) _discoveryEpoch++;
    isDiscovering = false;
  }

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
  Future<String?> sendBytes(
    Uint8List bytes, {
    String? peerId,
    bool capturePayloadDiagnostics = false,
  }) async {
    if (!connected) throw StateError('peer is not connected');
    other._payloads.add(
      NearbyPayloadEvent(peerId: localEndpointId, bytes: bytes),
    );
    return null;
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
