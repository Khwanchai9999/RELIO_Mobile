import 'dart:async';
import 'dart:io';

import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'nearby_transport.dart';

class AndroidNearbyTransport implements NearbyTransport {
  AndroidNearbyTransport({this.serviceId = relioNearbyServiceId}) {
    _nearby.setNativeDiagnosticListener(_onNativeDiagnostic);
  }

  @override
  final String serviceId;
  final Nearby _nearby = Nearby();
  final _peers = StreamController<NearbyPeer>.broadcast();
  final _payloads = StreamController<NearbyPayloadEvent>.broadcast();
  final _files = StreamController<NearbyFilePayloadEvent>.broadcast();
  final _transfers = StreamController<NearbyTransferEvent>.broadcast();
  final _connections = StreamController<NearbyConnectionEvent>.broadcast();
  final _nativeDiagnostics =
      StreamController<NearbyNativeDiagnostic>.broadcast();
  final Map<String, NativeConnectionResult> _rawConnectionResults = {};
  final Set<String> _connectedPeers = {};
  final Set<String> _connectionRequests = {};
  final Set<String> _pendingConnectionRequests = {};
  final Map<String, String> _peerNames = {};
  final Map<String, String> _peerFingerprintHints = {};
  final Map<String, NearbyPeer> _discoveredEndpoints = {};
  bool _advertising = false;
  bool _discovering = false;
  bool _disposed = false;
  int _discoveryEpoch = 0;
  NearbyTransportTestMode _testMode = NearbyTransportTestMode.clusterBaseline;

  @override
  String get strategyName => _testMode.strategyName;

  @override
  NearbyTransportTestMode get testMode => _testMode;

  @override
  int get discoveryEpoch => _discoveryEpoch;

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
  Stream<NearbyNativeDiagnostic> get nativeDiagnostics =>
      _nativeDiagnostics.stream;

  @override
  Future<Map<String, Object?>> diagnosticSnapshot() async {
    final snapshot = await _nearby.getNativeDiagnostics();
    return {
      ...?snapshot?.map((key, value) => MapEntry('$key', value)),
      'transportTestMode': _testMode.diagnosticName,
      'discoveryEpoch': _discoveryEpoch,
      'discoveryActive': _discovering,
      'advertisingActive': _advertising,
      'strategy': strategyName,
    };
  }

  @override
  Future<void> configureTestMode(NearbyTransportTestMode mode) async {
    if (_advertising || _discovering) {
      throw StateError('Stop the Nearby session before changing test mode.');
    }
    _testMode = mode;
  }

  @override
  Future<void> startAdvertising({
    required String displayName,
    String? identityFingerprint,
  }) async {
    if (_disposed || _advertising) return;
    final endpointName = _endpointName(displayName, identityFingerprint);
    try {
      final started = await _nearby.startAdvertising(
        endpointName,
        _strategy,
        serviceId: serviceId,
        onConnectionInitiated: _connectionInitiated,
        onConnectionResult: _connectionResult,
        onRawConnectionResult: _rawConnectionResult,
        onDisconnected: _disconnected,
      );
      if (!started) {
        throw const NearbyTransportException(
          'Android startAdvertising returned false.',
          code: 'start_returned_false',
          operation: 'startAdvertising',
          exceptionType: 'bool',
          returnedFalse: true,
        );
      }
      _advertising = true;
    } on NearbyTransportException {
      rethrow;
    } on PlatformException catch (error) {
      throw _platformFailure('startAdvertising', error);
    } on Object catch (error) {
      throw NearbyTransportException(
        'Unable to start advertising: $error',
        code: _failureCode(error),
        operation: 'startAdvertising',
        exceptionType: error.runtimeType.toString(),
      );
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
    final callbackEpoch = ++_discoveryEpoch;
    try {
      final started = await _nearby.startDiscovery(
        serviceId,
        _strategy,
        serviceId: serviceId,
        onEndpointFound: (id, name, _) {
          if (callbackEpoch != _discoveryEpoch) return;
          final now = DateTime.now().toUtc();
          _peerNames[id] = name;
          final hint = _identityFingerprintHint(name);
          if (hint == null) {
            _peerFingerprintHints.remove(id);
          } else {
            _peerFingerprintHints[id] = hint;
          }
          final previous = _discoveredEndpoints[id];
          final peer = NearbyPeer(
            id: id,
            name: hint == null ? name : 'RELIO ${hint.substring(0, 8)}',
            identityFingerprintHint: hint,
            discoveryEpoch: callbackEpoch,
            foundAt: previous?.discoveryEpoch == callbackEpoch
                ? previous?.foundAt
                : now,
            lastSeenAt: now,
            isCurrent: true,
          );
          _discoveredEndpoints[id] = peer;
          _peers.add(peer);
        },
        onEndpointLost: (id) {
          if (id != null && callbackEpoch == _discoveryEpoch) {
            final name = _peerNames.remove(id) ?? id;
            final hint =
                _peerFingerprintHints.remove(id) ??
                _identityFingerprintHint(name);
            final previous = _discoveredEndpoints.remove(id);
            final now = DateTime.now().toUtc();
            _peers.add(
              NearbyPeer(
                id: id,
                name: hint == null ? name : 'RELIO ${hint.substring(0, 8)}',
                identityFingerprintHint: hint,
                isLost: true,
                discoveryEpoch: previous?.discoveryEpoch ?? callbackEpoch,
                foundAt: previous?.foundAt,
                lastSeenAt: previous?.lastSeenAt,
                lostAt: now,
                isCurrent: false,
              ),
            );
          }
        },
      );
      if (!started) {
        throw const NearbyTransportException(
          'Android startDiscovery returned false.',
          code: 'start_returned_false',
          operation: 'startDiscovery',
          exceptionType: 'bool',
          returnedFalse: true,
        );
      }
      _discovering = true;
    } on NearbyTransportException {
      rethrow;
    } on PlatformException catch (error) {
      throw _platformFailure('startDiscovery', error);
    } on Object catch (error) {
      throw NearbyTransportException(
        'Unable to start discovery: $error',
        code: _failureCode(error),
        operation: 'startDiscovery',
        exceptionType: error.runtimeType.toString(),
      );
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_discovering) return;
    _discoveryEpoch++;
    await _nearby.stopDiscovery();
    _discovering = false;
    _discoveredEndpoints.clear();
  }

  @override
  Future<void> resetSessionOperations() async {
    // หยุดเฉพาะ advertise/discovery ที่อาจค้าง; ไม่ตัด endpoint ที่เชื่อมต่อแล้ว
    _discoveryEpoch++;
    await _nearby.stopDiscovery();
    await _nearby.stopAdvertising();
    _discovering = false;
    _advertising = false;
    _discoveredEndpoints.clear();
  }

  Strategy get _strategy => switch (_testMode) {
    NearbyTransportTestMode.clusterBaseline ||
    NearbyTransportTestMode.clusterPauseDiscovery => Strategy.P2P_CLUSTER,
    NearbyTransportTestMode.pointToPointDiagnostic =>
      Strategy.P2P_POINT_TO_POINT,
  };

  @override
  Future<void> acceptConnection(
    String peerId, {
    String? connectionTraceId,
  }) async {
    if (!_pendingConnectionRequests.remove(peerId)) return;
    try {
      await _nearby.acceptConnection(
        peerId,
        onPayLoadRecieved: _payloadReceived,
        onPayloadTransferUpdate: _payloadTransferUpdated,
        connectionTraceId: connectionTraceId,
      );
    } on PlatformException catch (error) {
      throw _platformFailure('acceptConnection', error);
    } on Object catch (error) {
      throw NearbyTransportException(
        'Unable to accept Nearby connection.',
        operation: 'acceptConnection',
        exceptionType: error.runtimeType.toString(),
      );
    }
  }

  @override
  Future<void> rejectConnection(
    String peerId, {
    String? connectionTraceId,
  }) async {
    _pendingConnectionRequests.remove(peerId);
    _connectionRequests.remove(peerId);
    try {
      await _nearby.rejectConnection(
        peerId,
        connectionTraceId: connectionTraceId,
      );
    } on PlatformException catch (error) {
      throw _platformFailure('rejectConnection', error);
    } on Object catch (error) {
      throw NearbyTransportException(
        'Unable to reject Nearby connection.',
        operation: 'rejectConnection',
        exceptionType: error.runtimeType.toString(),
      );
    }
    _connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(id: peerId, name: _peerNames[peerId] ?? 'RELIO'),
        state: NearbyConnectionState.disconnected,
      ),
    );
  }

  @override
  Future<void> requestConnection(
    String peerId, {
    String? identityFingerprint,
    String? connectionTraceId,
  }) async {
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
        _endpointName('RELIO', identityFingerprint),
        peerId,
        onConnectionInitiated: _connectionInitiated,
        onConnectionResult: _connectionResult,
        onRawConnectionResult: _rawConnectionResult,
        onDisconnected: _disconnected,
        connectionTraceId: connectionTraceId,
      );
      if (!requested) {
        throw const NearbyTransportException(
          'Android connection request failed.',
          code: 'request_returned_false',
          operation: 'requestConnection',
          exceptionType: 'bool',
          returnedFalse: true,
        );
      }
    } on NearbyTransportException {
      _connectionRequests.remove(peerId);
      rethrow;
    } on PlatformException catch (error) {
      _connectionRequests.remove(peerId);
      throw _platformFailure('requestConnection', error);
    } on Object catch (error) {
      _connectionRequests.remove(peerId);
      throw NearbyTransportException(
        'Unable to request Nearby connection.',
        code: _failureCode(error),
        operation: 'requestConnection',
        exceptionType: error.runtimeType.toString(),
      );
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

  Future<void> _connectionInitiated(
    String endpointId,
    ConnectionInfo info,
  ) async {
    final callbackHint = _identityFingerprintHint(info.endpointName);
    final fingerprintHint = callbackHint ?? _peerFingerprintHints[endpointId];
    if (callbackHint != null) {
      _peerFingerprintHints[endpointId] = callbackHint;
    }
    if (callbackHint != null || !_peerNames.containsKey(endpointId)) {
      _peerNames[endpointId] = info.endpointName;
    }
    if (!_pendingConnectionRequests.add(endpointId)) return;
    _connections.add(
      NearbyConnectionEvent(
        peer: NearbyPeer(
          id: endpointId,
          name: fingerprintHint == null
              ? info.endpointName
              : 'RELIO ${fingerprintHint.substring(0, 8)}',
          identityFingerprintHint: fingerprintHint,
        ),
        state: NearbyConnectionState.incomingRequest,
        authenticationToken: info.authenticationToken,
        isIncomingRequest: info.isIncomingConnection,
      ),
    );
  }

  String? _identityFingerprintHint(String endpointName) {
    const prefix = 'RELIO-ID-V1:';
    if (!endpointName.startsWith(prefix)) return null;
    final fingerprint = endpointName.substring(prefix.length);
    return RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint) ? fingerprint : null;
  }

  String _endpointName(String displayName, String? fingerprint) {
    if (fingerprint == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      return displayName;
    }
    return 'RELIO-ID-V1:$fingerprint';
  }

  void _payloadReceived(String id, Payload payload) {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      _payloads.add(NearbyPayloadEvent(peerId: id, bytes: payload.bytes!));
    } else if (payload.type == PayloadType.FILE) {
      unawaited(_emitIncomingFile(id, payload));
    }
  }

  void _payloadTransferUpdated(String id, PayloadTransferUpdate update) {
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

  void _rawConnectionResult(String endpointId, NativeConnectionResult result) {
    _rawConnectionResults[endpointId] = result;
  }

  void _onNativeDiagnostic(NativeDiagnosticEvent event) {
    _nativeDiagnostics.add(
      NearbyNativeDiagnostic(
        name: event.name,
        fields: event.fields.map((key, value) => MapEntry('$key', value)),
      ),
    );
  }

  void _connectionResult(String endpointId, Status status) {
    final raw = _rawConnectionResults.remove(endpointId);
    _connectionRequests.remove(endpointId);
    final peer = NearbyPeer(
      id: endpointId,
      name: _identityFingerprintHint(_peerNames[endpointId] ?? '') == null
          ? _peerNames[endpointId] ?? endpointId
          : 'RELIO ${_identityFingerprintHint(_peerNames[endpointId]!)!.substring(0, 8)}',
      connected: status == Status.CONNECTED,
      identityFingerprintHint:
          _peerFingerprintHints[endpointId] ??
          _identityFingerprintHint(_peerNames[endpointId] ?? ''),
    );
    if (status == Status.CONNECTED) {
      _connectedPeers.add(endpointId);
      _connections.add(
        NearbyConnectionEvent(
          peer: peer,
          state: NearbyConnectionState.connected,
          rawStatusCode: raw?.rawStatusCode,
          rawStatusName: raw?.rawStatusName,
          rawStatusMessage: raw?.rawStatusMessage,
          operation: raw?.operation,
          role: raw?.role,
          elapsedMs: raw?.elapsedMs,
          strategy: raw?.strategy,
          connectionTraceId: raw?.connectionTraceId,
          androidApi: raw?.androidApi,
          googlePlayServicesVersionName: raw?.googlePlayServicesVersionName,
          googlePlayServicesVersionCode: raw?.googlePlayServicesVersionCode,
          nearbyLibraryVersion: raw?.nearbyLibraryVersion,
          playServicesNearbyDependencyVersion:
              raw?.playServicesNearbyDependencyVersion,
        ),
      );
    } else {
      _connections.add(
        NearbyConnectionEvent(
          peer: peer,
          state: NearbyConnectionState.failed,
          error: status.name,
          rawStatusCode: raw?.rawStatusCode,
          rawStatusName: raw?.rawStatusName,
          rawStatusMessage: raw?.rawStatusMessage,
          operation: raw?.operation,
          role: raw?.role,
          elapsedMs: raw?.elapsedMs,
          strategy: raw?.strategy,
          connectionTraceId: raw?.connectionTraceId,
          androidApi: raw?.androidApi,
          googlePlayServicesVersionName: raw?.googlePlayServicesVersionName,
          googlePlayServicesVersionCode: raw?.googlePlayServicesVersionCode,
          nearbyLibraryVersion: raw?.nearbyLibraryVersion,
          playServicesNearbyDependencyVersion:
              raw?.playServicesNearbyDependencyVersion,
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
          name: _identityFingerprintHint(_peerNames[endpointId] ?? '') == null
              ? _peerNames[endpointId] ?? endpointId
              : 'RELIO ${_identityFingerprintHint(_peerNames[endpointId]!)!.substring(0, 8)}',
          identityFingerprintHint:
              _peerFingerprintHints[endpointId] ??
              _identityFingerprintHint(_peerNames[endpointId] ?? ''),
        ),
        state: NearbyConnectionState.disconnected,
      ),
    );
  }

  String _failureCode(Object error) {
    if (error is PlatformException) {
      final status = RegExp(
        r'STATUS_[A-Z_]+',
      ).firstMatch('${error.message ?? ''} ${error.details ?? ''}');
      if (status != null) return status.group(0)!;
      final safeCode = error.code.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      return safeCode.isEmpty ? 'platform_error' : safeCode;
    }
    return 'transport_error';
  }

  NearbyTransportException _platformFailure(
    String operation,
    PlatformException error,
  ) {
    final nativeText = '${error.message ?? ''} ${error.details ?? ''}';
    final status = RegExp(
      r'(?<!\d)(\d{3,5})\s*:\s*([A-Z][A-Z0-9_]+)',
    ).firstMatch(nativeText);
    final detailsStatus = error.details is Map
        ? (error.details! as Map)['statusCode']
        : null;
    final rawDetails = error.details is Map
        ? error.details! as Map
        : const <Object?, Object?>{};
    final statusCode =
        int.tryParse('${rawDetails['rawStatusCode']}') ??
        int.tryParse(status?.group(1) ?? '') ??
        int.tryParse('$detailsStatus') ??
        int.tryParse(
          RegExp(
                r'statusCode\s*[=:]\s*(\d+)',
              ).firstMatch(nativeText)?.group(1) ??
              '',
        );
    final statusName =
        rawDetails['rawStatusName'] as String? ??
        status?.group(2) ??
        _statusName(statusCode);
    return NearbyTransportException(
      'PlatformException during $operation.',
      code: statusName ?? error.code,
      operation: operation,
      exceptionType: error.runtimeType.toString(),
      platformCode: error.code,
      platformMessage:
          rawDetails['rawStatusMessage'] as String? ?? error.message,
      platformDetails: error.details,
      apiStatusCode: statusCode,
      apiStatusName: statusName,
    );
  }

  String? _statusName(int? statusCode) => switch (statusCode) {
    8001 => 'STATUS_ALREADY_ADVERTISING',
    8002 => 'STATUS_ALREADY_DISCOVERING',
    8003 => 'STATUS_ALREADY_CONNECTED_TO_ENDPOINT',
    8007 => 'STATUS_RADIO_ERROR',
    8008 => 'STATUS_ALREADY_HAVE_ACTIVE_STRATEGY',
    8009 => 'STATUS_OUT_OF_ORDER_API_CALL',
    8029 => 'MISSING_PERMISSION_NEARBY_WIFI_DEVICES',
    8032 => 'MISSING_PERMISSION_ACCESS_WIFI_STATE',
    8033 => 'MISSING_PERMISSION_CHANGE_WIFI_STATE',
    8034 => 'MISSING_PERMISSION_ACCESS_COARSE_LOCATION',
    8036 => 'MISSING_PERMISSION_ACCESS_FINE_LOCATION',
    8050 => 'API_CONNECTION_FAILED_ALREADY_IN_USE',
    _ => null,
  };

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _discoveryEpoch++;
    await _nearby.stopAdvertising();
    await _nearby.stopDiscovery();
    await _nearby.stopAllEndpoints();
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
