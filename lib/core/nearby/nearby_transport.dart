import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class NearbyPeer {
  const NearbyPeer({
    required this.id,
    required this.name,
    this.connected = false,
    this.deviceId,
    this.identityFingerprintHint,
    this.capabilities = const [],
    this.isLost = false,
  });

  /// Transport endpoint identity. This may change between sessions.
  final String id;
  String get endpointId => id;
  final String name;
  final bool connected;

  /// RELIO's stable application identity, learned from the hello packet.
  final String? deviceId;

  /// Public-key fingerprint advertised as a candidate hint, never as proof.
  final String? identityFingerprintHint;

  /// Capabilities learned from the completed RELIO hello handshake.
  final List<String> capabilities;

  /// True when the transport explicitly reports the endpoint is no longer seen.
  final bool isLost;
}

class NearbyPayloadEvent {
  const NearbyPayloadEvent({required this.peerId, required this.bytes});
  final String peerId;
  final Uint8List bytes;
}

class NearbyFilePayloadEvent {
  const NearbyFilePayloadEvent({
    required this.peerId,
    required this.payloadId,
    required this.filePath,
    this.uri,
  });

  final String peerId;
  final String payloadId;
  final String filePath;
  final String? uri;
}

enum NearbyTransferStatus { started, inProgress, success, failure, cancelled }

class NearbyTransferEvent {
  const NearbyTransferEvent({
    required this.peerId,
    required this.payloadId,
    required this.status,
    required this.bytesTransferred,
    required this.totalBytes,
    this.error,
  });

  final String peerId;
  final String payloadId;
  final NearbyTransferStatus status;
  final int bytesTransferred;
  final int totalBytes;
  final String? error;
}

enum NearbyConnectionState {
  incomingRequest,
  connecting,
  connected,
  disconnected,
  failed,
}

class NearbyConnectionEvent {
  const NearbyConnectionEvent({
    required this.peer,
    required this.state,
    this.error,
    this.authenticationToken,
    this.isIncomingRequest = false,
  });

  final NearbyPeer peer;
  final NearbyConnectionState state;
  final String? error;
  final String? authenticationToken;
  final bool isIncomingRequest;
}

const relioNearbyServiceId = 'com.relio.relio_mobile';
const relioNearbyStrategyName = 'P2P_CLUSTER';

class NearbyTransportException implements Exception {
  const NearbyTransportException(
    this.message, {
    this.code = 'transport_error',
    this.operation,
    this.exceptionType,
    this.platformCode,
    this.platformMessage,
    this.platformDetails,
    this.apiStatusCode,
    this.apiStatusName,
    this.returnedFalse = false,
  });

  final String message;
  final String code;
  final String? operation;
  final String? exceptionType;
  final String? platformCode;
  final String? platformMessage;
  final Object? platformDetails;
  final int? apiStatusCode;
  final String? apiStatusName;
  final bool returnedFalse;

  @override
  String toString() {
    final fields = [
      if (operation != null) 'operation=$operation',
      if (exceptionType != null) 'exceptionType=$exceptionType',
      if (platformCode != null) 'platformCode=$platformCode',
      if (platformMessage != null) 'platformMessage=$platformMessage',
      if (platformDetails != null) 'platformDetails=$platformDetails',
      if (apiStatusCode != null) 'apiStatusCode=$apiStatusCode',
      if (apiStatusName != null) 'apiStatusName=$apiStatusName',
      if (returnedFalse) 'result=false',
    ];
    return 'NearbyTransportException: $message'
        '${fields.isEmpty ? '' : ' (${fields.join(', ')})'}';
  }
}

abstract interface class NearbyTransport {
  String get implementationName;
  String get serviceId;
  String get strategyName;
  Stream<NearbyPeer> get discoveredPeers;
  Stream<NearbyPayloadEvent> get incomingPayloads;
  Stream<NearbyFilePayloadEvent> get incomingFilePayloads;
  Stream<NearbyTransferEvent> get transferEvents;
  Stream<NearbyConnectionEvent> get connectionEvents;
  Future<void> startAdvertising({
    required String displayName,
    String? identityFingerprint,
  });
  Future<void> stopAdvertising();
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Future<void> resetSessionOperations();
  Future<void> acceptConnection(String peerId);
  Future<void> rejectConnection(String peerId);
  Future<void> requestConnection(String peerId);
  Future<void> disconnect(String peerId);
  Future<void> sendBytes(Uint8List bytes, {String? peerId});
  Future<String> sendFile(String filePath, {String? peerId});
  Future<void> dispose();
}

class MockNearbyTransport implements NearbyTransport {
  MockNearbyTransport({
    this.autoAcknowledge = false,
    this.failSends = false,
    this.autoCompleteFiles = true,
  });

  final bool autoAcknowledge;
  bool failSends;
  bool failFileSends = false;
  final bool autoCompleteFiles;
  final _peers = StreamController<NearbyPeer>.broadcast();
  final _payloads = StreamController<NearbyPayloadEvent>.broadcast();
  final _connections = StreamController<NearbyConnectionEvent>.broadcast();
  final _files = StreamController<NearbyFilePayloadEvent>.broadcast();
  final _transfers = StreamController<NearbyTransferEvent>.broadcast();
  final List<Uint8List> sentPayloads = [];
  final List<String> sentFiles = [];
  final Map<String, NearbyPeer> peers = {};
  Duration startDelay = Duration.zero;
  NearbyTransportException? advertisingStartFailure;
  NearbyTransportException? discoveryStartFailure;
  int advertisingStartCount = 0;
  int discoveryStartCount = 0;
  int resetSessionOperationsCount = 0;
  int connectionRequestCount = 0;
  bool holdConnectionRequests = false;
  final Set<String> acceptedConnections = {};
  final Set<String> rejectedConnections = {};
  bool isAdvertising = false;
  bool isDiscovering = false;
  bool isDisposed = false;

  @override
  String get implementationName => 'MockNearbyTransport';

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
  Future<void> startAdvertising({
    required String displayName,
    String? identityFingerprint,
  }) async {
    advertisingStartCount++;
    if (startDelay > Duration.zero) await Future<void>.delayed(startDelay);
    if (advertisingStartFailure case final failure?) throw failure;
    isAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    isAdvertising = false;
  }

  @override
  Future<void> startDiscovery() async {
    discoveryStartCount++;
    if (startDelay > Duration.zero) await Future<void>.delayed(startDelay);
    if (discoveryStartFailure case final failure?) throw failure;
    isDiscovering = true;
  }

  @override
  Future<void> stopDiscovery() async {
    isDiscovering = false;
  }

  @override
  Future<void> resetSessionOperations() async {
    resetSessionOperationsCount++;
    isAdvertising = false;
    isDiscovering = false;
  }

  @override
  Future<void> acceptConnection(String peerId) async {
    acceptedConnections.add(peerId);
  }

  @override
  Future<void> rejectConnection(String peerId) async {
    rejectedConnections.add(peerId);
  }

  @override
  Future<void> requestConnection(String peerId) async {
    connectionRequestCount++;
    final peer = peers[peerId];
    if (peer == null) {
      throw const NearbyTransportException('Mock peer was not discovered.');
    }
    if (peer.connected) return;
    _connections.add(
      NearbyConnectionEvent(
        peer: peer,
        state: NearbyConnectionState.connecting,
      ),
    );
    if (holdConnectionRequests) return;
    final connected = NearbyPeer(
      id: peer.id,
      name: peer.name,
      connected: true,
      deviceId: peer.deviceId,
    );
    peers[peerId] = connected;
    _connections.add(
      NearbyConnectionEvent(
        peer: connected,
        state: NearbyConnectionState.connected,
      ),
    );
  }

  @override
  Future<void> disconnect(String peerId) async {
    final peer = peers[peerId];
    if (peer == null) return;
    final disconnected = NearbyPeer(id: peer.id, name: peer.name);
    peers[peerId] = disconnected;
    _connections.add(
      NearbyConnectionEvent(
        peer: disconnected,
        state: NearbyConnectionState.disconnected,
      ),
    );
  }

  @override
  Future<void> sendBytes(Uint8List bytes, {String? peerId}) async {
    if (failSends) {
      throw const NearbyTransportException('Mock send failure.');
    }
    sentPayloads.add(bytes);
  }

  @override
  Future<String> sendFile(String filePath, {String? peerId}) async {
    if (failFileSends || failSends) {
      throw const NearbyTransportException('Mock file send failure.');
    }
    final payloadId = 'mock-payload-${sentFiles.length + 1}';
    sentFiles.add(filePath);
    final totalBytes = await File(filePath).length();
    _transfers.add(
      NearbyTransferEvent(
        peerId: peerId ?? 'broadcast',
        payloadId: payloadId,
        status: NearbyTransferStatus.started,
        bytesTransferred: 0,
        totalBytes: totalBytes,
      ),
    );
    if (autoCompleteFiles) {
      _transfers.add(
        NearbyTransferEvent(
          peerId: peerId ?? 'broadcast',
          payloadId: payloadId,
          status: NearbyTransferStatus.success,
          bytesTransferred: totalBytes,
          totalBytes: totalBytes,
        ),
      );
    }
    return payloadId;
  }

  void simulatePeer({
    required String id,
    required String name,
    String? deviceId,
    String? identityFingerprintHint,
    List<String> capabilities = const [],
  }) {
    final peer = NearbyPeer(
      id: id,
      name: name,
      deviceId: deviceId,
      identityFingerprintHint: identityFingerprintHint,
      capabilities: capabilities,
    );
    peers[id] = peer;
    _peers.add(peer);
  }

  void simulateIncomingConnection({
    required String id,
    required String name,
    String? identityFingerprintHint,
    String? authenticationToken,
  }) {
    final peer = NearbyPeer(
      id: id,
      name: name,
      identityFingerprintHint: identityFingerprintHint,
    );
    peers[id] = peer;
    _connections.add(
      NearbyConnectionEvent(
        peer: peer,
        state: NearbyConnectionState.incomingRequest,
        authenticationToken: authenticationToken,
        isIncomingRequest: true,
      ),
    );
  }

  void simulateIncoming({required String peerId, required Uint8List bytes}) {
    _payloads.add(NearbyPayloadEvent(peerId: peerId, bytes: bytes));
  }

  void simulateIncomingFile({
    required String peerId,
    required String payloadId,
    required String filePath,
    String? uri,
  }) => _files.add(
    NearbyFilePayloadEvent(
      peerId: peerId,
      payloadId: payloadId,
      filePath: filePath,
      uri: uri,
    ),
  );

  void simulateTransfer({
    required String peerId,
    required String payloadId,
    required NearbyTransferStatus status,
    required int bytesTransferred,
    required int totalBytes,
    String? error,
  }) => _transfers.add(
    NearbyTransferEvent(
      peerId: peerId,
      payloadId: payloadId,
      status: status,
      bytesTransferred: bytesTransferred,
      totalBytes: totalBytes,
      error: error,
    ),
  );

  void simulateConnectionLoss(String peerId) {
    final peer = peers[peerId];
    if (peer == null) return;
    _connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(id: peer.id, name: peer.name),
        state: NearbyConnectionState.disconnected,
        error: 'Mock connection loss',
      ),
    );
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await Future.wait([
      _peers.close(),
      _payloads.close(),
      _connections.close(),
      _files.close(),
      _transfers.close(),
    ]);
  }
}
