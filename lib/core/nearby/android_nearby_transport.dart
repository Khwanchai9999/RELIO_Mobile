import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'nearby_transport.dart';

class AndroidNearbyTransport implements NearbyTransport {
  AndroidNearbyTransport({this.serviceId = 'com.relio.relio_mobile'});

  final String serviceId;
  final Nearby _nearby = Nearby();
  final _peers = StreamController<NearbyPeer>.broadcast();
  final _payloads = StreamController<NearbyPayloadEvent>.broadcast();
  final _files = StreamController<NearbyFilePayloadEvent>.broadcast();
  final _transfers = StreamController<NearbyTransferEvent>.broadcast();
  final _connections = StreamController<NearbyConnectionEvent>.broadcast();
  final Set<String> _connectedPeers = {};
  final Set<String> _connectionRequests = {};
  final Map<String, String> _peerNames = {};
  bool _advertising = false;
  bool _discovering = false;
  bool _disposed = false;

  @override
  String get implementationName =>
      'AndroidNearbyTransport (nearby_connections)';

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
    if (_disposed || _advertising) return;
    try {
      final started = await _nearby.startAdvertising(
        displayName,
        Strategy.P2P_CLUSTER,
        serviceId: serviceId,
        onConnectionInitiated: _acceptConnection,
        onConnectionResult: _connectionResult,
        onDisconnected: _disconnected,
      );
      if (!started) {
        throw const NearbyTransportException(
          'Android advertising was rejected.',
        );
      }
      _advertising = true;
    } on NearbyTransportException {
      rethrow;
    } on Object catch (error) {
      throw NearbyTransportException('Unable to start advertising: $error');
    }
  }

  @override
  Future<void> stopAdvertising() async {
    if (!_advertising) return;
    await _nearby.stopAdvertising();
    _advertising = false;
  }

  @override
  Future<void> startDiscovery() async {
    if (_disposed || _discovering) return;
    try {
      final started = await _nearby.startDiscovery(
        serviceId,
        Strategy.P2P_CLUSTER,
        serviceId: serviceId,
        onEndpointFound: (id, name, _) {
          _peerNames[id] = name;
          _peers.add(NearbyPeer(id: id, name: name));
        },
        onEndpointLost: (id) {
          if (id != null) _peerNames.remove(id);
        },
      );
      if (!started) {
        throw const NearbyTransportException('Android discovery was rejected.');
      }
      _discovering = true;
    } on NearbyTransportException {
      rethrow;
    } on Object catch (error) {
      throw NearbyTransportException('Unable to start discovery: $error');
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_discovering) return;
    await _nearby.stopDiscovery();
    _discovering = false;
  }

  @override
  Future<void> requestConnection(String peerId) async {
    if (_disposed || _connectedPeers.contains(peerId)) return;
    if (!_connectionRequests.add(peerId)) return;
    _connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(id: peerId, name: _peerNames[peerId] ?? peerId),
        state: NearbyConnectionState.connecting,
      ),
    );
    try {
      final requested = await _nearby.requestConnection(
        'RELIO',
        peerId,
        onConnectionInitiated: _acceptConnection,
        onConnectionResult: _connectionResult,
        onDisconnected: _disconnected,
      );
      if (!requested) {
        throw const NearbyTransportException(
          'Android connection request failed.',
        );
      }
    } on NearbyTransportException {
      _connectionRequests.remove(peerId);
      rethrow;
    } on Object catch (error) {
      _connectionRequests.remove(peerId);
      throw NearbyTransportException('Unable to request connection: $error');
    }
  }

  @override
  Future<void> disconnect(String peerId) async {
    await _nearby.disconnectFromEndpoint(peerId);
    _connectedPeers.remove(peerId);
    _connectionRequests.remove(peerId);
  }

  @override
  Future<void> sendBytes(Uint8List bytes, {String? peerId}) async {
    final recipients = peerId == null ? _connectedPeers.toList() : [peerId];
    if (recipients.isEmpty) {
      throw const NearbyTransportException('No connected Nearby peer.');
    }
    for (final endpointId in recipients) {
      await _nearby.sendBytesPayload(endpointId, bytes);
    }
  }

  @override
  Future<String> sendFile(String filePath, {String? peerId}) async {
    final recipients = peerId == null ? _connectedPeers.toList() : [peerId];
    if (recipients.isEmpty) {
      throw const NearbyTransportException('No connected Nearby peer.');
    }
    final payloadIds = <String>[];
    for (final endpointId in recipients) {
      try {
        final payloadId = await _nearby.sendFilePayload(endpointId, filePath);
        payloadIds.add(payloadId.toString());
      } on Object catch (error) {
        throw NearbyTransportException('Unable to send file payload: $error');
      }
    }
    return payloadIds.first;
  }

  Future<void> _acceptConnection(String endpointId, ConnectionInfo info) async {
    _peerNames[endpointId] = info.endpointName;
    await _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (id, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _payloads.add(NearbyPayloadEvent(peerId: id, bytes: payload.bytes!));
        } else if (payload.type == PayloadType.FILE) {
          unawaited(_emitIncomingFile(id, payload));
        }
      },
      onPayloadTransferUpdate: (id, update) {
        _transfers.add(
          NearbyTransferEvent(
            peerId: id,
            payloadId: update.id.toString(),
            status: switch (update.status) {
              PayloadStatus.IN_PROGRESS => NearbyTransferStatus.inProgress,
              PayloadStatus.SUCCESS => NearbyTransferStatus.success,
              PayloadStatus.FAILURE => NearbyTransferStatus.failure,
              PayloadStatus.CANCELED => NearbyTransferStatus.cancelled,
              PayloadStatus.NONE => NearbyTransferStatus.started,
            },
            bytesTransferred: update.bytesTransferred,
            totalBytes: update.totalBytes,
          ),
        );
      },
    );
  }

  Future<void> _emitIncomingFile(String endpointId, Payload payload) async {
    // nearby_connections exposes a file path on older Android versions and a
    // content URI on newer versions. Normalize both to a real local path here
    // so the rest of RELIO never depends on plugin-specific URI handling.
    // ignore: deprecated_member_use
    final directPath = payload.filePath;
    if (directPath != null && directPath.isNotEmpty) {
      _files.add(
        NearbyFilePayloadEvent(
          peerId: endpointId,
          payloadId: payload.id.toString(),
          filePath: directPath,
          uri: payload.uri,
        ),
      );
      return;
    }
    final uri = payload.uri;
    if (uri == null || uri.isEmpty) return;
    try {
      final directory = await getTemporaryDirectory();
      final destination = path.join(
        directory.path,
        'relio-incoming-${const Uuid().v4()}',
      );
      final copied = await _nearby.copyFileAndDeleteOriginal(uri, destination);
      if (!copied || !await File(destination).exists()) return;
      _files.add(
        NearbyFilePayloadEvent(
          peerId: endpointId,
          payloadId: payload.id.toString(),
          filePath: destination,
          uri: uri,
        ),
      );
    } on Object catch (_) {
      // The transfer event will report failure; never expose a raw plugin
      // callback exception to application widgets.
    }
  }

  void _connectionResult(String endpointId, Status status) {
    _connectionRequests.remove(endpointId);
    final peer = NearbyPeer(
      id: endpointId,
      name: _peerNames[endpointId] ?? endpointId,
      connected: status == Status.CONNECTED,
    );
    if (status == Status.CONNECTED) {
      _connectedPeers.add(endpointId);
      _connections.add(
        NearbyConnectionEvent(
          peer: peer,
          state: NearbyConnectionState.connected,
        ),
      );
    } else {
      _connections.add(
        NearbyConnectionEvent(
          peer: peer,
          state: NearbyConnectionState.failed,
          error: status.name,
        ),
      );
    }
  }

  void _disconnected(String endpointId) {
    _connectedPeers.remove(endpointId);
    _connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(
          id: endpointId,
          name: _peerNames[endpointId] ?? endpointId,
        ),
        state: NearbyConnectionState.disconnected,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _nearby.stopAdvertising();
    await _nearby.stopDiscovery();
    await _nearby.stopAllEndpoints();
    await Future.wait([
      _peers.close(),
      _payloads.close(),
      _connections.close(),
      _files.close(),
      _transfers.close(),
    ]);
  }
}
