import 'dart:async';

import 'package:flutter/services.dart';

import 'nearby_transport.dart';

String? bluetoothClassicAddressSuffix(String endpointId) {
  const prefix = 'classic:';
  if (!endpointId.startsWith(prefix)) return null;
  final address = endpointId.substring(prefix.length).toUpperCase();
  if (!RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(address)) {
    return null;
  }
  final octets = address.split(':');
  return '...:${octets[4]}:${octets[5]}';
}

/// Dart adapter for the Android secure RFCOMM compatibility transport.
/// Application packets remain opaque here and are handled by NearbyService.
/// ฝั่งนี้แปลง MethodChannel เป็น NearbyTransport โดยไม่ตีความเนื้อหา packet
class BluetoothClassicTransport implements NearbyTransport {
  BluetoothClassicTransport({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methods =
           methodChannel ?? const MethodChannel('relio/bluetooth_classic'),
       _events =
           eventChannel ?? const EventChannel('relio/bluetooth_classic/events');

  final MethodChannel _methods;
  final EventChannel _events;
  final _peers = StreamController<NearbyPeer>.broadcast();
  final _payloads = StreamController<NearbyPayloadEvent>.broadcast();
  final _files = StreamController<NearbyFilePayloadEvent>.broadcast();
  final _transfers = StreamController<NearbyTransferEvent>.broadcast();
  final _connections = StreamController<NearbyConnectionEvent>.broadcast();
  final _diagnostics = StreamController<NearbyNativeDiagnostic>.broadcast();
  StreamSubscription<dynamic>? _eventSubscription;
  final Set<String> _connectedPeers = <String>{};
  final Map<String, NearbyPeer> _peersById = <String, NearbyPeer>{};
  bool _advertising = false;
  bool _discovering = false;
  bool _disposed = false;
  int _discoveryEpoch = 0;

  @override
  String get implementationName => 'BluetoothClassicTransport (RFCOMM)';

  @override
  String get serviceId => relioNearbyServiceId;

  @override
  String get strategyName => 'BLUETOOTH_CLASSIC_RFCOMM';

  @override
  NearbyTransportTestMode get testMode =>
      NearbyTransportTestMode.clusterBaseline;

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
  Stream<NearbyNativeDiagnostic> get nativeDiagnostics => _diagnostics.stream;

  @override
  Future<Map<String, Object?>> diagnosticSnapshot() async {
    final result = await _methods.invokeMethod<Map<Object?, Object?>>(
      'snapshot',
    );
    return {
      ...?result?.map((key, value) => MapEntry('$key', value)),
      'transport': strategyName,
      'discoveryEpoch': _discoveryEpoch,
      'advertisingActive': _advertising,
      'discoveryActive': _discovering,
      'connectedPeers': _connectedPeers.length,
    };
  }

  Future<List<BondedBluetoothDevice>> bondedBluetoothDevices() async {
    if (_disposed) return const [];
    _listenOnce();
    final result = await _methods.invokeListMethod<Object?>('bondedDevices');
    final devices = <BondedBluetoothDevice>[];
    for (final item in result ?? const <Object?>[]) {
      if (item is! Map) continue;
      final values = item.map((key, value) => MapEntry('$key', value));
      devices.add(
        BondedBluetoothDevice(
          address: values['address'] as String? ?? '',
          name: _safeName(values['name'] as String?),
          bondState: values['bondState'] as String? ?? 'NONE',
        ),
      );
    }
    return deduplicateBondedBluetoothDevices(devices);
  }

  @override
  Future<void> configureTestMode(NearbyTransportTestMode mode) async {}

  void _listenOnce() {
    _eventSubscription ??= _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object error) => _diagnostics.add(
        NearbyNativeDiagnostic(
          name: 'bluetooth_classic_event_error',
          fields: {'exceptionClass': error.runtimeType.toString()},
        ),
      ),
    );
  }

  @override
  Future<void> startAdvertising({
    required String displayName,
    String? identityFingerprint,
  }) async {
    if (_disposed) return;
    _listenOnce();
    await _methods.invokeMethod<void>('startAdvertising', {
      'displayName': displayName,
    });
    _advertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    if (!_advertising) return;
    await _methods.invokeMethod<void>('stopAdvertising');
    _advertising = false;
  }

  @override
  Future<void> startDiscovery() async {
    if (_disposed || _discovering) return;
    _listenOnce();
    _discoveryEpoch++;
    await _methods.invokeMethod<void>('startDiscovery');
    _discovering = true;
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_discovering) return;
    _discoveryEpoch++;
    await _methods.invokeMethod<void>('stopDiscovery');
    _discovering = false;
    _peersById.clear();
  }

  @override
  Future<void> resetSessionOperations() async {
    await _methods.invokeMethod<void>('reset');
    _discovering = false;
    _advertising = false;
    _peersById.clear();
  }

  @override
  Future<void> acceptConnection(
    String peerId, {
    String? connectionTraceId,
  }) async {
    await _methods.invokeMethod<void>('acceptConnection', {'peerId': peerId});
  }

  @override
  Future<void> rejectConnection(
    String peerId, {
    String? connectionTraceId,
  }) async {
    await _methods.invokeMethod<void>('rejectConnection', {'peerId': peerId});
  }

  @override
  Future<void> requestConnection(
    String peerId, {
    String? identityFingerprint,
    String? connectionTraceId,
  }) async {
    await _methods.invokeMethod<void>('requestConnection', {'peerId': peerId});
  }

  @override
  Future<void> disconnect(String peerId) async {
    await _methods.invokeMethod<void>('disconnect', {'peerId': peerId});
  }

  @override
  Future<void> sendBytes(Uint8List bytes, {String? peerId}) async {
    final recipients = peerId == null ? _connectedPeers.toList() : [peerId];
    if (recipients.isEmpty) {
      throw const NearbyTransportException('No connected Bluetooth peer.');
    }
    for (final recipient in recipients) {
      await _methods.invokeMethod<void>('sendBytes', {
        'peerId': recipient,
        'bytes': bytes,
      });
    }
  }

  @override
  Future<String> sendFile(String filePath, {String? peerId}) async {
    final recipients = peerId == null ? _connectedPeers.toList() : [peerId];
    if (recipients.isEmpty) {
      throw const NearbyTransportException('No connected Bluetooth peer.');
    }
    final result = await _methods.invokeMethod<String>('sendFile', {
      'peerId': recipients.first,
      'path': filePath,
    });
    if (result == null || result.isEmpty) {
      throw const NearbyTransportException('Bluetooth file transfer failed.');
    }
    return result;
  }

  void _onEvent(Object? raw) {
    if (raw is! Map) return;
    final event = raw.map((key, value) => MapEntry('$key', value));
    final kind = event['kind'];
    final peerId = event['peerId'] as String?;
    if (kind == 'peerFound' && peerId != null) {
      final peer = NearbyPeer(
        id: peerId,
        name: _safeName(event['name'] as String?),
        discoveryEpoch: _discoveryEpoch,
        foundAt: DateTime.now().toUtc(),
        lastSeenAt: DateTime.now().toUtc(),
      );
      _peersById[peerId] = peer;
      _peers.add(peer);
      return;
    }
    if (kind == 'peerLost' && peerId != null) {
      final old = _peersById.remove(peerId);
      if (old != null) {
        _peers.add(
          NearbyPeer(
            id: peerId,
            name: old.name,
            isLost: true,
            isCurrent: false,
            discoveryEpoch: old.discoveryEpoch,
            foundAt: old.foundAt,
            lastSeenAt: old.lastSeenAt,
            lostAt: DateTime.now().toUtc(),
          ),
        );
      }
      return;
    }
    if (kind == 'bytes' && peerId != null) {
      final bytes = _bytes(event['bytes']);
      if (bytes != null) {
        _payloads.add(NearbyPayloadEvent(peerId: peerId, bytes: bytes));
      }
      return;
    }
    if (kind == 'file' && peerId != null) {
      final path = event['path'] as String?;
      final payloadId = event['payloadId'] as String?;
      if (path != null && payloadId != null) {
        _files.add(
          NearbyFilePayloadEvent(
            peerId: peerId,
            payloadId: payloadId,
            filePath: path,
          ),
        );
      }
      return;
    }
    if (kind == 'transfer' && peerId != null) {
      _transfers.add(
        NearbyTransferEvent(
          peerId: peerId,
          payloadId: event['payloadId'] as String? ?? 'unknown',
          status: _transferStatus(event['status'] as String?),
          bytesTransferred: (event['bytesTransferred'] as num?)?.toInt() ?? 0,
          totalBytes: (event['totalBytes'] as num?)?.toInt() ?? 0,
          error: event['error'] as String?,
        ),
      );
      return;
    }
    if (kind == 'connection' && peerId != null) {
      final state = _connectionState(event['state'] as String?);
      final peer =
          _peersById[peerId] ??
          NearbyPeer(id: peerId, name: _safeName(event['name'] as String?));
      final connected = state == NearbyConnectionState.connected;
      final updated = NearbyPeer(
        id: peer.id,
        name: peer.name,
        connected: connected,
        deviceId: peer.deviceId,
        identityFingerprintHint: peer.identityFingerprintHint,
        discoveryEpoch: peer.discoveryEpoch,
        foundAt: peer.foundAt,
        lastSeenAt: DateTime.now().toUtc(),
      );
      _peersById[peerId] = updated;
      if (connected) {
        _connectedPeers.add(peerId);
      } else if (state == NearbyConnectionState.disconnected ||
          state == NearbyConnectionState.failed) {
        _connectedPeers.remove(peerId);
      }
      _connections.add(
        NearbyConnectionEvent(
          peer: updated,
          state: state,
          error: event['error'] as String?,
          isIncomingRequest: event['incoming'] == true,
          operation: 'bluetoothClassic',
        ),
      );
      return;
    }
    if (kind == 'diagnostic') {
      _diagnostics.add(
        NearbyNativeDiagnostic(
          name: event['name'] as String? ?? 'bluetooth_classic',
          fields: event['fields'] is Map
              ? (event['fields'] as Map).map(
                  (key, value) => MapEntry('$key', value),
                )
              : const {},
        ),
      );
    }
  }

  String _safeName(String? value) {
    final name = value?.trim();
    return name == null || name.isEmpty
        ? 'Bluetooth • RELIO'
        : name.substring(0, name.length.clamp(1, 80));
  }

  Uint8List? _bytes(Object? value) => value is Uint8List
      ? value
      : value is List
      ? Uint8List.fromList(
          value.whereType<num>().map((item) => item.toInt()).toList(),
        )
      : null;

  NearbyTransferStatus _transferStatus(String? value) => switch (value) {
    'started' => NearbyTransferStatus.started,
    'inProgress' => NearbyTransferStatus.inProgress,
    'success' => NearbyTransferStatus.success,
    'cancelled' => NearbyTransferStatus.cancelled,
    _ => NearbyTransferStatus.failure,
  };

  NearbyConnectionState _connectionState(String? value) => switch (value) {
    'incomingRequest' => NearbyConnectionState.incomingRequest,
    'connecting' => NearbyConnectionState.connecting,
    'connected' => NearbyConnectionState.connected,
    'disconnected' => NearbyConnectionState.disconnected,
    _ => NearbyConnectionState.failed,
  };

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSubscription?.cancel();
    await _methods.invokeMethod<void>('dispose');
    await Future.wait([
      _peers.close(),
      _payloads.close(),
      _files.close(),
      _transfers.close(),
      _connections.close(),
      _diagnostics.close(),
    ]);
  }
}

class CompatibilityNearbyTransport
    implements
        NearbyTransport,
        CompatibilityTransport,
        NearbyIdleSessionRecovery {
  CompatibilityNearbyTransport({
    required this.primary,
    required this.compatibility,
  }) {
    _forward(primary);
    _forward(compatibility);
  }

  final NearbyTransport primary;
  final NearbyTransport compatibility;
  final _peers = StreamController<NearbyPeer>.broadcast();
  final _payloads = StreamController<NearbyPayloadEvent>.broadcast();
  final _files = StreamController<NearbyFilePayloadEvent>.broadcast();
  final _transfers = StreamController<NearbyTransferEvent>.broadcast();
  final _connections = StreamController<NearbyConnectionEvent>.broadcast();
  final _diagnostics = StreamController<NearbyNativeDiagnostic>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<String> _compatibilityPeers = <String>{};
  bool _active = false;
  bool? _serverRole;
  String _displayName = 'RELIO';
  String? _identityFingerprint;

  @override
  String get implementationName => 'CompatibilityNearbyTransport';

  @override
  String get serviceId => primary.serviceId;

  @override
  String get strategyName =>
      _active ? compatibility.strategyName : primary.strategyName;

  @override
  NearbyTransportTestMode get testMode => primary.testMode;

  @override
  int get discoveryEpoch =>
      _active ? compatibility.discoveryEpoch : primary.discoveryEpoch;

  @override
  bool get compatibilityModeActive => _active;

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
  Stream<NearbyNativeDiagnostic> get nativeDiagnostics => _diagnostics.stream;

  void _forward(NearbyTransport source) {
    _subscriptions.add(source.discoveredPeers.listen(_peers.add));
    _subscriptions.add(source.incomingPayloads.listen(_payloads.add));
    _subscriptions.add(source.incomingFilePayloads.listen(_files.add));
    _subscriptions.add(source.transferEvents.listen(_transfers.add));
    _subscriptions.add(
      source.connectionEvents.listen((event) {
        if (source == compatibility &&
            event.peer.endpointId.startsWith('classic:')) {
          _compatibilityPeers.add(event.peer.endpointId);
        }
        _connections.add(event);
      }),
    );
    _subscriptions.add(source.nativeDiagnostics.listen(_diagnostics.add));
  }

  @override
  Future<Map<String, Object?>> diagnosticSnapshot() async => {
    ...await primary.diagnosticSnapshot(),
    if (_active) ...{
      'compatibilityMode': true,
      ...await compatibility.diagnosticSnapshot(),
    } else
      'compatibilityMode': false,
  };

  @override
  Future<void> configureTestMode(NearbyTransportTestMode mode) =>
      primary.configureTestMode(mode);

  @override
  Future<void> startAdvertising({
    required String displayName,
    String? identityFingerprint,
  }) async {
    _displayName = displayName;
    _identityFingerprint = identityFingerprint;
    if (_active) {
      if (_serverRole == true) {
        await compatibility.startAdvertising(
          displayName: displayName,
          identityFingerprint: identityFingerprint,
        );
      }
      return;
    }
    await primary.startAdvertising(
      displayName: displayName,
      identityFingerprint: identityFingerprint,
    );
  }

  @override
  Future<void> stopAdvertising() async {
    await primary.stopAdvertising();
    if (_active) await compatibility.stopAdvertising();
  }

  @override
  Future<void> startDiscovery() async {
    if (_active) {
      if (_serverRole == false) await compatibility.startDiscovery();
      return;
    }
    await primary.startDiscovery();
  }

  @override
  Future<void> stopDiscovery() async {
    await primary.stopDiscovery();
    if (_active) await compatibility.stopDiscovery();
  }

  @override
  Future<void> resetSessionOperations() async {
    await primary.resetSessionOperations();
    await compatibility.resetSessionOperations();
  }

  @override
  Future<void> clearIdleEndpoints() async {
    if (_active) {
      throw StateError('Cannot reset Nearby endpoints during Classic mode.');
    }
    if (primary case NearbyIdleSessionRecovery recovery) {
      await recovery.clearIdleEndpoints();
    }
  }

  @override
  Future<void> activateCompatibilityMode({
    required bool serverRole,
    bool bondedOnly = false,
  }) async {
    if (_active) return;
    _active = true;
    _serverRole = serverRole;
    // หยุด discovery/advertising ของ Google Nearby ก่อนเปิด RFCOMM เพื่อไม่ให้
    // ทั้งสอง transport แย่ง Bluetooth session เดียวกันระหว่าง fallback
    await primary.stopDiscovery();
    await primary.stopAdvertising();
    try {
      if (serverRole) {
        await compatibility.startAdvertising(
          displayName: _displayName,
          identityFingerprint: _identityFingerprint,
        );
      } else if (!bondedOnly) {
        await compatibility.startDiscovery();
      }
    } on Object {
      _active = false;
      _serverRole = null;
      rethrow;
    }
    _diagnostics.add(
      const NearbyNativeDiagnostic(
        name: 'compatibility_mode_activated',
        fields: {'transport': 'BLUETOOTH_CLASSIC_RFCOMM'},
      ),
    );
  }

  @override
  Future<List<BondedBluetoothDevice>> bondedBluetoothDevices() =>
      (compatibility as BluetoothClassicTransport).bondedBluetoothDevices();

  NearbyTransport _sourceFor(String peerId) =>
      peerId.startsWith('classic:') ? compatibility : primary;

  @override
  Future<void> acceptConnection(String peerId, {String? connectionTraceId}) =>
      _sourceFor(
        peerId,
      ).acceptConnection(peerId, connectionTraceId: connectionTraceId);

  @override
  Future<void> rejectConnection(String peerId, {String? connectionTraceId}) =>
      _sourceFor(
        peerId,
      ).rejectConnection(peerId, connectionTraceId: connectionTraceId);

  @override
  Future<void> requestConnection(
    String peerId, {
    String? identityFingerprint,
    String? connectionTraceId,
  }) => _sourceFor(peerId).requestConnection(
    peerId,
    identityFingerprint: identityFingerprint,
    connectionTraceId: connectionTraceId,
  );

  @override
  Future<void> disconnect(String peerId) =>
      _sourceFor(peerId).disconnect(peerId);

  @override
  Future<void> sendBytes(Uint8List bytes, {String? peerId}) async {
    if (peerId != null) {
      return _sourceFor(peerId).sendBytes(bytes, peerId: peerId);
    }
    await primary.sendBytes(bytes, peerId: peerId);
    if (_active && _compatibilityPeers.isNotEmpty) {
      await compatibility.sendBytes(bytes, peerId: peerId);
    }
  }

  @override
  Future<String> sendFile(String filePath, {String? peerId}) =>
      _sourceFor(peerId ?? '').sendFile(filePath, peerId: peerId);

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await primary.dispose();
    await compatibility.dispose();
    await Future.wait([
      _peers.close(),
      _payloads.close(),
      _files.close(),
      _transfers.close(),
      _connections.close(),
      _diagnostics.close(),
    ]);
  }
}
