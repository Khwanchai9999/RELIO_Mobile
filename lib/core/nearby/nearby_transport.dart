import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class NearbyPeer {
  const NearbyPeer({
    required this.id,
    required this.name,
    this.connected = false,
    this.deviceId,
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

enum NearbyConnectionState { connecting, connected, disconnected, failed }

class NearbyConnectionEvent {
  const NearbyConnectionEvent({
    required this.peer,
    required this.state,
    this.error,
  });

  final NearbyPeer peer;
  final NearbyConnectionState state;
  final String? error;
}

class NearbyTransportException implements Exception {
  const NearbyTransportException(this.message);
  final String message;

  @override
  String toString() => 'NearbyTransportException: $message';
}

abstract interface class NearbyTransport {
  String get implementationName;
  Stream<NearbyPeer> get discoveredPeers;
  Stream<NearbyPayloadEvent> get incomingPayloads;
  Stream<NearbyFilePayloadEvent> get incomingFilePayloads;
  Stream<NearbyTransferEvent> get transferEvents;
  Stream<NearbyConnectionEvent> get connectionEvents;
  Future<void> startAdvertising({required String displayName});
  Future<void> stopAdvertising();
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
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
  bool isAdvertising = false;
  bool isDiscovering = false;
  bool isDisposed = false;

  @override
  String get implementationName => 'MockNearbyTransport';

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
  Future<void> startAdvertising({required String displayName}) async {
    isAdvertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    isAdvertising = false;
  }

  @override
  Future<void> startDiscovery() async {
    isDiscovering = true;
  }

  @override
  Future<void> stopDiscovery() async {
    isDiscovering = false;
  }

  @override
  Future<void> requestConnection(String peerId) async {
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
    List<String> capabilities = const [],
  }) {
    final peer = NearbyPeer(
      id: id,
      name: name,
      deviceId: deviceId,
      capabilities: capabilities,
    );
    peers[id] = peer;
    _peers.add(peer);
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
