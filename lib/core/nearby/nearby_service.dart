import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/environment.dart';
import '../../data/models/prototype_models.dart';
import '../domain/relio_entities.dart';
import '../diagnostics/diagnostics_log_service.dart';
import '../media/media_storage_service.dart';
import '../notifications/local_notification_service.dart';
import '../notifications/notification_preview.dart';
import '../repositories/local_repositories.dart';
import '../relay/relay_engine.dart';
import 'nearby_transport.dart';
import 'nearby_readiness.dart';
import 'peer_identity_crypto.dart';
import 'relio_packet.dart';

enum NearbyApplicationState {
  initializing,
  blocked,
  ready,
  starting,
  active,
  stopping,
  idle,
  advertising,
  discovering,
  connecting,
  verifyingIdentity,
  connected,
  disconnected,
  failed,
}

/// แยก phase ของ Native negotiation จากสถานะบนหน้าจอ เพื่อให้การเชื่อมต่อช้า
/// แสดงเป็น slow ได้โดยไม่ถูกตัดสินว่า failed
enum NearbyConnectionPhase {
  requestSubmitted,
  nativeRequestAccepted,
  nativeAcceptAccepted,
  connectionInitiated,
  awaitingApproval,
  awaitingRemoteApproval,
  nativeNegotiating,
  nativeResult,
  identityHandshake,
}

class _PendingIdentityChallenge {
  const _PendingIdentityChallenge({
    required this.challengeId,
    required this.nonce,
    required this.challengerDeviceId,
    required this.expiresAt,
  });

  final String challengeId;
  final String nonce;
  final String challengerDeviceId;
  final DateTime expiresAt;
}

class _AppDisconnectRequest {
  const _AppDisconnectRequest(this.reason, this.requestedAt);

  final String reason;
  final DateTime requestedAt;
}

class _PendingVerifiedIdentity {
  const _PendingVerifiedIdentity({
    required this.request,
    required this.packet,
    required this.publicKey,
    required this.fingerprint,
    required this.wasPinned,
    required this.pinnedMatches,
    required this.previousFingerprint,
  });

  final NearbyConnectionEvent request;
  final RelioPacket packet;
  final String publicKey;
  final String fingerprint;
  final bool wasPinned;
  final bool pinnedMatches;
  final String? previousFingerprint;
}

class NearbyService extends ChangeNotifier {
  NearbyService({
    required this.transport,
    required this.messages,
    required this.conversations,
    required this.identity,
    required this.nearbyDevices,
    this.currentUserIdProvider,
    this.sos,
    this.settings,
    this.attachments,
    this.mediaStorage,
    this.localNotifications,
    this.relayEngine,
    this.diagnostics,
    PeerIdentityCrypto? identityCrypto,
    this.handshakeTimeout = const Duration(seconds: 30),
    this.connectionAttemptTimeout = const Duration(seconds: 35),
    this.hardNegotiationTimeout = const Duration(seconds: 90),
  }) : identityCrypto =
           identityCrypto ??
           (transport is MockNearbyTransport
               ? MockPeerIdentityCrypto('mock-local-device')
               : AndroidPeerIdentityCrypto());

  final NearbyTransport transport;
  final MessageRepository messages;
  final ConversationRepository conversations;
  final RelioDeviceIdentityRepository identity;
  final NearbyDeviceRepository nearbyDevices;
  final String? Function()? currentUserIdProvider;
  final SOSRepository? sos;
  final RelioSettingsRepository? settings;
  final AttachmentRepository? attachments;
  final MediaStorageService? mediaStorage;
  final LocalNotificationSink? localNotifications;
  final RelayEngine? relayEngine;
  final DiagnosticsLogService? diagnostics;
  final PeerIdentityCrypto identityCrypto;
  final Duration handshakeTimeout;

  /// Google ระบุ callback ผลลัพธ์ แต่ไม่ได้กำหนด maximum resolution time
  /// ค่านี้จึงมีไว้กัน native attempt ค้างถาวร ไม่ใช่ UX timeout
  final Duration hardNegotiationTimeout;
  final Duration connectionAttemptTimeout;
  NearbyReadiness? readiness;
  NearbyApplicationState? _transition;
  bool _sessionFailed = false;
  String? _readinessSignature;
  String appLifecycleState = 'unknown';
  String screenRoute = 'unknown';
  Future<void>? _startSessionOperation;
  String? lastDiagnostic;
  int startRetryAttempt = 1;

  void updateReadiness(NearbyReadiness next) {
    readiness = next;
    final signature =
        '${next.policy.sdkInt}/${next.policy.tier}/${next.playServicesStatus}/'
        '${next.bluetoothEnabled}/${next.wifiEnabled}/${next.locationEnabled}/'
        '${next.missingPermissions.join(',')}/${next.blockers.map((b) => b.name).join(',')}';
    if (signature == _readinessSignature) return;
    _readinessSignature = signature;
    _log(
      'readiness sdk=${next.policy.sdkInt} tier=${next.policy.tier} '
      'ready=${next.ready} blockers=${next.blockers.map((b) => b.name).join(',')} '
      'gms=${next.playServicesStatus}',
    );
    notifyListeners();
  }

  void updateLifecycleContext({
    required String lifecycleState,
    required String route,
  }) {
    appLifecycleState = lifecycleState;
    screenRoute = route;
  }

  bool identityApprovalChangesPinnedKey(String endpointId) =>
      _pendingVerifiedIdentityApprovals[endpointId]?.wasPinned == true &&
      _pendingVerifiedIdentityApprovals[endpointId]?.pinnedMatches == false;

  String get statusLabel {
    if (readiness case final current? when !current.ready) {
      return current.summary;
    }
    if (lastErrorCode == '8033' ||
        lastErrorCode == 'MISSING_PERMISSION_CHANGE_WIFI_STATE') {
      return 'สิทธิ์ระบบ Nearby ในแอปไม่ครบ กรุณาอัปเดต RELIO';
    }
    if (lastErrorCode == '8007' || lastErrorCode == 'STATUS_RADIO_ERROR') {
      return 'วิทยุ Bluetooth/Wi-Fi ยังเริ่ม Nearby ไม่สำเร็จ';
    }
    if (peerErrors.values.contains('connection_slow') &&
        hasActiveConnectionAttempts) {
      return 'กำลังเชื่อมต่อนานกว่าปกติ…';
    }
    return switch (applicationState) {
      NearbyApplicationState.initializing => 'กำลังตรวจสอบ Nearby',
      NearbyApplicationState.starting => 'กำลังเริ่มค้นหา',
      NearbyApplicationState.stopping => 'กำลังหยุดค้นหา',
      NearbyApplicationState.active ||
      NearbyApplicationState.discovering => 'กำลังค้นหาอุปกรณ์',
      NearbyApplicationState.advertising => 'กำลังประกาศอุปกรณ์',
      NearbyApplicationState.connecting => 'กำลังเชื่อมต่อ',
      NearbyApplicationState.verifyingIdentity => 'กำลังยืนยันอุปกรณ์',
      NearbyApplicationState.connected => 'เชื่อมต่อแล้ว',
      NearbyApplicationState.failed =>
        'เริ่ม Nearby ไม่สำเร็จ กรุณาตรวจสอบสิทธิ์และลองอีกครั้ง',
      _ => 'พร้อมค้นหาอุปกรณ์ใกล้เคียง',
    };
  }

  final List<NearbyPeer> discoveredPeers = [];
  final List<String> eventLog = [];
  final Map<String, String> _packetMessageIds = {};
  final Set<String> _pendingConversationFlushes = {};
  final Set<String> _incomingTextMessagesInProgress = {};
  final Map<String, RelioPacket> _mediaMetadataByPayload = {};
  final Map<String, Future<void>> _incomingMediaOperations = {};
  final Map<String, NearbyFilePayloadEvent> _mediaFilesByPayload = {};
  final Map<String, String> _payloadTransferIds = {};
  final Map<String, String> endpointToDeviceId = {};
  final Map<String, String> deviceToEndpointId = {};
  final Map<String, NearbyConnectionState> peerStates = {};
  final Map<String, NearbyConnectionEvent> pendingConnectionRequests = {};
  final Set<String> _approvedConnectionEndpoints = {};
  final Set<String> _provisionalConnectionEndpoints = {};
  final Map<String, NearbyConnectionEvent> _provisionalIncomingRequests = {};
  final Map<String, _PendingVerifiedIdentity>
  _pendingVerifiedIdentityApprovals = {};
  final Map<String, String> _pendingIdentityApprovalReasons = {};
  final Set<String> _userInitiatedEndpoints = {};
  final Map<String, String> peerErrors = {};
  final Map<String, Timer> _identityHandshakeTimeouts = {};
  final Map<String, Timer> _connectionSoftTimeouts = {};
  final Map<String, Timer> _connectionHardWatchdogs = {};
  final Map<String, String> _connectionTraces = {};
  final Map<String, DateTime> _connectionStartedAt = {};
  final Map<String, NearbyConnectionPhase> _connectionPhases = {};
  final Map<String, DateTime> _connectionPhaseStartedAt = {};
  final Map<String, _PendingIdentityChallenge> _identityChallenges = {};
  final Set<String> _completedIdentityHandshakes = {};
  final Map<String, _AppDisconnectRequest> _appDisconnectRequests = {};
  final Set<String> _automaticConnectionAttempts = {};
  final Map<String, String> _reconnectFingerprintByEndpoint = {};
  final Map<String, String> _fingerprintEndpointReservations = {};
  final Map<String, DateTime> _nextReconnectAt = {};
  final Map<String, int> _reconnectAttemptCounts = {};
  final Map<String, DateTime> _receivedChallengeExpiries = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, DeviceStatus> peerStatuses = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<Future<void>> _inFlightOperations = {};
  bool _closed = false;
  String? lastSentPacket;
  String? lastReceivedPacket;
  String? lastError;
  String? lastErrorCode;
  bool isAdvertising = false;
  bool isDiscovering = false;
  bool initialized = false;
  int acknowledgementCount = 0;
  int protocolErrorCount = 0;
  int transportErrorCount = 0;
  String? activeConversationId;
  final Map<String, Object?> nativeTransportSnapshot = {};
  NearbyConnectionEvent? lastNativeConnectionFailure;
  bool _sessionRestartDeferred = false;

  NearbyConnectionPhase? connectionPhaseForEndpoint(String endpointId) =>
      _connectionPhases[endpointId];

  DateTime? connectionPhaseStartedAt(String endpointId) =>
      _connectionPhaseStartedAt[endpointId];

  int get activeConnectionAttempts => peerStates.entries
      .where(
        (entry) =>
            entry.value == NearbyConnectionState.connecting ||
            entry.value == NearbyConnectionState.incomingRequest,
      )
      .map((entry) => entry.key)
      .toSet()
      .union(pendingConnectionRequests.keys.toSet())
      .union(_provisionalConnectionEndpoints)
      .length;

  bool get hasActiveConnectionAttempts => activeConnectionAttempts > 0;

  bool get sessionRestartDeferred => _sessionRestartDeferred;

  void setActiveConversation(String? conversationId) {
    activeConversationId = conversationId;
  }

  // แชตที่ยังอยู่ใน navigation stack อาจถูกหน้าอื่นบัง หรือแอปอยู่เบื้องหลัง
  bool isConversationVisible(String conversationId) =>
      activeConversationId == conversationId &&
      appLifecycleState == 'resumed' &&
      screenRoute == '/chat/$conversationId';

  NearbyApplicationState get applicationState {
    if (!initialized) return NearbyApplicationState.initializing;
    if (readiness?.ready == false) return NearbyApplicationState.blocked;
    if (_sessionFailed) {
      return NearbyApplicationState.failed;
    }
    if (connectedPeers.any(
      (peer) =>
          peer.deviceId != null &&
          _completedIdentityHandshakes.contains(peer.endpointId),
    )) {
      return NearbyApplicationState.connected;
    }
    if (connectedPeers.isNotEmpty) {
      return NearbyApplicationState.verifyingIdentity;
    }
    if (_transition != null) return _transition!;
    if (peerStates.values.contains(NearbyConnectionState.connecting)) {
      return NearbyApplicationState.connecting;
    }
    if (isAdvertising && isDiscovering) return NearbyApplicationState.active;
    if (isDiscovering) return NearbyApplicationState.discovering;
    if (isAdvertising) return NearbyApplicationState.advertising;
    if (peerStates.values.contains(NearbyConnectionState.disconnected)) {
      return NearbyApplicationState.disconnected;
    }
    return NearbyApplicationState.ready;
  }

  List<NearbyPeer> get connectedPeers => discoveredPeers
      .where(
        (peer) =>
            peerStates[peer.endpointId] == NearbyConnectionState.connected,
      )
      .toList(growable: false);

  int get connectedPeerCount => connectedPeers
      .map((peer) => peer.deviceId ?? peer.endpointId)
      .toSet()
      .length;

  bool isDeviceConnected(String deviceId) => connectedPeers.any(
    (peer) => peer.deviceId == deviceId || peer.endpointId == deviceId,
  );

  String? deviceIdForEndpoint(String endpointId) =>
      endpointToDeviceId[endpointId];

  String? connectionTraceForEndpoint(String endpointId) =>
      _connectionTraces[endpointId];

  Future<void> initialize() async {
    if (initialized) return;
    initialized = true;
    _subscriptions.add(transport.discoveredPeers.listen(_onPeer));
    _subscriptions.add(transport.incomingPayloads.listen(_onPayload));
    _subscriptions.add(transport.incomingFilePayloads.listen(_onFilePayload));
    _subscriptions.add(transport.transferEvents.listen(_onTransfer));
    _subscriptions.add(transport.connectionEvents.listen(_onConnection));
    _subscriptions.add(transport.nativeDiagnostics.listen(_onNativeDiagnostic));
    _log('transport initialize name=${transport.implementationName}');
    unawaited(_captureTransportSnapshot());
    notifyListeners();
  }

  Future<void> _captureTransportSnapshot() async {
    if (!RelioBuildInfo.developerDiagnosticsEnabled) return;
    try {
      final snapshot = await transport.diagnosticSnapshot();
      nativeTransportSnapshot
        ..clear()
        ..addAll(snapshot);
      diagnostics?.record(
        'nearby',
        'nearby_strategy_snapshot',
        fields: snapshot,
      );
      diagnostics?.record(
        'nearby',
        'google_play_services_snapshot',
        fields: {
          'googlePlayServicesAvailable':
              snapshot['googlePlayServicesAvailable'],
          'googlePlayServicesVersionName':
              snapshot['googlePlayServicesVersionName'],
          'googlePlayServicesVersionCode':
              snapshot['googlePlayServicesVersionCode'],
          'androidApi': snapshot['androidApi'],
        },
      );
      notifyListeners();
    } on Object catch (error) {
      diagnostics?.record(
        'nearby',
        'nearby_strategy_snapshot_unavailable',
        severity: 'warning',
        fields: {'exceptionClass': error.runtimeType.toString()},
      );
    }
  }

  void _onNativeDiagnostic(NearbyNativeDiagnostic event) {
    final fields = Map<String, Object?>.from(event.fields);
    final endpointId = fields['endpointId'] as String?;
    if (endpointId != null) {
      if (event.name == 'native_request_connection_task_success') {
        _nativePhaseAccepted(
          endpointId,
          NearbyConnectionPhase.nativeRequestAccepted,
          operation: 'requestConnection',
        );
      } else if (event.name == 'native_accept_connection_task_success') {
        _nativePhaseAccepted(
          endpointId,
          NearbyConnectionPhase.nativeAcceptAccepted,
          operation: 'acceptConnection',
        );
      } else if (event.name == 'native_connection_resolution_received') {
        _setConnectionPhase(endpointId, NearbyConnectionPhase.nativeResult);
      }
    }
    if (!RelioBuildInfo.developerDiagnosticsEnabled) return;
    diagnostics?.record(
      'native_nearby',
      event.name,
      connectionTraceId: fields['connectionTraceId'] as String?,
      operation: fields['operation'] as String?,
      nativeCode: fields['rawStatusCode'],
      nativeMessage: fields['rawStatusMessage'] as String?,
      fields: fields,
    );
  }

  Future<void> startAdvertising() async {
    if (isAdvertising) return;
    if (hasActiveConnectionAttempts) {
      _sessionRestartDeferred = true;
      _recordDeferredSessionOperation(
        'session_restart_deferred_active_connection',
      );
      return;
    }
    try {
      _log('advertising start');
      final localIdentity = await identityCrypto.getPublicIdentity();
      diagnostics?.record(
        'trust',
        'advertising_identity_hint_generated',
        operation: 'startAdvertising',
        fields: {'fingerprintAvailable': localIdentity.fingerprint.isNotEmpty},
      );
      await transport.startAdvertising(
        displayName: await identity.getDisplayName(),
        identityFingerprint: localIdentity.fingerprint,
      );
      isAdvertising = true;
      diagnostics?.record(
        'trust',
        'advertising_started_with_trust_hint',
        operation: 'startAdvertising',
        fields: {'fingerprintAvailable': true},
      );
      _log('advertising started');
      notifyListeners();
    } on Object catch (error) {
      if (_isAlreadyActive(error, operation: 'advertising')) {
        isAdvertising = true;
        _log('advertising already active; local state reconciled');
        notifyListeners();
        return;
      }
      await _recoverOutOfOrder(error);
      _sessionFailed = true;
      transportErrorCount++;
      _recordStartFailure('startAdvertising', error);
      _fail('เริ่ม Advertising ไม่สำเร็จ', code: _errorCode(error));
    }
  }

  Future<void> startSession() {
    if (_closed || (isAdvertising && isDiscovering)) return Future.value();
    if (hasActiveConnectionAttempts) {
      _sessionRestartDeferred = true;
      _recordDeferredSessionOperation(
        'session_restart_deferred_active_connection',
      );
      return Future.value();
    }
    final current = _startSessionOperation;
    if (current != null) return current;
    final operation = _startSession();
    _startSessionOperation = operation;
    return operation.whenComplete(() {
      if (identical(_startSessionOperation, operation)) {
        _startSessionOperation = null;
      }
    });
  }

  Future<void> _startSession() async {
    _transition = NearbyApplicationState.starting;
    _sessionFailed = false;
    notifyListeners();
    await startAdvertising();
    if (isAdvertising) {
      await startDiscovery();
    } else {
      _log('discovery skipped because advertising did not start');
    }
    _transition = null;
    if (isAdvertising && isDiscovering) {
      lastError = null;
      lastErrorCode = null;
      lastDiagnostic = null;
      _sessionFailed = false;
    }
    notifyListeners();
  }

  Future<void> stopSession({
    String reason = 'session_reconcile',
    String caller = 'NearbyService.stopSession',
  }) async {
    if (_closed) return;
    _recordSessionStop(caller: caller, reason: reason);
    if (hasActiveConnectionAttempts) {
      _sessionRestartDeferred = true;
      diagnostics?.record(
        'lifecycle',
        'session_stop_deferred_active_connection',
        operation: 'stopNearbySession',
        reason: reason,
        fields: {
          'caller': caller,
          'activeConnectionAttempts': activeConnectionAttempts,
          'appLifecycleState': appLifecycleState,
          'screenRoute': screenRoute,
        },
      );
      return;
    }
    if (!isDiscovering && !isAdvertising) return;
    _transition = NearbyApplicationState.stopping;
    notifyListeners();
    await stopDiscovery();
    await stopAdvertising();
    _transition = null;
    notifyListeners();
  }

  void _recordDeferredSessionOperation(String event) {
    diagnostics?.record(
      'lifecycle',
      event,
      operation: 'startNearbySession',
      fields: {
        'activeConnectionAttempts': activeConnectionAttempts,
        'appLifecycleState': appLifecycleState,
        'screenRoute': screenRoute,
      },
    );
  }

  void _recordSessionStop({required String caller, required String reason}) {
    diagnostics?.record(
      'lifecycle',
      'nearby_session_stop_requested',
      operation: 'stopNearbySession',
      reason: reason,
      fields: {
        'caller': caller,
        'activeConnections': connectedPeerCount,
        'activeHandshakes': _identityHandshakeTimeouts.length,
        'appLifecycleState': appLifecycleState,
        'screenRoute': screenRoute,
        'discoveryActive': isDiscovering,
        'advertisingActive': isAdvertising,
      },
    );
  }

  Future<void> stopAdvertising() async {
    if (!isAdvertising) return;
    try {
      await transport.stopAdvertising();
      isAdvertising = false;
      _log('advertising stopped');
      notifyListeners();
    } on Object catch (error) {
      _fail('หยุด Advertising ไม่สำเร็จ: $error', code: _errorCode(error));
    }
  }

  Future<void> startDiscovery() async {
    if (isDiscovering) return;
    if (hasActiveConnectionAttempts) {
      _sessionRestartDeferred = true;
      _recordDeferredSessionOperation(
        'session_restart_deferred_active_connection',
      );
      return;
    }
    try {
      _log('discovery start');
      await transport.startDiscovery();
      isDiscovering = true;
      _log('discovery started');
      notifyListeners();
    } on Object catch (error) {
      if (_isAlreadyActive(error, operation: 'discovery')) {
        isDiscovering = true;
        _log('discovery already active; local state reconciled');
        notifyListeners();
        return;
      }
      await _recoverOutOfOrder(error);
      _sessionFailed = true;
      transportErrorCount++;
      _recordStartFailure('startDiscovery', error);
      _fail('เริ่ม Discovery ไม่สำเร็จ', code: _errorCode(error));
    }
  }

  bool _isAlreadyActive(Object error, {required String operation}) {
    if (error is! NearbyTransportException) return false;
    final status = error.apiStatusCode ?? int.tryParse(error.code);
    final name = error.apiStatusName ?? error.code;
    return operation == 'advertising'
        ? status == 8001 || name.contains('ALREADY_ADVERTISING')
        : status == 8002 || name.contains('ALREADY_DISCOVERING');
  }

  Future<void> _recoverOutOfOrder(Object error) async {
    if (error is! NearbyTransportException) return;
    final status = error.apiStatusCode ?? int.tryParse(error.code);
    final name = error.apiStatusName ?? error.code;
    if (status != 8009 && !name.contains('OUT_OF_ORDER')) return;
    if (hasActiveConnectionAttempts) {
      _sessionRestartDeferred = true;
      _recordDeferredSessionOperation(
        'session_restart_deferred_active_connection',
      );
      return;
    }
    try {
      await transport.resetSessionOperations();
      isAdvertising = false;
      isDiscovering = false;
      _log(
        'out-of-order start; advertising/discovery stopped for backoff retry',
      );
    } on Object catch (recoveryError) {
      _log('out-of-order recovery failed: ${_diagnosticError(recoveryError)}');
    }
  }

  void _recordStartFailure(String operation, Object error) {
    final current = readiness;
    final native = _diagnosticError(error);
    final snapshot = current == null
        ? 'unknown'
        : 'sdk=${current.policy.sdkInt} model=${_deviceModel ?? 'unknown'} '
              'tier=${current.policy.tier} ready=${current.ready} '
              'blockers=${current.blockers.map((item) => item.name).join(',')} '
              'missingRuntime=${current.missingPermissions.join(',')} '
              'missingManifest=${current.missingManifestPermissions.join(',')} '
              'bluetooth=${current.bluetoothEnabled} wifi=${current.wifiEnabled} '
              'location=${current.locationEnabled} gms=${current.playServicesStatus}';
    lastDiagnostic =
        'operation=$operation api=${current?.policy.sdkInt ?? 'unknown'} '
        'model=${_deviceModel ?? 'unknown'} serviceId=$relioNearbyServiceId '
        'strategy=$relioNearbyStrategyName readiness={$snapshot} '
        'advertisingActive=$isAdvertising discoveryActive=$isDiscovering '
        'retryAttempt=$startRetryAttempt $native';
    _log('START_FAILURE $lastDiagnostic');
  }

  String? get _deviceModel => _runtimeDeviceModel;

  String? _runtimeDeviceModel;

  void updateDeviceModel(String? model) {
    if (model == null || model.isEmpty) return;
    _runtimeDeviceModel = model;
  }

  String _diagnosticError(Object error) => error is NearbyTransportException
      ? error.toString()
      : 'exceptionType=${error.runtimeType} message=$error';

  void logRetryScheduled(int attempt, Duration delay) {
    _log('retry scheduled attempt=$attempt delayMs=${delay.inMilliseconds}');
  }

  Future<void> stopDiscovery() async {
    if (!isDiscovering) return;
    try {
      await transport.stopDiscovery();
      isDiscovering = false;
      _log('หยุด Discovery แล้ว');
      notifyListeners();
    } on Object catch (error) {
      _fail('หยุด Discovery ไม่สำเร็จ: $error', code: _errorCode(error));
    }
  }

  Future<void> connect(String peerId) async {
    await _connect(peerId, userInitiated: true);
  }

  Future<void> _connect(String peerId, {required bool userInitiated}) async {
    final currentState = peerStates[peerId];
    if (currentState == NearbyConnectionState.connected ||
        currentState == NearbyConnectionState.connecting ||
        currentState == NearbyConnectionState.incomingRequest ||
        pendingConnectionRequests.containsKey(peerId)) {
      diagnostics?.record(
        'connection',
        'connect_suppressed',
        peerIdentifier: peerId,
        reason: 'already_${currentState?.name ?? 'active'}',
        fields: {'initiator': userInitiated ? 'manual' : 'automatic'},
      );
      _fingerprintEndpointReservations.removeWhere(
        (_, endpoint) =>
            endpoint == peerId &&
            currentState == NearbyConnectionState.connected,
      );
      return;
    }
    final candidateFingerprint = discoveredPeers
        .where((peer) => peer.endpointId == peerId)
        .firstOrNull
        ?.identityFingerprintHint;
    final reservedEndpoint = candidateFingerprint == null
        ? null
        : _fingerprintEndpointReservations[candidateFingerprint];
    if (reservedEndpoint != null &&
        reservedEndpoint != peerId &&
        (peerStates[reservedEndpoint] == NearbyConnectionState.connecting ||
            peerStates[reservedEndpoint] ==
                NearbyConnectionState.incomingRequest ||
            peerStates[reservedEndpoint] == NearbyConnectionState.connected)) {
      diagnostics?.record(
        'connection',
        'connection_attempt_suppressed_single_flight',
        peerIdentifier: peerId,
        reason: 'same_stable_peer_already_active',
        fields: {
          'reservedPeerAlias': DiagnosticsLogService.peerAlias(
            reservedEndpoint,
          ),
          'initiator': userInitiated ? 'manual' : 'automatic',
        },
      );
      return;
    }
    final previousState = currentState?.name ?? 'discovered';
    final traceId = const Uuid().v4();
    _connectionTraces[peerId] = traceId;
    _connectionStartedAt[peerId] = DateTime.now().toUtc();
    _setConnectionPhase(peerId, NearbyConnectionPhase.requestSubmitted);
    diagnostics?.record(
      'connection',
      userInitiated ? 'manual_connect_tap' : 'auto_reconnect_initiated',
      connectionTraceId: traceId,
      operation: 'requestConnection',
      stateFrom: previousState,
      stateTo: 'connecting',
      peerIdentifier: peerId,
      sdk: readiness?.policy.sdkInt,
      fields: {
        'trustHintAvailable': discoveredPeers.any(
          (p) => p.endpointId == peerId && p.identityFingerprintHint != null,
        ),
        'bluetoothEnabled': readiness?.bluetoothEnabled,
        'wifiEnabled': readiness?.wifiEnabled,
        'locationEnabled': readiness?.locationEnabled,
        'nearbyReady': readiness?.ready,
        'missingPermissionCount': readiness?.missingPermissions.length,
      },
    );
    diagnostics?.record(
      'connection',
      'connection_negotiation_started',
      connectionTraceId: traceId,
      operation: 'requestConnection',
      stateFrom: previousState,
      stateTo: 'connecting',
      peerIdentifier: peerId,
    );
    peerStates[peerId] = NearbyConnectionState.connecting;
    if (candidateFingerprint != null) {
      _fingerprintEndpointReservations[candidateFingerprint] = peerId;
    }
    if (userInitiated) _userInitiatedEndpoints.add(peerId);
    unawaited(_recordCandidateTrust(peerId, traceId));
    _startConnectionSoftTimeout(peerId);
    notifyListeners();
    try {
      final localIdentity = await identityCrypto.getPublicIdentity();
      diagnostics?.record(
        'trust',
        localIdentity.fingerprint.isEmpty
            ? 'advertising_identity_hint_missing'
            : 'connection_request_identity_hint_generated',
        connectionTraceId: traceId,
        operation: 'requestConnection',
        peerIdentifier: peerId,
        fields: {'fingerprintAvailable': localIdentity.fingerprint.isNotEmpty},
      );
      await transport.requestConnection(
        peerId,
        identityFingerprint: localIdentity.fingerprint,
        connectionTraceId: traceId,
      );
      diagnostics?.record(
        'connection',
        'request_connection_returned',
        connectionTraceId: traceId,
        operation: 'requestConnection',
        peerIdentifier: peerId,
      );
      _nativePhaseAccepted(
        peerId,
        NearbyConnectionPhase.nativeRequestAccepted,
        operation: 'requestConnection',
      );
      _log('ส่งคำขอเชื่อมต่อไปยัง ${DiagnosticsLogService.peerAlias(peerId)}');
    } on Object catch (error) {
      _cancelConnectionTimers(peerId);
      _connectionPhases[peerId] = NearbyConnectionPhase.nativeResult;
      peerStates[peerId] = NearbyConnectionState.failed;
      _fingerprintEndpointReservations.removeWhere(
        (_, endpoint) => endpoint == peerId,
      );
      peerErrors[peerId] = _safeError(error);
      diagnostics?.record(
        'connection',
        'request_connection_exception',
        severity: 'error',
        connectionTraceId: traceId,
        operation: 'requestConnection',
        stateFrom: 'connecting',
        stateTo: 'failed',
        peerIdentifier: peerId,
        nativeCode: _errorCode(error),
        nativeMessage: error is NearbyTransportException
            ? error.platformMessage ?? error.message
            : error.runtimeType.toString(),
        detailsSummary: error is NearbyTransportException
            ? _safeNativeDetails(error.platformDetails)
            : null,
      );
      _fail('เชื่อมต่อไม่สำเร็จ: $error', code: _errorCode(error));
    }
  }

  void _setConnectionPhase(
    String endpointId,
    NearbyConnectionPhase phase, {
    bool notify = false,
  }) {
    _connectionPhases[endpointId] = phase;
    _connectionPhaseStartedAt[endpointId] = DateTime.now().toUtc();
    diagnostics?.record(
      'connection',
      'connection_phase_changed',
      connectionTraceId: _connectionTraces[endpointId],
      operation: phase.name,
      peerIdentifier: endpointId,
      fields: {
        'phase': phase.name,
        'phaseStartedAt': _connectionPhaseStartedAt[endpointId]!
            .toIso8601String(),
      },
    );
    if (notify) notifyListeners();
  }

  void _startConnectionSoftTimeout(String endpointId) {
    _connectionSoftTimeouts.remove(endpointId)?.cancel();
    _connectionSoftTimeouts[endpointId] = Timer(connectionAttemptTimeout, () {
      if (peerStates[endpointId] != NearbyConnectionState.connecting) return;
      peerErrors[endpointId] = 'connection_slow';
      diagnostics?.record(
        'connection',
        'connection_soft_timeout',
        severity: 'warning',
        connectionTraceId: _connectionTraces[endpointId],
        operation: 'connectionNegotiation',
        peerIdentifier: endpointId,
        reason: 'RELIO_APPLICATION_SOFT_TIMEOUT',
        fields: {
          'timeoutMs': connectionAttemptTimeout.inMilliseconds,
          'phase': _connectionPhases[endpointId]?.name,
          'disconnectRequested': false,
        },
      );
      // รอผลจาก Google Nearby ต่อ ไม่ตัดการเชื่อมต่อทันทีเมื่อครบ soft timeout
      notifyListeners();
    });
  }

  void _startHardNegotiationWatchdog(String endpointId) {
    _connectionHardWatchdogs.remove(endpointId)?.cancel();
    _connectionHardWatchdogs[endpointId] = Timer(
      hardNegotiationTimeout,
      () => unawaited(_expireConnectionAttempt(endpointId)),
    );
  }

  void _nativePhaseAccepted(
    String endpointId,
    NearbyConnectionPhase phase, {
    required String operation,
  }) {
    if (peerStates[endpointId] != NearbyConnectionState.connecting) return;
    _setConnectionPhase(endpointId, phase);
    _setConnectionPhase(endpointId, NearbyConnectionPhase.nativeNegotiating);
    _startHardNegotiationWatchdog(endpointId);
    diagnostics?.record(
      'connection',
      'native_${operation}_accepted',
      connectionTraceId: _connectionTraces[endpointId],
      operation: operation,
      peerIdentifier: endpointId,
      fields: {'hardWatchdogMs': hardNegotiationTimeout.inMilliseconds},
    );
  }

  void _cancelConnectionTimers(String endpointId) {
    _connectionSoftTimeouts.remove(endpointId)?.cancel();
    _connectionHardWatchdogs.remove(endpointId)?.cancel();
  }

  Future<void> _recordCandidateTrust(String endpointId, String traceId) async {
    try {
      final peer = discoveredPeers
          .where((candidate) => candidate.endpointId == endpointId)
          .firstOrNull;
      final fingerprint = peer?.identityFingerprintHint;
      final candidates = await nearbyDevices.listDevices();
      final matches = fingerprint == null
          ? const <RelioNearbyDevice>[]
          : candidates
                .where((item) => item.publicIdentityFingerprint == fingerprint)
                .toList(growable: false);
      final saved = matches.length == 1 ? matches.single : null;
      diagnostics?.record(
        'trust',
        'manual_peer_trust_lookup',
        connectionTraceId: traceId,
        operation: 'nearbyDevices.lookup',
        peerIdentifier: endpointId,
        reason: saved?.isBlocked == true
            ? 'blocked'
            : saved?.isTrusted != true
            ? 'untrusted'
            : saved?.publicIdentityKey == null ||
                  saved?.publicIdentityFingerprint == null
            ? 'incomplete_legacy_trust'
            : 'trusted_identity_pinned',
        fields: {
          'trusted': saved?.isTrusted ?? false,
          'blocked': saved?.isBlocked ?? false,
          'publicKeyAvailable': saved?.publicIdentityKey != null,
          'fingerprintAvailable': fingerprint != null,
        },
      );
    } on Object {
      diagnostics?.record(
        'trust',
        'manual_peer_trust_lookup_failed',
        severity: 'warning',
        connectionTraceId: traceId,
        operation: 'nearbyDevices.lookup',
        peerIdentifier: endpointId,
      );
    }
  }

  Future<void> _expireConnectionAttempt(String endpointId) async {
    if (peerStates[endpointId] != NearbyConnectionState.connecting) return;
    final traceId = _connectionTraces[endpointId];
    final softTimeoutElapsed = peerErrors[endpointId] == 'connection_slow';
    final operation = _approvedConnectionEndpoints.contains(endpointId)
        ? 'acceptConnection'
        : 'requestConnection';
    _cancelConnectionTimers(endpointId);
    _userInitiatedEndpoints.remove(endpointId);
    _approvedConnectionEndpoints.remove(endpointId);
    peerErrors[endpointId] = 'connection_hard_timeout';
    _setConnectionPhase(endpointId, NearbyConnectionPhase.nativeResult);
    diagnostics?.record(
      'connection',
      'RELIO_HARD_NEGOTIATION_TIMEOUT',
      severity: 'error',
      connectionTraceId: traceId,
      operation: operation,
      stateFrom: 'negotiating',
      stateTo: 'failed',
      peerIdentifier: endpointId,
      reason: 'RELIO_HARD_NEGOTIATION_TIMEOUT',
      fields: {
        'hardWatchdogMs': hardNegotiationTimeout.inMilliseconds,
        'phase': _connectionPhases[endpointId]?.name,
        'softTimeoutElapsed': softTimeoutElapsed,
      },
    );
    try {
      // Hard watchdog เป็น timeout เดียวที่ยกเลิก Native negotiation ได้
      // ส่วน soft timeout มีหน้าที่แจ้งผู้ใช้เท่านั้น
      await disconnect(endpointId, reason: 'hard_negotiation_timeout');
    } on Object {
      // Timeout cleanup is best effort; local transient state still expires.
    }
    if (_closed) return;
    peerStates[endpointId] = NearbyConnectionState.failed;
    diagnostics?.record(
      'connection',
      'connection_negotiation_timeout',
      severity: 'error',
      connectionTraceId: traceId,
      operation: operation,
      stateFrom: 'connecting',
      stateTo: 'failed',
      peerIdentifier: endpointId,
      reason: 'RELIO_HARD_NEGOTIATION_TIMEOUT',
      fields: {
        'failureSource': 'RELIO_HARD_NEGOTIATION_TIMEOUT',
        'timeoutMs': hardNegotiationTimeout.inMilliseconds,
        'appLifecycleState': appLifecycleState,
      },
    );
    notifyListeners();
  }

  void expireActiveConnectionAttemptsForBackground() {
    final endpoints = peerStates.entries
        .where(
          (entry) =>
              entry.value == NearbyConnectionState.connecting ||
              entry.value == NearbyConnectionState.incomingRequest,
        )
        .map((entry) => entry.key)
        .toSet()
        .union(pendingConnectionRequests.keys.toSet())
        .union(_provisionalConnectionEndpoints);
    for (final endpointId in endpoints) {
      diagnostics?.record(
        'lifecycle',
        'nearby_negotiation_kept_alive_in_background',
        connectionTraceId: _connectionTraces[endpointId],
        operation: 'setNearbyForeground',
        peerIdentifier: endpointId,
        fields: {'phase': _connectionPhases[endpointId]?.name},
      );
    }
    notifyListeners();
  }

  Future<void> acceptConnectionRequest(String endpointId) async {
    final pendingIdentity = _pendingVerifiedIdentityApprovals.remove(
      endpointId,
    );
    if (pendingIdentity != null) {
      pendingConnectionRequests.remove(endpointId);
      _pendingIdentityApprovalReasons.remove(endpointId);
      _approvedConnectionEndpoints.add(endpointId);
      _recordIdentityStage(
        endpointId,
        'identity_approval_accepted',
        fields: {
          'identityChanged':
              pendingIdentity.wasPinned && !pendingIdentity.pinnedMatches,
        },
      );
      await _finalizeVerifiedIdentity(endpointId, pendingIdentity);
      notifyListeners();
      return;
    }
    final isAutomaticTrustedReconnect =
        !pendingConnectionRequests.containsKey(endpointId) &&
        _approvedConnectionEndpoints.contains(endpointId);
    if (!pendingConnectionRequests.containsKey(endpointId) &&
        !isAutomaticTrustedReconnect) {
      return;
    }
    diagnostics?.record(
      'connection',
      isAutomaticTrustedReconnect
          ? 'trusted_reconnect_accepted'
          : 'accept_tapped',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'acceptConnection',
      peerIdentifier: endpointId,
      fields: {'automaticTrustedReconnect': isAutomaticTrustedReconnect},
    );
    _approvedConnectionEndpoints.add(endpointId);
    pendingConnectionRequests.remove(endpointId);
    peerStates[endpointId] = NearbyConnectionState.connecting;
    _setConnectionPhase(
      endpointId,
      NearbyConnectionPhase.awaitingRemoteApproval,
    );
    _connectionSoftTimeouts.remove(endpointId)?.cancel();
    _connectionStartedAt.putIfAbsent(endpointId, DateTime.now().toUtc);
    _startConnectionSoftTimeout(endpointId);
    notifyListeners();
    try {
      await transport.acceptConnection(
        endpointId,
        connectionTraceId: _connectionTraces[endpointId],
      );
      diagnostics?.record(
        'connection',
        'accept_connection_returned',
        connectionTraceId: _connectionTraces[endpointId],
        operation: 'acceptConnection',
        peerIdentifier: endpointId,
      );
      _nativePhaseAccepted(
        endpointId,
        NearbyConnectionPhase.nativeAcceptAccepted,
        operation: 'acceptConnection',
      );
    } on Object catch (error) {
      _approvedConnectionEndpoints.remove(endpointId);
      _cancelConnectionTimers(endpointId);
      _setConnectionPhase(endpointId, NearbyConnectionPhase.nativeResult);
      peerStates[endpointId] = NearbyConnectionState.failed;
      diagnostics?.record(
        'connection',
        'accept_connection_exception',
        severity: 'error',
        connectionTraceId: _connectionTraces[endpointId],
        operation: 'acceptConnection',
        peerIdentifier: endpointId,
        nativeCode: _errorCode(error),
        nativeMessage: error is NearbyTransportException
            ? error.platformMessage ?? error.message
            : error.runtimeType.toString(),
      );
      _fail('ยอมรับคำขอไม่สำเร็จ: $error', code: _errorCode(error));
    }
  }

  Future<void> rejectConnectionRequest(String endpointId) async {
    _connectionSoftTimeouts.remove(endpointId)?.cancel();
    diagnostics?.record(
      'connection',
      'reject_tapped',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'rejectConnection',
      peerIdentifier: endpointId,
    );
    final wasIdentityApproval =
        _pendingVerifiedIdentityApprovals.remove(endpointId) != null;
    _pendingIdentityApprovalReasons.remove(endpointId);
    _provisionalIncomingRequests.remove(endpointId);
    _provisionalConnectionEndpoints.remove(endpointId);
    pendingConnectionRequests.remove(endpointId);
    if (wasIdentityApproval ||
        peerStates[endpointId] == NearbyConnectionState.connected) {
      await disconnect(endpointId, reason: 'identity_approval_rejected');
    } else {
      peerStates[endpointId] = NearbyConnectionState.disconnected;
    }
    notifyListeners();
    if (wasIdentityApproval) return;
    try {
      await transport.rejectConnection(
        endpointId,
        connectionTraceId: _connectionTraces[endpointId],
      );
      diagnostics?.record(
        'connection',
        'reject_connection_returned',
        connectionTraceId: _connectionTraces[endpointId],
        operation: 'rejectConnection',
        peerIdentifier: endpointId,
      );
    } on Object catch (error) {
      _fail('ปฏิเสธคำขอไม่สำเร็จ: $error', code: _errorCode(error));
    }
  }

  Future<void> disconnect(
    String peerId, {
    String reason = 'user_requested',
  }) async {
    final cancellingNegotiation =
        hasActiveConnectionAttempts &&
        peerStates[peerId] == NearbyConnectionState.connecting;
    if (cancellingNegotiation &&
        (reason == 'user_requested' || reason == 'user_cancelled_connection')) {
      _cancelConnectionTimers(peerId);
      _setConnectionPhase(peerId, NearbyConnectionPhase.nativeResult);
      diagnostics?.record(
        'connection',
        'USER_CANCELLED_CONNECTION',
        connectionTraceId: _connectionTraces[peerId],
        operation: 'disconnect',
        peerIdentifier: peerId,
        reason: 'USER_CANCELLED_CONNECTION',
      );
    }
    _appDisconnectRequests[peerId] = _AppDisconnectRequest(
      reason,
      DateTime.now().toUtc(),
    );
    _recordIdentityStage(
      peerId,
      'disconnect_requested_by_app',
      reason: reason,
      fields: {'disconnectReason': reason},
    );
    _recordIdentityStage(
      peerId,
      'disconnect_requested_reason',
      reason: reason,
      fields: {'disconnectReason': reason},
    );
    try {
      await transport.disconnect(peerId);
      peerStates[peerId] = NearbyConnectionState.disconnected;
      _log('ตัดการเชื่อมต่อ $peerId');
    } on Object catch (error) {
      _appDisconnectRequests.remove(peerId);
      _recordIdentityStage(
        peerId,
        'disconnect_request_failed',
        severity: 'error',
        reason: reason,
        nativeCode: _errorCode(error),
      );
      _fail('ตัดการเชื่อมต่อไม่สำเร็จ: $error', code: _errorCode(error));
    }
  }

  Future<void> cancelConnection(String peerId) =>
      disconnect(peerId, reason: 'user_cancelled_connection');

  Future<DeviceStatus> currentStatus() async {
    final deviceId = await identity.getDeviceId();
    if (sos != null && await sos!.readActive(ownerDeviceId: deviceId) != null) {
      return DeviceStatus.sos;
    }
    if (settings != null &&
        await settings!.getBool('rescue_mode', defaultValue: false)) {
      return DeviceStatus.rescue;
    }
    return DeviceStatus.normal;
  }

  Future<void> sendHello({String? peerId}) async {
    final packet = RelioPacket.hello(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: await _senderUserId(),
      displayName: await identity.getDisplayName(),
      status: await currentStatus(),
    );
    await _sendPacket(packet, description: 'Hello RELIO', peerId: peerId);
  }

  Future<void> propagateCurrentStatus() async {
    final deviceId = await identity.getDeviceId();
    final status = await currentStatus();
    await _sendPacket(
      RelioPacket.deviceStatus(
        senderDeviceId: deviceId,
        senderUserId: await _senderUserId(),
        displayName: await identity.getDisplayName(),
        status: status,
      ),
      description: 'deviceStatus ${status.name}',
    );
    final active = await sos?.readActive(ownerDeviceId: deviceId);
    if (active != null) await sendSos(active);
  }

  Future<void> sendSos(RelioSosEvent event, {String? peerId}) async {
    final deviceId = await identity.getDeviceId();
    await _sendPacket(
      RelioPacket.sos(
        senderDeviceId: deviceId,
        senderUserId: event.ownerUserId.isNotEmpty
            ? event.ownerUserId
            : deviceId,
        displayName: await identity.getDisplayName(),
        sosId: event.id,
        message: event.message,
        latitude: event.latitude,
        longitude: event.longitude,
        accuracyMeters: event.locationAccuracy,
        locationCapturedAt: event.locationCapturedAt,
        createdAt: event.createdAt,
        isActive: event.isActive,
      ),
      description: 'SOS ${event.id}',
      peerId: peerId,
    );
  }

  Future<void> sendTestText() async {
    await _sendPacket(
      RelioPacket.textMessage(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: await _senderUserId(),
        messageId: const Uuid().v4(),
        conversationId: 'diagnostics',
        text: 'Hello RELIO',
        timestamp: DateTime.now(),
      ),
      description: 'test text',
      allowEmptyMock: true,
    );
  }

  Future<void> sendTestSos() async {
    await _sendPacket(
      RelioPacket.sos(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: await _senderUserId(),
        displayName: await identity.getDisplayName(),
        sosId: const Uuid().v4(),
        message: 'TEST SOS จาก diagnostics',
        latitude: 13.7563,
        longitude: 100.5018,
        createdAt: DateTime.now(),
        isActive: true,
      ),
      description: 'test SOS',
      allowEmptyMock: true,
    );
  }

  Future<void> sendTestRescue() async {
    await _sendPacket(
      RelioPacket.deviceStatus(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: await _senderUserId(),
        displayName: await identity.getDisplayName(),
        status: DeviceStatus.rescue,
      ),
      description: 'test Rescue status',
      allowEmptyMock: true,
    );
  }

  Future<void> sendMessage(RelioMessage message) async {
    final packet = RelioPacket.textMessage(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: message.senderId ?? await _senderUserId(),
      messageId: message.id,
      conversationId: message.conversationId ?? 'somchai',
      text: message.text,
      timestamp: message.createdAt ?? DateTime.now(),
    );
    _packetMessageIds[packet.packetId] = message.id;
    final peerId = await _endpointForMessage(message);
    if (peerId == null && transport is! MockNearbyTransport) {
      lastError = 'ยังไม่พบการเชื่อมต่อของผู้รับข้อความ';
      _log('เก็บข้อความ ${message.id} ไว้ pending: peer ยังไม่ connected');
      notifyListeners();
      return;
    }
    try {
      await transport.sendBytes(packet.toBytes(), peerId: peerId);
      await messages.updateDeliveryStatus(
        message.id,
        DeliveryStatus.nearbySent,
      );
      lastSentPacket = _diagnosticPacket(packet);
      _log('ส่ง textMessage ${message.id} แล้ว');
      notifyListeners();
      if (transport is MockNearbyTransport &&
          (transport as MockNearbyTransport).autoAcknowledge) {
        final ack = RelioPacket.ack(
          senderDeviceId: await identity.getDeviceId(),
          senderUserId: 'mock-peer',
          acknowledgedPacketId: packet.packetId,
          messageId: message.id,
        );
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          (transport as MockNearbyTransport).simulateIncoming(
            peerId: peerId ?? 'mock-peer',
            bytes: ack.toBytes(),
          );
        });
      }
    } on Object catch (error) {
      await messages.markFailed(message.id, '$error');
      _fail('ส่งข้อความไม่สำเร็จ: $error');
    }
  }

  Future<void> sendLocationMessage(RelioMessage message) async {
    if (message.latitude == null || message.longitude == null) {
      await messages.markFailed(message.id, 'location_unavailable');
      return;
    }
    final peerId = await _endpointForMessage(message);
    if (peerId == null && transport is! MockNearbyTransport) return;
    final packet = RelioPacket.locationMessage(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: message.senderId ?? await _senderUserId(),
      messageId: message.id,
      conversationId: message.conversationId ?? 'unknown',
      latitude: message.latitude!,
      longitude: message.longitude!,
      capturedAt: message.createdAt ?? DateTime.now(),
    );
    _packetMessageIds[packet.packetId] = message.id;
    try {
      await transport.sendBytes(packet.toBytes(), peerId: peerId);
      await messages.updateDeliveryStatus(
        message.id,
        DeliveryStatus.nearbySent,
      );
      lastSentPacket = _diagnosticPacket(packet);
      _log('ส่ง locationMessage ${message.id} แล้ว');
      if (transport is MockNearbyTransport &&
          (transport as MockNearbyTransport).autoAcknowledge) {
        final ack = RelioPacket.ack(
          senderDeviceId: await identity.getDeviceId(),
          senderUserId: 'mock-peer',
          acknowledgedPacketId: packet.packetId,
          messageId: message.id,
        );
        Future<void>.delayed(const Duration(milliseconds: 80), () {
          (transport as MockNearbyTransport).simulateIncoming(
            peerId: peerId ?? 'mock-peer',
            bytes: ack.toBytes(),
          );
        });
      }
    } on Object catch (error) {
      await messages.markFailed(message.id, '$error');
      _fail('ส่งตำแหน่งไม่สำเร็จ: $error');
    }
  }

  Future<void> sendMediaMessage(
    RelioMessage message,
    RelioMediaAttachment attachment,
  ) async {
    if (attachments == null || mediaStorage == null) return;
    final peerId = await _endpointForMessage(message);
    if (peerId == null && transport is! MockNearbyTransport) {
      _recordMediaStage(null, 'media_queued_offline');
      return;
    }
    try {
      _recordMediaStage(
        peerId,
        'media_send_started',
        fields: {
          'mediaType': attachment.mediaType.name,
          'sizeBytes': attachment.byteSize,
        },
      );
      final digest = await mediaStorage!.sha256ForFile(attachment.localPath);
      final payloadId = await transport.sendFile(
        attachment.localPath,
        peerId: peerId,
      );
      _payloadTransferIds[payloadId] = attachment.transferId;
      final packet = RelioPacket.mediaMetadata(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: message.senderId ?? await _senderUserId(),
        messageId: message.id,
        attachmentId: attachment.id,
        transferId: attachment.transferId,
        mediaType: attachment.mediaType.name,
        fileName: attachment.fileName,
        mimeType: attachment.mimeType,
        byteSize: attachment.byteSize,
        payloadId: payloadId,
        sha256: digest,
      );
      await transport.sendBytes(packet.toBytes(), peerId: peerId);
      _recordMediaStage(peerId, 'media_metadata_sent');
      await attachments!.updateProgress(
        attachment.id,
        status: MediaTransferState.transferring,
        bytesTransferred: 0,
      );
      await messages.updateDeliveryStatus(
        message.id,
        DeliveryStatus.nearbySent,
      );
      lastSentPacket = _diagnosticPacket(packet);
      _log('ส่ง mediaMetadata ${attachment.transferId} แล้ว');
      if (transport is MockNearbyTransport &&
          (transport as MockNearbyTransport).autoAcknowledge) {
        final ack = RelioPacket.mediaAck(
          senderDeviceId: await identity.getDeviceId(),
          senderUserId: 'mock-peer',
          messageId: message.id,
          attachmentId: attachment.id,
          transferId: attachment.transferId,
          status: 'completed',
        );
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          (transport as MockNearbyTransport).simulateIncoming(
            peerId: peerId ?? 'mock-peer',
            bytes: ack.toBytes(),
          );
        });
      }
    } on Object catch (error) {
      _recordMediaStage(
        peerId,
        'media_send_failed',
        severity: 'error',
        reason: 'transport_or_metadata_send_failed',
        nativeCode: _errorCode(error),
      );
      await attachments!.markFailed(attachment.id, 'send_failed');
      await messages.markFailed(message.id, '$error');
      _fail('ส่งสื่อไม่สำเร็จ: $error');
    }
  }

  Future<void> retryMessage(String messageId) async {
    final message = await messages.getMessage(messageId);
    if (message == null) return;
    await messages.updateDeliveryStatus(messageId, DeliveryStatus.pending);
    await _sendPendingMessage(message);
  }

  Future<String?> _endpointForMessage(RelioMessage message) async {
    final conversationId = message.conversationId;
    if (conversationId == null) return null;
    final conversation = await conversations.getConversation(conversationId);
    final deviceId = conversation?.participantId ?? conversationId;
    final exact = deviceToEndpointId[deviceId];
    if (exact != null) return exact;
    for (final peer in connectedPeers) {
      if (peer.endpointId == deviceId ||
          peer.name == conversation?.displayName) {
        return peer.endpointId;
      }
    }
    if (transport is MockNearbyTransport && connectedPeers.length == 1) {
      return connectedPeers.single.endpointId;
    }
    return null;
  }

  Future<void> _sendPacket(
    RelioPacket packet, {
    required String description,
    String? peerId,
    bool allowEmptyMock = false,
  }) async {
    try {
      if (peerId == null &&
          transport is! MockNearbyTransport &&
          connectedPeers.isEmpty) {
        throw const NearbyTransportException('No connected Nearby peer.');
      }
      if (peerId == null &&
          transport is MockNearbyTransport &&
          !allowEmptyMock &&
          packet.type != RelioPacketType.hello &&
          connectedPeers.isEmpty) {
        throw const NearbyTransportException('No connected mock peer.');
      }
      await transport.sendBytes(packet.toBytes(), peerId: peerId);
      lastSentPacket = _diagnosticPacket(packet);
      _log('ส่ง $description แล้ว');
      notifyListeners();
    } on Object catch (error) {
      _fail('ส่ง packet ไม่สำเร็จ: $error');
    }
  }

  void clearLog() {
    eventLog.clear();
    lastError = null;
    lastErrorCode = null;
    notifyListeners();
  }

  void _onPeer(NearbyPeer peer) {
    if (peer.isLost) {
      if (peerStates[peer.endpointId] == NearbyConnectionState.connecting ||
          peerStates[peer.endpointId] ==
              NearbyConnectionState.incomingRequest) {
        diagnostics?.record(
          'connection',
          'ENDPOINT_LOST_DURING_NEGOTIATION',
          severity: 'warning',
          connectionTraceId: _connectionTraces[peer.endpointId],
          operation: 'onEndpointLost',
          peerIdentifier: peer.endpointId,
          fields: {
            'appLifecycleState': appLifecycleState,
            'screenRoute': screenRoute,
          },
        );
        diagnostics?.record(
          'connection',
          'connection_negotiation_failed',
          severity: 'warning',
          connectionTraceId: _connectionTraces[peer.endpointId],
          operation: 'onEndpointLost',
          stateFrom: peerStates[peer.endpointId]?.name,
          stateTo: 'failed',
          peerIdentifier: peer.endpointId,
          nativeCode: 'ENDPOINT_LOST',
          reason: 'ENDPOINT_LOST_DURING_NEGOTIATION',
        );
      }
      if (peerStates[peer.endpointId] != NearbyConnectionState.connected) {
        _identityHandshakeTimeouts.remove(peer.endpointId)?.cancel();
        _cancelConnectionTimers(peer.endpointId);
        _setConnectionPhase(
          peer.endpointId,
          NearbyConnectionPhase.nativeResult,
        );
        _connectionStartedAt.remove(peer.endpointId);
        _connectionTraces.remove(peer.endpointId);
        discoveredPeers.removeWhere(
          (item) => item.endpointId == peer.endpointId,
        );
        peerStates[peer.endpointId] = NearbyConnectionState.failed;
        peerErrors[peer.endpointId] = 'endpoint_lost_during_negotiation';
        final deviceId = endpointToDeviceId.remove(peer.endpointId);
        if (deviceId != null) deviceToEndpointId.remove(deviceId);
      }
      _log('endpoint lost id=${peer.endpointId}');
      notifyListeners();
      return;
    }
    final index = discoveredPeers.indexWhere((item) => item.id == peer.id);
    diagnostics?.record(
      'trust',
      peer.identityFingerprintHint == null
          ? 'discovered_peer_hint_missing'
          : 'discovered_peer_hint_present',
      operation: 'onEndpointFound',
      peerIdentifier: peer.endpointId,
    );
    if (index == -1) {
      discoveredPeers.add(peer);
    } else {
      discoveredPeers[index] = peer;
    }
    peerStates.putIfAbsent(
      peer.endpointId,
      () => peer.connected
          ? NearbyConnectionState.connected
          : NearbyConnectionState.disconnected,
    );
    _log('endpoint found id=${peer.endpointId}');
    notifyListeners();
    _track(_maybeReconnect(peer));
  }

  Future<void> _maybeReconnect(NearbyPeer peer) async {
    if (peerStates[peer.endpointId] == NearbyConnectionState.connected ||
        peerStates[peer.endpointId] == NearbyConnectionState.connecting ||
        peerStates[peer.endpointId] == NearbyConnectionState.incomingRequest ||
        pendingConnectionRequests.containsKey(peer.endpointId)) {
      diagnostics?.record(
        'trust',
        'auto_reconnect_suppressed',
        operation: 'candidateLookup',
        peerIdentifier: peer.endpointId,
        reason: 'active_connection_or_prompt',
      );
      return;
    }
    final hint = peer.identityFingerprintHint;
    if (hint == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hint)) {
      diagnostics?.record(
        'trust',
        'auto_reconnect_suppressed',
        operation: 'candidateLookup',
        peerIdentifier: peer.endpointId,
        reason: 'no_valid_fingerprint_candidate',
      );
      return;
    }
    final candidates = await nearbyDevices.listDevices();
    final saved = candidates.where(
      (device) => device.publicIdentityFingerprint == hint,
    );
    if (saved.length != 1) {
      diagnostics?.record(
        'trust',
        'auto_reconnect_suppressed',
        operation: 'candidateLookup',
        peerIdentifier: peer.endpointId,
        reason: 'no_unique_saved_peer',
      );
      return;
    }
    final device = saved.single;
    if (!device.isTrusted ||
        !device.autoReconnectEnabled ||
        device.isBlocked ||
        device.publicIdentityKey == null) {
      diagnostics?.record(
        'trust',
        'auto_reconnect_suppressed',
        operation: 'candidateLookup',
        peerIdentifier: peer.endpointId,
        reason: device.isBlocked
            ? 'blocked'
            : device.publicIdentityKey == null
            ? 'incomplete_legacy_trust'
            : 'not_eligible',
        fields: {
          'trusted': device.isTrusted,
          'autoReconnect': device.autoReconnectEnabled,
          'publicKeyAvailable': device.publicIdentityKey != null,
        },
      );
      return;
    }
    // Both peers see the same pinned fingerprints, so only the lower one
    // initiates. The fingerprint is only a candidate selector; proof is still
    // required after connecting.
    final local = await identityCrypto.getPublicIdentity();
    if (local.fingerprint.compareTo(hint) >= 0) {
      diagnostics?.record(
        'trust',
        'auto_reconnect_suppressed',
        operation: 'candidateLookup',
        peerIdentifier: peer.endpointId,
        reason: 'other_peer_is_initiator',
      );
      return;
    }
    if (peerStates[peer.endpointId] == NearbyConnectionState.connected ||
        peerStates[peer.endpointId] == NearbyConnectionState.connecting ||
        peerStates[peer.endpointId] == NearbyConnectionState.incomingRequest ||
        pendingConnectionRequests.containsKey(peer.endpointId)) {
      diagnostics?.record(
        'trust',
        'auto_reconnect_suppressed',
        operation: 'candidateLookup',
        peerIdentifier: peer.endpointId,
        reason: 'connection_became_active_during_lookup',
      );
      return;
    }
    final retryAt = _nextReconnectAt[hint];
    if (retryAt != null && retryAt.isAfter(DateTime.now().toUtc())) {
      diagnostics?.record(
        'trust',
        'auto_reconnect_suppressed',
        operation: 'candidateLookup',
        peerIdentifier: peer.endpointId,
        reason: 'retry_backoff',
      );
      return;
    }
    if (!_automaticConnectionAttempts.add(hint)) {
      diagnostics?.record(
        'trust',
        'auto_reconnect_suppressed',
        operation: 'candidateLookup',
        peerIdentifier: peer.endpointId,
        reason: 'single_flight',
      );
      return;
    }
    _reconnectFingerprintByEndpoint[peer.endpointId] = hint;
    final attempts = _reconnectAttemptCounts.update(
      hint,
      (count) => (count + 1).clamp(1, 5).toInt(),
      ifAbsent: () => 1,
    );
    diagnostics?.record(
      'trust',
      'retry_started',
      connectionTraceId: _connectionTraces[peer.endpointId],
      operation: 'autoReconnect',
      peerIdentifier: peer.endpointId,
      fields: {'attempt': attempts},
    );
    _nextReconnectAt[hint] = DateTime.now().toUtc().add(
      Duration(seconds: 1 << attempts),
    );
    await _connect(peer.endpointId, userInitiated: false);
    if (peerStates[peer.endpointId] == NearbyConnectionState.failed) {
      _automaticConnectionAttempts.remove(hint);
      _scheduleReconnect(peer, hint, attempts);
    }
  }

  void _scheduleReconnect(NearbyPeer peer, String fingerprint, int attempts) {
    if (attempts >= 5 || _closed) {
      diagnostics?.record(
        'trust',
        'retry_exhausted',
        operation: 'autoReconnect',
        peerIdentifier: peer.endpointId,
        fields: {'attempt': attempts, 'closed': _closed},
      );
      return;
    }
    _reconnectTimers.remove(fingerprint)?.cancel();
    final delay = Duration(seconds: 1 << attempts);
    diagnostics?.record(
      'trust',
      'retry_scheduled',
      operation: 'autoReconnect',
      peerIdentifier: peer.endpointId,
      fields: {'attempt': attempts + 1, 'delayMs': delay.inMilliseconds},
    );
    _reconnectTimers[fingerprint] = Timer(delay, () {
      _reconnectTimers.remove(fingerprint);
      _nextReconnectAt.remove(fingerprint);
      _track(_maybeReconnect(peer));
    });
  }

  void _onConnection(NearbyConnectionEvent event) {
    final endpointId = event.peer.endpointId;
    if (event.state == NearbyConnectionState.connected ||
        event.state == NearbyConnectionState.failed ||
        event.state == NearbyConnectionState.disconnected) {
      // ยกเลิก timer ก่อนบันทึก callback เพื่อไม่ให้ native failure
      // แข่งกับ soft timeout เก่าแล้วถูกระบุสาเหตุผิด
      _cancelConnectionTimers(endpointId);
    }
    if (event.connectionTraceId != null) {
      _connectionTraces.putIfAbsent(endpointId, () => event.connectionTraceId!);
    }
    if (event.state == NearbyConnectionState.incomingRequest) {
      final traceId = _connectionTraces.putIfAbsent(
        endpointId,
        () => const Uuid().v4(),
      );
      _connectionStartedAt.putIfAbsent(endpointId, DateTime.now().toUtc);
      _setConnectionPhase(
        endpointId,
        event.isIncomingRequest
            ? NearbyConnectionPhase.connectionInitiated
            : NearbyConnectionPhase.awaitingRemoteApproval,
      );
      diagnostics?.record(
        'connection',
        'native_connection_initiated_received',
        connectionTraceId: traceId,
        operation: 'onConnectionInitiated',
        stateFrom: peerStates[endpointId]?.name ?? 'discovered',
        stateTo: 'incomingRequest',
        peerIdentifier: endpointId,
        fields: {
          'fingerprintHintAvailable':
              event.peer.identityFingerprintHint != null,
          'authenticationCodeAvailable': event.authenticationToken != null,
          'isIncomingConnection': event.isIncomingRequest,
        },
      );
      diagnostics?.record(
        'connection',
        'connection_negotiation_started',
        connectionTraceId: traceId,
        operation: 'acceptConnection',
        stateFrom: 'discovered',
        stateTo: 'incomingRequest',
        peerIdentifier: endpointId,
      );
      final existingPeer = discoveredPeers
          .where((peer) => peer.endpointId == endpointId)
          .firstOrNull;
      final fingerprint =
          event.peer.identityFingerprintHint ??
          existingPeer?.identityFingerprintHint;
      final resolvedEvent = NearbyConnectionEvent(
        peer: NearbyPeer(
          id: endpointId,
          name: event.peer.name == 'RELIO' && existingPeer != null
              ? existingPeer.name
              : event.peer.name,
          identityFingerprintHint: fingerprint,
        ),
        state: event.state,
        authenticationToken: event.authenticationToken,
        isIncomingRequest: event.isIncomingRequest,
      );
      diagnostics?.record(
        'trust',
        fingerprint == null
            ? 'discovered_peer_hint_missing'
            : 'discovered_peer_hint_present',
        connectionTraceId: traceId,
        operation: 'incomingCandidateResolution',
        peerIdentifier: endpointId,
        fields: {
          'callbackHintAvailable': event.peer.identityFingerprintHint != null,
          'cachedHintAvailable': existingPeer?.identityFingerprintHint != null,
          'resolvedHintAvailable': fingerprint != null,
        },
      );
      if (fingerprint != null) {
        final reservedEndpoint = _fingerprintEndpointReservations[fingerprint];
        if (reservedEndpoint != null && reservedEndpoint != endpointId) {
          _recordIncomingPromptSuppressed(
            endpointId,
            peerStates[reservedEndpoint] == NearbyConnectionState.connected
                ? 'already_connected'
                : 'active_connection',
            traceId: traceId,
          );
          if (event.isIncomingRequest) {
            unawaited(_rejectEndpoint(endpointId));
          }
          peerStates[endpointId] = NearbyConnectionState.disconnected;
          return;
        }
        _fingerprintEndpointReservations[fingerprint] = endpointId;
      }
      if (!event.isIncomingRequest &&
          (_userInitiatedEndpoints.contains(endpointId) ||
              peerStates[endpointId] == NearbyConnectionState.connecting)) {
        _recordIncomingPromptSuppressed(
          endpointId,
          'active_connection',
          traceId: traceId,
        );
        return;
      }
      if (pendingConnectionRequests.containsKey(endpointId)) {
        _recordIncomingPromptSuppressed(
          endpointId,
          'existing_prompt',
          traceId: traceId,
        );
        if (event.isIncomingRequest) {
          unawaited(_rejectEndpoint(endpointId));
        }
        return;
      }
      if (peerStates[endpointId] == NearbyConnectionState.connected) {
        _recordIncomingPromptSuppressed(
          endpointId,
          _completedIdentityHandshakes.contains(endpointId)
              ? 'already_connected'
              : 'trusted_verification',
          traceId: traceId,
        );
        if (event.isIncomingRequest) {
          unawaited(_rejectEndpoint(endpointId));
        }
        return;
      }
      if (peerStates[endpointId] == NearbyConnectionState.connecting ||
          _identityHandshakeTimeouts.containsKey(endpointId) ||
          _provisionalConnectionEndpoints.contains(endpointId)) {
        _recordIncomingPromptSuppressed(
          endpointId,
          _identityHandshakeTimeouts.containsKey(endpointId)
              ? 'trusted_verification'
              : 'active_connection',
          traceId: traceId,
        );
        if (event.isIncomingRequest) {
          unawaited(_rejectEndpoint(endpointId));
        }
        return;
      }
      if (fingerprint != null) {
        _track(_acceptKnownPeerRequest(resolvedEvent, fingerprint));
        return;
      }
      if (event.isIncomingRequest &&
          identityCrypto is! MockPeerIdentityCrypto) {
        _track(_acceptProvisionalIncoming(resolvedEvent));
      } else {
        _queueIncomingRequest(resolvedEvent);
      }
      return;
    }
    final eventFingerprint =
        event.peer.identityFingerprintHint ??
        _reconnectFingerprintByEndpoint[endpointId];
    if (event.state == NearbyConnectionState.failed ||
        event.state == NearbyConnectionState.disconnected) {
      if (eventFingerprint != null) {
        _automaticConnectionAttempts.remove(eventFingerprint);
      }
      if (event.state == NearbyConnectionState.failed) {
        final fingerprint = eventFingerprint;
        if (fingerprint != null) {
          final peer = NearbyPeer(
            id: endpointId,
            name: event.peer.name,
            identityFingerprintHint: fingerprint,
          );
          _scheduleReconnect(
            peer,
            fingerprint,
            _reconnectAttemptCounts[fingerprint] ?? 5,
          );
        }
      }
    }
    if (event.state == NearbyConnectionState.disconnected) {
      final requested = _appDisconnectRequests.remove(endpointId);
      _recordIdentityStage(
        endpointId,
        'native_endpoint_disconnected',
        severity: event.error == null ? 'warning' : 'error',
        reason: requested?.reason ?? 'not_requested_by_app',
        fields: {
          'disconnectRequester': requested == null ? 'nearby_or_remote' : 'app',
          'appDisconnectRequestFresh':
              requested != null &&
              DateTime.now().toUtc().difference(requested.requestedAt) <=
                  const Duration(seconds: 5),
          if (event.error != null) 'nativeErrorAvailable': true,
        },
        nativeCode: event.error,
      );
    }
    peerStates[endpointId] = event.state;
    if (event.state == NearbyConnectionState.failed &&
        RelioBuildInfo.developerDiagnosticsEnabled) {
      lastNativeConnectionFailure = event;
      lastDiagnostic = event.rawStatusName ?? event.error;
    }
    diagnostics?.record(
      'connection',
      event.state == NearbyConnectionState.failed
          ? 'native_connection_resolution_failed'
          : 'native_connection_result',
      connectionTraceId:
          event.connectionTraceId ?? _connectionTraces[endpointId],
      operation: event.operation ?? 'onConnectionResult',
      stateFrom: event.state == NearbyConnectionState.connected
          ? 'connecting'
          : 'connecting',
      stateTo: event.state.name,
      peerIdentifier: endpointId,
      nativeCode:
          (RelioBuildInfo.developerDiagnosticsEnabled
              ? event.rawStatusCode
              : null) ??
          (event.error == null ? 'success' : _errorCode(event.error!)),
      nativeMessage:
          (RelioBuildInfo.developerDiagnosticsEnabled
              ? event.rawStatusMessage
              : null) ??
          event.error,
      fields: {
        if (RelioBuildInfo.developerDiagnosticsEnabled &&
            event.rawStatusCode != null)
          'rawStatusCode': event.rawStatusCode,
        if (RelioBuildInfo.developerDiagnosticsEnabled &&
            event.rawStatusName != null)
          'rawStatusName': event.rawStatusName,
        if (RelioBuildInfo.developerDiagnosticsEnabled &&
            event.rawStatusMessage != null)
          'rawStatusMessage': event.rawStatusMessage,
        if (event.role != null) 'role': event.role,
        if (event.strategy != null) 'strategy': event.strategy,
        if (event.elapsedMs != null) 'elapsedMs': event.elapsedMs,
        if (RelioBuildInfo.developerDiagnosticsEnabled &&
            event.androidApi != null)
          'androidApi': event.androidApi,
        if (RelioBuildInfo.developerDiagnosticsEnabled &&
            event.googlePlayServicesVersionName != null)
          'googlePlayServicesVersionName': event.googlePlayServicesVersionName,
        if (RelioBuildInfo.developerDiagnosticsEnabled &&
            event.googlePlayServicesVersionCode != null)
          'googlePlayServicesVersionCode': event.googlePlayServicesVersionCode,
        if (RelioBuildInfo.developerDiagnosticsEnabled &&
            event.nearbyLibraryVersion != null)
          'nearbyLibraryVersion': event.nearbyLibraryVersion,
        if (RelioBuildInfo.developerDiagnosticsEnabled &&
            event.playServicesNearbyDependencyVersion != null)
          'playServicesNearbyDependencyVersion':
              event.playServicesNearbyDependencyVersion,
        if (_connectionStartedAt[endpointId] case final start?)
          'durationMs': DateTime.now().toUtc().difference(start).inMilliseconds,
      },
    );
    if (event.state == NearbyConnectionState.connected ||
        event.state == NearbyConnectionState.failed ||
        event.state == NearbyConnectionState.disconnected) {
      _cancelConnectionTimers(endpointId);
      _setConnectionPhase(endpointId, NearbyConnectionPhase.nativeResult);
      _connectionStartedAt.remove(endpointId);
    }
    if (event.state == NearbyConnectionState.connected ||
        event.state == NearbyConnectionState.failed) {
      if (event.state == NearbyConnectionState.failed) {
        diagnostics?.record(
          'connection',
          'GOOGLE_NEARBY_NATIVE_FAILURE',
          severity: 'error',
          connectionTraceId:
              event.connectionTraceId ?? _connectionTraces[endpointId],
          operation: event.operation ?? 'onConnectionResult',
          peerIdentifier: endpointId,
          nativeCode: event.rawStatusCode ?? event.error,
          nativeMessage: event.rawStatusMessage ?? event.error,
          fields: {
            if (event.rawStatusCode != null)
              'rawStatusCode': event.rawStatusCode,
            if (event.rawStatusName != null)
              'rawStatusName': event.rawStatusName,
            if (event.role != null) 'role': event.role,
            if (event.strategy != null) 'strategy': event.strategy,
            if (event.elapsedMs != null) 'elapsedMs': event.elapsedMs,
          },
        );
      }
      diagnostics?.record(
        'connection',
        event.state == NearbyConnectionState.connected
            ? 'connection_negotiation_completed'
            : 'connection_negotiation_failed',
        severity: event.state == NearbyConnectionState.failed
            ? 'warning'
            : 'info',
        connectionTraceId:
            event.connectionTraceId ?? _connectionTraces[endpointId],
        operation: event.operation ?? 'onConnectionResult',
        stateFrom: 'negotiating',
        stateTo: event.state.name,
        peerIdentifier: endpointId,
        nativeCode: event.rawStatusCode ?? event.error,
        nativeMessage: event.rawStatusMessage ?? event.error,
        reason: event.state == NearbyConnectionState.failed
            ? 'GOOGLE_NEARBY_NATIVE_FAILURE'
            : null,
        fields: {
          if (event.role != null) 'role': event.role,
          if (event.strategy != null) 'strategy': event.strategy,
          if (event.elapsedMs != null) 'elapsedMs': event.elapsedMs,
        },
      );
    }
    if (event.state == NearbyConnectionState.connected) {
      _setConnectionPhase(endpointId, NearbyConnectionPhase.identityHandshake);
      pendingConnectionRequests.remove(endpointId);
      peerErrors.remove(endpointId);
      _connectionStartedAt.putIfAbsent(endpointId, DateTime.now().toUtc);
      _identityHandshakeTimeouts.remove(endpointId)?.cancel();
      _completedIdentityHandshakes.remove(endpointId);
      _identityHandshakeTimeouts[endpointId] = Timer(handshakeTimeout, () {
        if (peerStates[endpointId] == NearbyConnectionState.connected &&
            !_completedIdentityHandshakes.contains(endpointId)) {
          _recordIdentityStage(
            endpointId,
            'identity_handshake_timeout',
            severity: 'error',
            reason: 'identity_proof_or_enrollment_deadline',
            fields: {'timeoutMs': handshakeTimeout.inMilliseconds},
          );
          peerErrors[endpointId] = 'identity_handshake_timeout';
          _track(_expireHandshake(endpointId));
          notifyListeners();
        }
      });
      final index = discoveredPeers.indexWhere((item) => item.id == endpointId);
      final peer = NearbyPeer(
        id: endpointId,
        name: event.peer.name,
        connected: true,
        deviceId: endpointToDeviceId[endpointId],
        identityFingerprintHint: event.peer.identityFingerprintHint,
      );
      if (index == -1) {
        discoveredPeers.add(peer);
      } else {
        discoveredPeers[index] = peer;
      }
      _track(_beginPeerHandshake(endpointId));
    } else if (event.state == NearbyConnectionState.disconnected) {
      pendingConnectionRequests.remove(endpointId);
      _approvedConnectionEndpoints.remove(endpointId);
      _userInitiatedEndpoints.remove(endpointId);
      _identityChallenges.remove(endpointId);
      _completedIdentityHandshakes.remove(endpointId);
      _identityHandshakeTimeouts.remove(endpointId)?.cancel();
      final deviceId = endpointToDeviceId.remove(endpointId);
      if (deviceId != null) deviceToEndpointId.remove(deviceId);
      _fingerprintEndpointReservations.removeWhere(
        (_, reservedEndpoint) => reservedEndpoint == endpointId,
      );
      _connectionPhases.remove(endpointId);
      _connectionPhaseStartedAt.remove(endpointId);
    } else if (event.state == NearbyConnectionState.failed) {
      _identityHandshakeTimeouts.remove(endpointId)?.cancel();
      peerErrors[endpointId] = event.error ?? 'connection failed';
    }
    if (event.state == NearbyConnectionState.failed ||
        event.state == NearbyConnectionState.disconnected) {
      _approvedConnectionEndpoints.remove(endpointId);
      _provisionalConnectionEndpoints.remove(endpointId);
      _provisionalIncomingRequests.remove(endpointId);
      _pendingVerifiedIdentityApprovals.remove(endpointId);
      _pendingIdentityApprovalReasons.remove(endpointId);
      _userInitiatedEndpoints.remove(endpointId);
      _identityChallenges.remove(endpointId);
      _fingerprintEndpointReservations.removeWhere(
        (_, reservedEndpoint) => reservedEndpoint == endpointId,
      );
    }
    if (event.error != null) peerErrors[endpointId] = event.error!;
    _log(
      'connection state=${event.state.name} endpoint=$endpointId'
      '${event.error == null ? '' : ' code=${_errorCode(event.error!)}'}',
    );
    if (event.state == NearbyConnectionState.disconnected ||
        event.state == NearbyConnectionState.failed) {
      _connectionTraces.remove(endpointId);
      _connectionStartedAt.remove(endpointId);
      _connectionPhases.remove(endpointId);
      _connectionPhaseStartedAt.remove(endpointId);
    }
    if (!hasActiveConnectionAttempts) _sessionRestartDeferred = false;
    notifyListeners();
  }

  void _recordIncomingPromptSuppressed(
    String endpointId,
    String reason, {
    required String traceId,
  }) {
    diagnostics?.record(
      'connection',
      'incoming_prompt_suppressed_$reason',
      connectionTraceId: traceId,
      operation: 'onConnectionInitiated',
      peerIdentifier: endpointId,
      reason: reason,
      fields: {
        'activeConnections': connectedPeerCount,
        'activeHandshakes': _identityHandshakeTimeouts.length,
        'appLifecycleState': appLifecycleState,
        'screenRoute': screenRoute,
      },
    );
  }

  Future<void> _acceptProvisionalIncoming(NearbyConnectionEvent event) async {
    final endpointId = event.peer.endpointId;
    if (_provisionalConnectionEndpoints.contains(endpointId) ||
        pendingConnectionRequests.containsKey(endpointId) ||
        peerStates[endpointId] == NearbyConnectionState.connected) {
      _recordIncomingPromptSuppressed(
        endpointId,
        'active_connection',
        traceId: _connectionTraces[endpointId]!,
      );
      return;
    }
    _provisionalConnectionEndpoints.add(endpointId);
    _provisionalIncomingRequests[endpointId] = event;
    peerStates[endpointId] = NearbyConnectionState.connecting;
    _setConnectionPhase(
      endpointId,
      NearbyConnectionPhase.awaitingRemoteApproval,
    );
    _startConnectionSoftTimeout(endpointId);
    diagnostics?.record(
      'trust',
      'trusted_transport_auto_accepted',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'acceptProvisionalTransport',
      peerIdentifier: endpointId,
      reason: 'fingerprint_hint_unavailable_identity_proof_required',
      fields: {
        'trustedCandidatePendingVerification': true,
        'privateOperationsAllowed': false,
      },
    );
    diagnostics?.record(
      'trust',
      'trusted_candidate_pending_verification',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'identityHandshake',
      peerIdentifier: endpointId,
    );
    notifyListeners();
    try {
      await transport.acceptConnection(
        endpointId,
        connectionTraceId: _connectionTraces[endpointId],
      );
      _nativePhaseAccepted(
        endpointId,
        NearbyConnectionPhase.nativeAcceptAccepted,
        operation: 'acceptConnection',
      );
    } on Object catch (error) {
      _provisionalConnectionEndpoints.remove(endpointId);
      _provisionalIncomingRequests.remove(endpointId);
      _cancelConnectionTimers(endpointId);
      _setConnectionPhase(endpointId, NearbyConnectionPhase.nativeResult);
      peerStates[endpointId] = NearbyConnectionState.failed;
      _fail('ยอมรับคำขอชั่วคราวไม่สำเร็จ: $error', code: _errorCode(error));
    }
  }

  Future<void> _handshakeAndShareActiveSos(String endpointId) async {
    _log('connection result=connected endpoint=$endpointId');
    _log('hello send endpoint=$endpointId');
    await sendHello(peerId: endpointId);
    final deviceId = await identity.getDeviceId();
    final active = await sos?.readActive(ownerDeviceId: deviceId);
    if (active != null) await sendSos(active, peerId: endpointId);
  }

  Future<void> _beginPeerHandshake(String endpointId) async {
    _recordIdentityStage(
      endpointId,
      'identity_handshake_started',
      fields: {
        'firstContactConsent':
            _approvedConnectionEndpoints.contains(endpointId) ||
            _userInitiatedEndpoints.contains(endpointId),
        'pinnedPeerKeyRequiredBeforehand': false,
      },
    );
    if (identityCrypto is MockPeerIdentityCrypto) {
      await _handshakeAndShareActiveSos(endpointId);
      _completedIdentityHandshakes.add(endpointId);
      _identityHandshakeTimeouts.remove(endpointId)?.cancel();
      return;
    }
    try {
      await _sendIdentityChallenge(endpointId);
    } on Object catch (error) {
      _recordIdentityStage(
        endpointId,
        'identity_handshake_failed',
        severity: 'error',
        reason: 'challenge_send_failed',
        nativeCode: _errorCode(error),
      );
      peerErrors[endpointId] = 'identity_challenge_send_failed';
      await disconnect(endpointId, reason: 'identity_challenge_send_failed');
    }
  }

  void _recordIdentityStage(
    String endpointId,
    String event, {
    String severity = 'info',
    String? reason,
    Object? nativeCode,
    Map<String, Object?> fields = const {},
  }) {
    final startedAt = _connectionStartedAt[endpointId];
    diagnostics?.record(
      'identity',
      event,
      severity: severity,
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'identityHandshake',
      peerIdentifier: endpointId,
      reason: reason,
      nativeCode: nativeCode,
      fields: {
        'protocolVersion': 2,
        'handshakeState': event,
        if (startedAt != null)
          'elapsedMs': DateTime.now()
              .toUtc()
              .difference(startedAt)
              .inMilliseconds,
        ...fields,
      },
    );
  }

  void _queueIncomingRequest(NearbyConnectionEvent event) {
    final endpointId = event.peer.endpointId;
    final isNewRequest = !pendingConnectionRequests.containsKey(endpointId);
    pendingConnectionRequests[endpointId] = event;
    peerStates[endpointId] = event.state;
    _setConnectionPhase(endpointId, NearbyConnectionPhase.awaitingApproval);
    if (isNewRequest) {
      _connectionSoftTimeouts.remove(endpointId)?.cancel();
      _connectionSoftTimeouts[endpointId] = Timer(connectionAttemptTimeout, () {
        if (pendingConnectionRequests.containsKey(endpointId)) {
          unawaited(_expireIncomingRequest(endpointId));
        }
      });
    }
    diagnostics?.record(
      'connection',
      'incoming_request_pending',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'queueIncomingRequest',
      stateFrom: 'nativeInitiated',
      stateTo: 'incomingRequest',
      peerIdentifier: endpointId,
    );
    _log(
      'incoming connection request peer=${DiagnosticsLogService.peerAlias(endpointId)}',
    );
    notifyListeners();
  }

  Future<void> _rejectEndpoint(String endpointId) => transport.rejectConnection(
    endpointId,
    connectionTraceId: _connectionTraces[endpointId],
  );

  Future<void> _expireIncomingRequest(String endpointId) async {
    final event = pendingConnectionRequests.remove(endpointId);
    _connectionSoftTimeouts.remove(endpointId)?.cancel();
    if (event == null || _closed) return;
    try {
      await transport.rejectConnection(
        endpointId,
        connectionTraceId: _connectionTraces[endpointId],
      );
    } on Object {
      // Best-effort native cleanup; a stale request must not retain local state.
    }
    peerStates[endpointId] = NearbyConnectionState.disconnected;
    peerErrors[endpointId] = 'incoming_request_timeout';
    diagnostics?.record(
      'connection',
      'incoming_request_timeout',
      severity: 'warning',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'rejectConnection',
      stateFrom: 'incomingRequest',
      stateTo: 'disconnected',
      peerIdentifier: endpointId,
      reason: 'approval_timeout',
    );
    notifyListeners();
  }

  Future<void> _acceptKnownPeerRequest(
    NearbyConnectionEvent event,
    String fingerprintHint,
  ) async {
    final endpointId = event.peer.endpointId;
    final devices = await nearbyDevices.listDevices();
    final matches = devices.where(
      (device) => device.publicIdentityFingerprint == fingerprintHint,
    );
    if (matches.length != 1) {
      diagnostics?.record(
        'trust',
        'manual_fallback',
        connectionTraceId: _connectionTraces[endpointId],
        operation: 'knownPeerLookup',
        peerIdentifier: endpointId,
        reason: 'fingerprint_not_uniquely_pinned',
      );
      _queueIncomingRequest(event);
      return;
    }
    final device = matches.single;
    if (device.isBlocked) {
      peerStates[endpointId] = NearbyConnectionState.disconnected;
      await _rejectEndpoint(endpointId);
      return;
    }
    final activeEndpoint = deviceToEndpointId[device.deviceId];
    if (activeEndpoint != null &&
        activeEndpoint != endpointId &&
        (peerStates[activeEndpoint] == NearbyConnectionState.connected ||
            peerStates[activeEndpoint] == NearbyConnectionState.connecting)) {
      _recordIncomingPromptSuppressed(
        endpointId,
        peerStates[activeEndpoint] == NearbyConnectionState.connected
            ? 'already_connected'
            : 'active_connection',
        traceId: _connectionTraces[endpointId]!,
      );
      try {
        await _rejectEndpoint(endpointId);
      } on Object {
        // Duplicate endpoint cleanup must not disturb the active peer session.
      }
      peerStates[endpointId] = NearbyConnectionState.disconnected;
      return;
    }
    if (!device.isTrusted ||
        !device.autoReconnectEnabled ||
        device.publicIdentityKey == null) {
      diagnostics?.record(
        'trust',
        'manual_fallback',
        connectionTraceId: _connectionTraces[endpointId],
        operation: 'knownPeerLookup',
        peerIdentifier: endpointId,
        reason: device.isTrusted ? 'incomplete_legacy_trust' : 'not_trusted',
        fields: {
          'trusted': device.isTrusted,
          'publicKeyAvailable': device.publicIdentityKey != null,
        },
      );
      _queueIncomingRequest(event);
      return;
    }
    _approvedConnectionEndpoints.add(endpointId);
    diagnostics?.record(
      'trust',
      'trusted_reconnect_candidate_accepted',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'acceptConnection',
      peerIdentifier: endpointId,
      fields: {'pinnedKeyAvailable': true},
    );
    await acceptConnectionRequest(endpointId);
  }

  Future<void> _sendIdentityChallenge(String endpointId) async {
    if (_identityChallenges.containsKey(endpointId)) {
      _recordIdentityStage(
        endpointId,
        'identity_challenge_suppressed',
        reason: 'challenge_already_pending',
      );
      return;
    }
    final localId = await identity.getDeviceId();
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final challengeId = const Uuid().v4();
    final nonce = base64Url.encode(bytes).replaceAll('=', '');
    final expiresAt = DateTime.now().toUtc().add(const Duration(seconds: 45));
    _identityChallenges[endpointId] = _PendingIdentityChallenge(
      challengeId: challengeId,
      nonce: nonce,
      challengerDeviceId: localId,
      expiresAt: expiresAt,
    );
    _recordIdentityStage(
      endpointId,
      'identity_challenge_created',
      fields: {'challengeTtlMs': 45000},
    );
    final packet = RelioPacket.identityChallenge(
      senderDeviceId: localId,
      senderUserId: await _senderUserId(),
      challengeId: challengeId,
      nonce: nonce,
      targetDeviceId: endpointToDeviceId[endpointId] ?? '',
      expiresAt: expiresAt,
    );
    await transport.sendBytes(packet.toBytes(), peerId: endpointId);
    _recordIdentityStage(endpointId, 'identity_challenge_sent');
  }

  Future<void> _handleIdentityChallenge(
    String endpointId,
    RelioPacket packet,
  ) async {
    _recordIdentityStage(endpointId, 'identity_challenge_received');
    final payload = packet.payload;
    final challengeId = payload['challengeId']! as String;
    final nonce = payload['nonce']! as String;
    final localId = await identity.getDeviceId();
    final target = payload['targetDeviceId']! as String;
    final expiresAt = DateTime.tryParse(payload['expiresAt']! as String);
    if ((target.isNotEmpty && target != localId) ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now().toUtc()) ||
        expiresAt.difference(DateTime.now().toUtc()) >
            const Duration(seconds: 60) ||
        !RegExp(r'^[A-Za-z0-9_-]{40,48}$').hasMatch(nonce)) {
      protocolErrorCount++;
      _recordIdentityStage(
        endpointId,
        'identity_handshake_failed',
        severity: 'error',
        reason: 'invalid_or_expired_challenge',
      );
      await disconnect(endpointId, reason: 'invalid_or_expired_challenge');
      return;
    }
    final now = DateTime.now().toUtc();
    // เก็บ challenge ที่เคยตอบไว้ชั่วคราว เพื่อกัน request เดิมถูก replay
    _receivedChallengeExpiries.removeWhere((_, expiry) => !expiry.isAfter(now));
    if (_receivedChallengeExpiries.containsKey(challengeId)) {
      protocolErrorCount++;
      _recordIdentityStage(
        endpointId,
        'identity_handshake_failed',
        severity: 'error',
        reason: 'challenge_replay',
      );
      await disconnect(endpointId, reason: 'challenge_replay');
      return;
    }
    if (_receivedChallengeExpiries.length >= 128) {
      final oldest = _receivedChallengeExpiries.keys.first;
      _receivedChallengeExpiries.remove(oldest);
    }
    _receivedChallengeExpiries[challengeId] = expiresAt;
    final own = await identityCrypto.getPublicIdentity();
    final signed = identityChallengeMessage(
      challengeId: challengeId,
      nonce: nonce,
      challengerDeviceId: packet.senderDeviceId,
      responderDeviceId: localId,
    );
    final signature = await identityCrypto.sign(signed);
    final proof = RelioPacket.identityProof(
      senderDeviceId: localId,
      senderUserId: await _senderUserId(),
      challengeId: challengeId,
      nonce: nonce,
      challengerDeviceId: packet.senderDeviceId,
      displayName: await identity.getDisplayName(),
      status: (await currentStatus()).name,
      capabilities: const ['textMessage', 'deviceStatus', 'ack', 'relay-v1'],
      publicKey: own.publicKey,
      fingerprint: own.fingerprint,
      signature: signature,
    );
    _recordIdentityStage(endpointId, 'identity_response_created');
    _recordIdentityStage(endpointId, 'identity_public_key_sent');
    await transport.sendBytes(proof.toBytes(), peerId: endpointId);
    _recordIdentityStage(endpointId, 'identity_response_sent');
  }

  Future<void> _handleIdentityProof(
    String endpointId,
    RelioPacket packet,
  ) async {
    _recordIdentityStage(endpointId, 'identity_response_received');
    _recordIdentityStage(endpointId, 'identity_public_key_received');
    final challenge = _identityChallenges[endpointId];
    final payload = packet.payload;
    if (challenge == null ||
        !challenge.expiresAt.isAfter(DateTime.now().toUtc()) ||
        payload['challengeId'] != challenge.challengeId ||
        payload['nonce'] != challenge.nonce ||
        payload['challengerDeviceId'] != challenge.challengerDeviceId) {
      protocolErrorCount++;
      _recordIdentityStage(
        endpointId,
        'identity_handshake_failed',
        severity: 'error',
        reason: 'challenge_response_mismatch_or_expired',
      );
      await disconnect(
        endpointId,
        reason: 'challenge_response_mismatch_or_expired',
      );
      return;
    }
    // Consume before signature work: a replay cannot reuse this challenge even
    // if verification fails or the packet handler is re-entered.
    _identityChallenges.remove(endpointId);
    final deviceId = packet.senderDeviceId;
    final publicKey = payload['publicKey']! as String;
    final fingerprint = payload['fingerprint']! as String;
    String computed;
    try {
      computed = await identityCrypto.fingerprint(publicKey);
    } on Object {
      protocolErrorCount++;
      _recordIdentityStage(
        endpointId,
        'identity_signature_verify_failed',
        severity: 'error',
        reason: 'invalid_public_key',
      );
      await disconnect(endpointId, reason: 'invalid_public_key_fingerprint');
      return;
    }
    final signed = identityChallengeMessage(
      challengeId: challenge.challengeId,
      nonce: challenge.nonce,
      challengerDeviceId: challenge.challengerDeviceId,
      responderDeviceId: deviceId,
    );
    _recordIdentityStage(endpointId, 'identity_signature_verify_started');
    final valid =
        computed == fingerprint &&
        await identityCrypto.verify(
          publicKey: publicKey,
          message: signed,
          signature: payload['signature']! as String,
        );
    if (!valid) {
      protocolErrorCount++;
      _recordIdentityStage(
        endpointId,
        'identity_signature_verify_failed',
        severity: 'error',
        reason: 'signature_or_fingerprint_mismatch',
      );
      _recordIdentityStage(
        endpointId,
        'identity_handshake_failed',
        severity: 'error',
        reason: 'signature_or_fingerprint_mismatch',
      );
      peerErrors[endpointId] = 'identity_proof_invalid';
      await disconnect(endpointId, reason: 'signature_or_fingerprint_mismatch');
      return;
    }
    _recordIdentityStage(endpointId, 'identity_signature_verify_success');
    final saved = await nearbyDevices.getDevice(deviceId);
    if (saved?.isBlocked == true) {
      _recordIdentityStage(
        endpointId,
        'identity_handshake_failed',
        severity: 'error',
        reason: 'peer_blocked',
      );
      await disconnect(endpointId, reason: 'peer_blocked');
      return;
    }
    final wasPinned = saved?.publicIdentityFingerprint != null;
    final pinnedMatches =
        wasPinned &&
        saved!.publicIdentityFingerprint == fingerprint &&
        saved.publicIdentityKey == publicKey;
    final consented =
        _approvedConnectionEndpoints.contains(endpointId) ||
        _userInitiatedEndpoints.contains(endpointId);
    _recordIdentityStage(
      endpointId,
      'identity_proof_verified',
      fields: {'pinnedIdentityMatched': pinnedMatches},
    );
    final pendingIdentity = _PendingVerifiedIdentity(
      request:
          _provisionalIncomingRequests[endpointId] ??
          NearbyConnectionEvent(
            peer: NearbyPeer(
              id: endpointId,
              name: payload['displayName']! as String,
              identityFingerprintHint: fingerprint,
            ),
            state: NearbyConnectionState.incomingRequest,
            isIncomingRequest: true,
          ),
      packet: packet,
      publicKey: publicKey,
      fingerprint: fingerprint,
      wasPinned: wasPinned,
      pinnedMatches: pinnedMatches,
      previousFingerprint: saved?.publicIdentityFingerprint,
    );
    final trustedAutoReconnect =
        pinnedMatches && saved.isTrusted && saved.autoReconnectEnabled;
    if (trustedAutoReconnect || (consented && (!wasPinned || pinnedMatches))) {
      diagnostics?.record(
        'trust',
        'trusted_candidate_verified',
        connectionTraceId: _connectionTraces[endpointId],
        operation: 'identityProof',
        peerIdentifier: endpointId,
        fields: {'automaticTrustedReconnect': trustedAutoReconnect},
      );
      await _finalizeVerifiedIdentity(endpointId, pendingIdentity);
      return;
    }
    _queueVerifiedIdentityApproval(endpointId, pendingIdentity);
  }

  void _queueVerifiedIdentityApproval(
    String endpointId,
    _PendingVerifiedIdentity pending,
  ) {
    if (_pendingVerifiedIdentityApprovals.containsKey(endpointId)) {
      _recordIncomingPromptSuppressed(
        endpointId,
        'existing_prompt',
        traceId: _connectionTraces[endpointId]!,
      );
      return;
    }
    final payload = pending.packet.payload;
    final request = NearbyConnectionEvent(
      peer: NearbyPeer(
        id: endpointId,
        name: payload['displayName']! as String,
        identityFingerprintHint: pending.fingerprint,
      ),
      state: NearbyConnectionState.incomingRequest,
      authenticationToken: pending.request.authenticationToken,
      isIncomingRequest: true,
    );
    _pendingVerifiedIdentityApprovals[endpointId] = pending;
    _pendingIdentityApprovalReasons[endpointId] =
        pending.wasPinned && !pending.pinnedMatches
        ? 'pinned_identity_changed'
        : 'first_contact_consent_required';
    pendingConnectionRequests[endpointId] = request;
    diagnostics?.record(
      'trust',
      pending.wasPinned && !pending.pinnedMatches
          ? 'trusted_candidate_rejected_identity_mismatch'
          : 'identity_approval_pending',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'identityProof',
      peerIdentifier: endpointId,
      reason: _pendingIdentityApprovalReasons[endpointId],
      fields: {
        'pinnedIdentityMatched': pending.pinnedMatches,
        'firstContactConsentRequired': !pending.wasPinned,
      },
    );
    notifyListeners();
  }

  Future<void> _finalizeVerifiedIdentity(
    String endpointId,
    _PendingVerifiedIdentity pending,
  ) async {
    final packet = pending.packet;
    final payload = packet.payload;
    final deviceId = packet.senderDeviceId;
    final saved = await nearbyDevices.getDevice(deviceId);
    if (saved?.isBlocked == true) {
      await disconnect(endpointId, reason: 'peer_blocked');
      return;
    }
    final currentFingerprint = saved?.publicIdentityFingerprint;
    final pinUnchanged = currentFingerprint == pending.previousFingerprint;
    final explicitIdentityApproval =
        _approvedConnectionEndpoints.contains(endpointId) &&
        _pendingVerifiedIdentityApprovals.containsKey(endpointId);
    if (!pinUnchanged && !explicitIdentityApproval) {
      peerErrors[endpointId] = 'identity_changed_during_approval';
      await disconnect(endpointId, reason: 'pinned_identity_changed');
      return;
    }
    final status = _statusFrom(payload['status']! as String);
    _updatePeerIdentity(
      endpointId,
      deviceId,
      displayName: payload['displayName']! as String,
      capabilities: _capabilitiesFrom(payload['capabilities']),
    );
    peerStatuses[deviceId] = status;
    if (!pending.pinnedMatches) {
      _recordIdentityStage(
        endpointId,
        'identity_enrollment_started',
        fields: {'wasPreviouslyPinned': pending.wasPinned},
      );
    }
    await nearbyDevices.upsert(
      deviceId: deviceId,
      displayName: payload['displayName']! as String,
      status: status,
    );
    if (!pending.pinnedMatches) {
      await nearbyDevices.setTrustedIdentity(
        deviceId: deviceId,
        publicIdentityKey: pending.publicKey,
        fingerprint: pending.fingerprint,
      );
      _recordIdentityStage(
        endpointId,
        'identity_fingerprint_pinned',
        fields: {'fingerprintPrefix': pending.fingerprint.substring(0, 12)},
      );
      _recordIdentityStage(endpointId, 'identity_enrollment_completed');
    }
    endpointToDeviceId[endpointId] = deviceId;
    deviceToEndpointId[deviceId] = endpointId;
    _approvedConnectionEndpoints.add(endpointId);
    _provisionalConnectionEndpoints.remove(endpointId);
    _provisionalIncomingRequests.remove(endpointId);
    _pendingVerifiedIdentityApprovals.remove(endpointId);
    _pendingIdentityApprovalReasons.remove(endpointId);
    peerStates[endpointId] = NearbyConnectionState.connected;
    _reconnectFingerprintByEndpoint.remove(endpointId);
    final fingerprint = pending.fingerprint;
    _automaticConnectionAttempts.remove(fingerprint);
    _reconnectTimers.remove(fingerprint)?.cancel();
    _nextReconnectAt.remove(fingerprint);
    _reconnectAttemptCounts.remove(fingerprint);
    final conversationId = await _conversationIdForDevice(deviceId, deviceId);
    await conversations.ensureConversation(
      id: conversationId,
      participantId: deviceId,
      displayName: payload['displayName']! as String,
      participantStatus: status,
    );
    _completedIdentityHandshakes.add(endpointId);
    _identityHandshakeTimeouts.remove(endpointId)?.cancel();
    peerErrors.remove(endpointId);
    _recordIdentityStage(endpointId, 'identity_handshake_completed');
    _recordIdentityStage(endpointId, 'identity_hello_sent');
    await sendHello(peerId: endpointId);
    _track(_flushPendingMessages(conversationId));
    final active = await sos?.readActive(
      ownerDeviceId: await identity.getDeviceId(),
    );
    if (active != null) await sendSos(active, peerId: endpointId);
  }

  Future<void> _expireHandshake(String endpointId) async {
    if (peerStates[endpointId] != NearbyConnectionState.connected ||
        _completedIdentityHandshakes.contains(endpointId)) {
      return;
    }
    peerErrors[endpointId] = 'identity_handshake_timeout';
    await disconnect(endpointId, reason: 'identity_handshake_timeout');
    endpointToDeviceId.remove(endpointId);
    peerStates[endpointId] = NearbyConnectionState.failed;
    peerErrors[endpointId] = 'identity_handshake_timeout';
    notifyListeners();
  }

  void _onPayload(NearbyPayloadEvent event) {
    _track(_handlePayload(event));
  }

  void _onFilePayload(NearbyFilePayloadEvent event) {
    _mediaFilesByPayload[event.payloadId] = event;
    _recordMediaStage(event.peerId, 'media_file_received');
    _track(_tryCompleteIncomingMedia(event.payloadId));
  }

  void _onTransfer(NearbyTransferEvent event) {
    final transferId = _payloadTransferIds[event.payloadId];
    if (transferId == null || attachments == null) return;
    _recordMediaStage(
      event.peerId,
      'media_native_transfer_${event.status.name}',
      reason: event.error,
      fields: {'bytesTransferred': event.bytesTransferred},
    );
    _track(_updateOutgoingTransfer(transferId, event));
  }

  Future<void> _updateOutgoingTransfer(
    String transferId,
    NearbyTransferEvent event,
  ) async {
    final attachment = await attachments!.getByTransferId(transferId);
    if (attachment == null) return;
    final status = switch (event.status) {
      NearbyTransferStatus.started ||
      NearbyTransferStatus.inProgress => MediaTransferState.transferring,
      NearbyTransferStatus.success => MediaTransferState.transferring,
      NearbyTransferStatus.failure => MediaTransferState.failed,
      NearbyTransferStatus.cancelled => MediaTransferState.cancelled,
    };
    await attachments!.updateProgress(
      attachment.id,
      status: status,
      bytesTransferred: event.bytesTransferred,
      errorCode: event.error,
    );
    if (status == MediaTransferState.failed ||
        status == MediaTransferState.cancelled) {
      await messages.markFailed(
        attachment.messageId,
        event.error ?? 'transfer_failed',
      );
    }
    notifyListeners();
  }

  Future<void> _handlePayload(NearbyPayloadEvent event) async {
    RelioPacket? receivedPacket;
    try {
      final packet = RelioPacket.fromBytes(event.bytes);
      receivedPacket = packet;
      final mappedDeviceId = endpointToDeviceId[event.peerId];
      final isIdentityHandshake =
          packet.type == RelioPacketType.identityChallenge ||
          packet.type == RelioPacketType.identityProof;
      if (identityCrypto is! MockPeerIdentityCrypto &&
          !_completedIdentityHandshakes.contains(event.peerId) &&
          !isIdentityHandshake) {
        protocolErrorCount++;
        _recordIdentityStage(
          event.peerId,
          'application_packet_blocked_before_identity_approval',
          severity: 'warning',
          reason: packet.type.name,
        );
        return;
      }
      if (!isIdentityHandshake &&
          packet.type != RelioPacketType.hello &&
          mappedDeviceId != packet.senderDeviceId) {
        protocolErrorCount += 1;
        _log('ปฏิเสธ ${packet.type.name}: endpoint ยังไม่ผ่าน hello handshake');
        return;
      }
      // Packet อาจมีข้อความ/SOS/พิกัดส่วนตัว จึงเก็บ diagnostics แค่ type กับ ID
      // และไม่เปิดเผย payload ใน log ปกติ
      lastReceivedPacket = _diagnosticPacket(packet);
      _log('รับ ${packet.type.name} จาก ${event.peerId}');
      switch (packet.type) {
        case RelioPacketType.identityChallenge:
          await _handleIdentityChallenge(event.peerId, packet);
        case RelioPacketType.identityProof:
          await _handleIdentityProof(event.peerId, packet);
        case RelioPacketType.hello:
          await _handleHello(event.peerId, packet);
        case RelioPacketType.textMessage:
          await _handleText(event.peerId, packet);
        case RelioPacketType.deviceStatus:
          await _handleDeviceStatus(packet);
        case RelioPacketType.ack:
          await _handleAck(packet);
        case RelioPacketType.sos:
          await _handleSos(event.peerId, packet);
        case RelioPacketType.mediaMetadata:
          await _handleMediaMetadata(event.peerId, packet);
        case RelioPacketType.mediaAck:
          await _handleMediaAck(packet);
        case RelioPacketType.locationMessage:
          await _handleLocation(event.peerId, packet);
        case RelioPacketType.readReceipt:
          await _handleReadReceipt(packet);
        case RelioPacketType.relayEnvelope:
          await relayEngine?.handleIncomingPacket(event.peerId, packet);
        case RelioPacketType.relayAck:
          await relayEngine?.handleIncomingPacket(event.peerId, packet);
      }
      notifyListeners();
    } on RelioPacketException catch (error) {
      protocolErrorCount += 1;
      peerErrors[event.peerId] = 'invalid_packet';
      if (receivedPacket?.type == RelioPacketType.identityChallenge ||
          receivedPacket?.type == RelioPacketType.identityProof) {
        _recordIdentityStage(
          event.peerId,
          'identity_handshake_failed',
          severity: 'error',
          reason: 'invalid_packet',
          fields: {'failureType': error.runtimeType.toString()},
        );
      }
      notifyListeners();
      _fail('packet ไม่ถูกต้อง: ${error.message}');
    } on Object catch (error) {
      peerErrors[event.peerId] = 'packet_processing_failed';
      if (receivedPacket?.type == RelioPacketType.identityChallenge ||
          receivedPacket?.type == RelioPacketType.identityProof) {
        _recordIdentityStage(
          event.peerId,
          'identity_handshake_failed',
          severity: 'error',
          reason: 'packet_handler_exception',
          fields: {'failureType': error.runtimeType.toString()},
        );
      }
      notifyListeners();
      _fail('ประมวลผล packet ไม่สำเร็จ: $error');
    }
  }

  Future<void> _handleMediaMetadata(
    String endpointId,
    RelioPacket packet,
  ) async {
    final payloadId = packet.payload['payloadId'] as String?;
    if (payloadId == null || payloadId.isEmpty) {
      _fail('mediaMetadata ไม่มี payloadId');
      return;
    }
    _mediaMetadataByPayload[payloadId] = packet;
    _recordMediaStage(endpointId, 'media_metadata_received');
    await _tryCompleteIncomingMedia(payloadId);
  }

  Future<void> _tryCompleteIncomingMedia(String payloadId) async {
    final packet = _mediaMetadataByPayload[payloadId];
    final file = _mediaFilesByPayload[payloadId];
    if (packet == null ||
        file == null ||
        attachments == null ||
        mediaStorage == null) {
      return;
    }
    if (identityCrypto is! MockPeerIdentityCrypto &&
        !_completedIdentityHandshakes.contains(
          _mediaFilesByPayload[payloadId]!.peerId,
        )) {
      return;
    }
    final messageId = packet.payload['messageId']! as String;
    final active = _incomingMediaOperations[messageId];
    if (active != null) {
      await active;
      return _tryCompleteIncomingMedia(payloadId);
    }
    // UUID เดียวทำทีละรายการ เพื่อไม่สร้างไฟล์หรือแจ้งเตือนซ้ำเมื่อ callback มาพร้อมกัน
    final operation = _persistIncomingMedia(payloadId, packet, file);
    _incomingMediaOperations[messageId] = operation;
    try {
      await operation;
    } finally {
      _incomingMediaOperations.remove(messageId);
    }
  }

  Future<void> _persistIncomingMedia(
    String payloadId,
    RelioPacket packet,
    NearbyFilePayloadEvent file,
  ) async {
    final payload = packet.payload;
    try {
      if (endpointToDeviceId[file.peerId] != packet.senderDeviceId) {
        throw const MediaStorageException('ไฟล์และ metadata มาจากคนละเครื่อง');
      }
      final existingMessage = await messages.getMessage(
        payload['messageId']! as String,
      );
      final existingAttachment = await attachments!.getById(
        payload['attachmentId']! as String,
      );
      if (existingMessage != null &&
          existingAttachment != null &&
          existingAttachment.transferStatus == MediaTransferState.completed) {
        if (existingMessage.senderDeviceId != packet.senderDeviceId ||
            existingAttachment.messageId != existingMessage.id ||
            existingAttachment.transferId != payload['transferId'] ||
            existingAttachment.byteSize != payload['byteSize'] ||
            existingAttachment.mimeType != payload['mimeType'] ||
            !await mediaStorage!.fileExists(existingAttachment.localPath) ||
            (payload['sha256'] != null &&
                await mediaStorage!.sha256ForFile(
                      existingAttachment.localPath,
                    ) !=
                    payload['sha256'])) {
          throw const MediaStorageException('ข้อมูลสื่อซ้ำไม่ตรงกับรายการเดิม');
        }
        await _sendMediaAck(file.peerId, packet, 'completed');
        return;
      }
      final storedPath = await mediaStorage!.storeIncomingFile(
        sourcePath: file.filePath,
        fileName: payload['fileName']! as String,
        expectedMimeType: payload['mimeType']! as String,
        expectedBytes: (payload['byteSize']! as num).toInt(),
        expectedSha256: payload['sha256'] as String?,
      );
      final conversationId = await _conversationIdForDevice(
        packet.senderDeviceId,
        packet.senderDeviceId,
      );
      await conversations.ensureConversation(
        id: conversationId,
        participantId: packet.senderDeviceId,
        displayName: _peerName(file.peerId, packet.senderUserId),
        participantStatus: DeviceStatus.normal,
      );
      final message = await messages.createIncomingMedia(
        conversationId: conversationId,
        senderId: packet.senderUserId,
        senderDeviceId: packet.senderDeviceId,
        messageId: payload['messageId']! as String,
        type: _mediaMessageType(payload['mediaType']! as String),
        fileName: payload['fileName']! as String,
        localPath: storedPath,
      );
      final attachmentId = payload['attachmentId']! as String;
      if (await attachments!.getById(attachmentId) == null) {
        await attachments!.createPending(
          id: attachmentId,
          messageId: message.id,
          transferId: payload['transferId']! as String,
          mediaType: _mediaType(payload['mediaType']! as String),
          fileName: payload['fileName']! as String,
          mimeType: payload['mimeType']! as String,
          localPath: storedPath,
          byteSize: (payload['byteSize']! as num).toInt(),
        );
      }
      await attachments!.markCompleted(attachmentId, localPath: storedPath);
      await _markIncomingReadIfVisible(conversationId, packet.senderDeviceId);
      if (existingMessage == null) {
        await _notifyIncoming(
          id: payload['messageId']! as String,
          title: _peerName(file.peerId, packet.senderUserId),
          preview: payload['mediaType'] == 'video' ? 'ส่งวิดีโอ' : 'ส่งรูปภาพ',
          route: '/chat/$conversationId',
        );
      }
      _recordMediaStage(
        file.peerId,
        'media_received_persisted',
        fields: {
          'mediaType': payload['mediaType'],
          'sizeBytes': payload['byteSize'],
        },
      );
      // ACK สำเร็จได้เมื่อไฟล์ตรวจผ่าน เก็บแล้ว และผูก attachment กับข้อความแล้วเท่านั้น
      await _sendMediaAck(file.peerId, packet, 'completed');
    } on Object catch (error) {
      _fail('รับไฟล์ไม่สำเร็จ: $error');
      await _sendMediaAck(
        file.peerId,
        packet,
        'failed',
        errorCode: 'invalid_file',
      );
    } finally {
      _mediaMetadataByPayload.remove(payloadId);
      _mediaFilesByPayload.remove(payloadId);
    }
  }

  Future<void> _handleMediaAck(RelioPacket packet) async {
    final transferId = packet.payload['transferId']! as String;
    final attachment = await attachments?.getByTransferId(transferId);
    if (attachment == null) return;
    final status = packet.payload['status']! as String;
    if (status == 'completed') {
      await attachments?.markCompleted(attachment.id);
      await messages.updateDeliveryStatus(
        attachment.messageId,
        DeliveryStatus.delivered,
      );
      acknowledgementCount += 1;
      _log('ACK media received status=completed');
    } else if (status == 'failed') {
      await attachments?.markFailed(
        attachment.id,
        packet.payload['errorCode'] as String? ?? 'remote_failed',
      );
      await messages.markFailed(attachment.messageId, 'remote_failed');
    }
  }

  Future<void> _handleLocation(String endpointId, RelioPacket packet) async {
    final payload = packet.payload;
    final conversationId = await _conversationIdForDevice(
      packet.senderDeviceId,
      payload['conversationId']! as String,
    );
    await conversations.ensureConversation(
      id: conversationId,
      participantId: packet.senderDeviceId,
      displayName: _peerName(endpointId, packet.senderUserId),
      participantStatus: DeviceStatus.normal,
    );
    await messages.createIncomingLocation(
      conversationId: conversationId,
      senderId: packet.senderUserId,
      senderDeviceId: packet.senderDeviceId,
      messageId: payload['messageId']! as String,
      location: LocationData(
        latitude: (payload['latitude']! as num).toDouble(),
        longitude: (payload['longitude']! as num).toDouble(),
        accuracyMeters: (payload['accuracyMeters'] as num?)?.toDouble(),
        capturedAt: DateTime.parse(payload['capturedAt']! as String),
        source: 'nearby',
      ),
    );
    await _markIncomingReadIfVisible(conversationId, packet.senderDeviceId);
    await _notifyIncoming(
      id: packet.payload['messageId']! as String,
      title: 'ได้รับตำแหน่งใหม่',
      route: '/chat/$conversationId',
    );
    await _sendAck(endpointId, packet);
  }

  Future<void> _sendMediaAck(
    String endpointId,
    RelioPacket source,
    String status, {
    String? errorCode,
  }) async {
    final payload = source.payload;
    final ack = RelioPacket.mediaAck(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: await _senderUserId(),
      messageId: payload['messageId']! as String,
      attachmentId: payload['attachmentId']! as String,
      transferId: payload['transferId']! as String,
      status: status,
      errorCode: errorCode,
    );
    await transport.sendBytes(ack.toBytes(), peerId: endpointId);
    lastSentPacket = _diagnosticPacket(ack);
    acknowledgementCount += 1;
    _log('ACK media sent status=$status');
  }

  Future<void> _markIncomingReadIfVisible(
    String conversationId,
    String peerDeviceId,
  ) async {
    if (!isConversationVisible(conversationId)) return;
    final messageIds = await messages.markConversationRead(conversationId);
    for (final messageId in messageIds) {
      await sendReadReceipt(messageId: messageId, peerDeviceId: peerDeviceId);
    }
  }

  Future<void> _notifyIncoming({
    required String id,
    required String title,
    required String route,
    String? preview,
    bool urgent = false,
  }) async {
    if (activeConversationId != null &&
        route == '/chat/$activeConversationId' &&
        isConversationVisible(activeConversationId!)) {
      return;
    }
    final sink = localNotifications;
    final setting = settings;
    if (sink == null || setting == null) return;
    if (!await setting.getBool('notifications_enabled', defaultValue: true)) {
      return;
    }
    final showPreview =
        !urgent &&
        await setting.getBool('notification_preview', defaultValue: false);
    await sink.show(
      id: id,
      title: urgent ? 'แจ้งเตือน SOS' : title,
      body: urgent
          ? 'มีเหตุฉุกเฉินใหม่ กรุณาตรวจสอบ'
          : notificationPreviewBody(
              enabled: showPreview,
              content: preview,
              fallback: 'คุณมีข้อความใหม่',
            ),
      route: route,
      urgent: urgent,
    );
  }

  void _recordMediaStage(
    String? endpointId,
    String event, {
    String severity = 'info',
    String? reason,
    Object? nativeCode,
    Map<String, Object?> fields = const {},
  }) {
    diagnostics?.record(
      'media',
      event,
      severity: severity,
      connectionTraceId: endpointId == null
          ? null
          : _connectionTraces[endpointId],
      operation: 'nearbyFileTransfer',
      peerIdentifier: endpointId,
      reason: reason,
      nativeCode: nativeCode,
      fields: fields,
    );
  }

  Future<void> _handleHello(String endpointId, RelioPacket packet) async {
    _log('hello receive: endpoint $endpointId');
    final savedPeer = await nearbyDevices.getDevice(packet.senderDeviceId);
    if (savedPeer?.isBlocked == true) {
      _log('blocked peer rejected after identity handshake');
      await disconnect(endpointId, reason: 'blocked_peer');
      return;
    }
    if (identityCrypto is! MockPeerIdentityCrypto &&
        (endpointToDeviceId[endpointId] != packet.senderDeviceId ||
            savedPeer?.publicIdentityKey == null ||
            savedPeer?.publicIdentityFingerprint == null)) {
      protocolErrorCount += 1;
      _log('hello rejected before cryptographic identity proof');
      await disconnect(endpointId, reason: 'hello_before_identity_proof');
      return;
    }
    if (savedPeer?.isTrusted != true &&
        !_approvedConnectionEndpoints.contains(endpointId) &&
        !_userInitiatedEndpoints.contains(endpointId)) {
      protocolErrorCount += 1;
      _log('unapproved peer identity rejected');
      await disconnect(endpointId, reason: 'unapproved_peer');
      return;
    }
    final status = _statusFrom(packet.payload['status'] as String);
    peerStatuses[packet.senderDeviceId] = status;
    final displayName = packet.payload['displayName']! as String;
    await nearbyDevices.upsert(
      deviceId: packet.senderDeviceId,
      displayName: displayName,
      status: status,
    );
    if (identityCrypto is MockPeerIdentityCrypto) {
      // Test transport only: production trust is pinned only after proof.
      await nearbyDevices.setTrusted(packet.senderDeviceId, true);
    }
    final conversationId = await _conversationIdForDevice(
      packet.senderDeviceId,
      packet.senderDeviceId,
    );
    await conversations.ensureConversation(
      id: conversationId,
      participantId: packet.senderDeviceId,
      displayName: displayName,
      participantStatus: status,
    );
    await conversations.updateParticipantStatus(packet.senderDeviceId, status);
    _updatePeerIdentity(
      endpointId,
      packet.senderDeviceId,
      displayName: displayName,
      capabilities: _capabilitiesFrom(packet.payload['capabilities']),
    );
    _completedIdentityHandshakes.add(endpointId);
    _identityHandshakeTimeouts.remove(endpointId)?.cancel();
    peerErrors.remove(endpointId);
    _recordIdentityStage(endpointId, 'identity_hello_received');
    if (identityCrypto is MockPeerIdentityCrypto) {
      _recordIdentityStage(endpointId, 'identity_handshake_completed');
    }
    _track(_flushPendingMessages(conversationId));
    _log('peer established: endpoint $endpointId ↔ ${packet.senderDeviceId}');
  }

  Future<void> _flushPendingMessages(String conversationId) async {
    if (!_pendingConversationFlushes.add(conversationId)) return;
    try {
      final pending = (await messages.listMessages(conversationId))
          .where(
            (message) =>
                message.outgoing && message.status == DeliveryStatus.pending,
          )
          .toList(growable: false);
      for (final message in pending) {
        await _sendPendingMessage(message);
      }
    } on Object catch (error) {
      _fail('ข้อความที่ค้างส่งยังไม่พร้อม: $error');
    } finally {
      _pendingConversationFlushes.remove(conversationId);
    }
  }

  Future<void> _sendPendingMessage(RelioMessage message) async {
    if (message.type != MessageType.image &&
        message.type != MessageType.video) {
      await sendMessage(message);
      return;
    }
    final matching = await attachments?.watchForMessage(message.id).first;
    if (matching == null || matching.isEmpty) {
      await messages.markFailed(message.id, 'attachment_missing');
      _recordMediaStage(
        null,
        'media_retry_failed',
        reason: 'attachment_missing',
      );
      return;
    }
    await sendMediaMessage(message, matching.first);
  }

  Future<void> _handleText(String endpointId, RelioPacket packet) async {
    final messageId = packet.payload['messageId']! as String;
    if (!_incomingTextMessagesInProgress.add(messageId)) {
      _log(
        'duplicate textMessage acknowledged while persistence is in progress',
      );
      await _sendAck(endpointId, packet);
      return;
    }
    try {
      if (await messages.getMessage(messageId) != null) {
        _log('duplicate textMessage acknowledged');
        await _sendAck(endpointId, packet);
        return;
      }
      final conversationId = await _conversationIdForDevice(
        packet.senderDeviceId,
        packet.payload['conversationId']! as String,
      );
      await conversations.ensureConversation(
        id: conversationId,
        participantId: packet.senderDeviceId,
        displayName: _peerName(endpointId, packet.senderUserId),
        participantStatus: DeviceStatus.normal,
      );
      await messages.createIncomingText(
        conversationId: conversationId,
        senderId: packet.senderUserId,
        senderDeviceId: packet.senderDeviceId,
        messageId: messageId,
        text: packet.payload['text']! as String,
        createdAt: DateTime.parse(packet.payload['timestamp']! as String),
      );
      await _markIncomingReadIfVisible(conversationId, packet.senderDeviceId);
      await _notifyIncoming(
        id: messageId,
        title: _peerName(endpointId, packet.senderUserId),
        preview: packet.payload['text']! as String,
        route: '/chat/$conversationId',
      );
      await _sendAck(endpointId, packet);
    } finally {
      _incomingTextMessagesInProgress.remove(messageId);
    }
  }

  Future<void> _handleDeviceStatus(RelioPacket packet) async {
    final status = _statusFrom(packet.payload['status']! as String);
    peerStatuses[packet.senderDeviceId] = status;
    final displayName = packet.payload['displayName']! as String;
    await nearbyDevices.upsert(
      deviceId: packet.senderDeviceId,
      displayName: displayName,
      status: status,
    );
    await conversations.updateParticipantStatus(packet.senderDeviceId, status);
    _updatePeerIdentity(
      deviceToEndpointId[packet.senderDeviceId],
      packet.senderDeviceId,
      displayName: displayName,
    );
  }

  Future<void> _handleAck(RelioPacket packet) async {
    final messageId =
        packet.payload['messageId'] as String? ??
        _packetMessageIds[packet.payload['packetId']];
    if (messageId == null) return;
    final message = await messages.getMessage(messageId);
    if (message == null || message.status == DeliveryStatus.delivered) return;
    await messages.updateDeliveryStatus(messageId, DeliveryStatus.delivered);
    acknowledgementCount += 1;
    _log('ACK message delivered');
    _log('รับ ACK ของข้อความ $messageId');
  }

  Future<void> sendReadReceipt({
    required String messageId,
    required String peerDeviceId,
  }) async {
    final endpointId = deviceToEndpointId[peerDeviceId];
    if (endpointId == null ||
        peerStates[endpointId] != NearbyConnectionState.connected) {
      return;
    }
    final packet = RelioPacket.readReceipt(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: await _senderUserId(),
      messageId: messageId,
      readAt: DateTime.now(),
    );
    await transport.sendBytes(packet.toBytes(), peerId: endpointId);
    lastSentPacket = _diagnosticPacket(packet);
    _log('ส่ง readReceipt แล้ว');
  }

  Future<void> _handleReadReceipt(RelioPacket packet) async {
    await messages.markMessageRead(packet.payload['messageId']! as String);
    _log('รับ readReceipt แล้ว');
  }

  Future<void> _handleSos(String endpointId, RelioPacket packet) async {
    if (sos == null) {
      _fail('รับ SOS ไม่ได้: SOS repository ไม่พร้อมใช้งาน');
      return;
    }
    final payload = packet.payload;
    final event = await sos!.createIncoming(
      id: payload['sosId']! as String,
      ownerDeviceId: payload['ownerDeviceId']! as String,
      ownerUserId: payload['ownerUserId']! as String,
      message: payload['message'] as String?,
      latitude: (payload['latitude'] as num?)?.toDouble(),
      longitude: (payload['longitude'] as num?)?.toDouble(),
      locationAccuracy: (payload['accuracyMeters'] as num?)?.toDouble(),
      locationCapturedAt: payload['locationCapturedAt'] == null
          ? null
          : DateTime.tryParse(payload['locationCapturedAt']! as String),
      createdAt: DateTime.parse(payload['createdAt']! as String),
      isActive: payload['isActive']! as bool,
    );
    final displayName = payload['displayName']! as String;
    final status = event.isActive ? DeviceStatus.sos : DeviceStatus.normal;
    if (event.isActive) {
      await _notifyIncoming(
        id: event.id,
        title: displayName,
        route: '/sos',
        urgent: true,
      );
    }
    peerStatuses[event.ownerDeviceId] = status;
    await nearbyDevices.upsert(
      deviceId: event.ownerDeviceId,
      displayName: displayName,
      status: status,
    );
    final conversationId = await _conversationIdForDevice(
      event.ownerDeviceId,
      event.ownerDeviceId,
    );
    await conversations.ensureConversation(
      id: conversationId,
      participantId: event.ownerDeviceId,
      displayName: displayName,
      participantStatus: status,
    );
    _updatePeerIdentity(
      endpointId,
      event.ownerDeviceId,
      displayName: displayName,
    );
    _log(
      event.isActive
          ? 'SOS RECEIVED จาก $displayName'
          : 'SOS cleared จาก $displayName',
    );
    await _sendAck(endpointId, packet);
  }

  Future<void> _sendAck(String endpointId, RelioPacket packet) async {
    final ack = RelioPacket.ack(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: await _senderUserId(),
      acknowledgedPacketId: packet.packetId,
      messageId: packet.payload['messageId'] as String?,
    );
    await transport.sendBytes(ack.toBytes(), peerId: endpointId);
    lastSentPacket = _diagnosticPacket(ack);
    acknowledgementCount += 1;
    _log('ACK sent packet=${packet.type.name}');
  }

  Future<String> _conversationIdForDevice(
    String deviceId,
    String fallback,
  ) async {
    final existing = (await conversations.listConversations())
        .where((conversation) => conversation.participantId == deviceId)
        .toList();
    return existing.isEmpty ? fallback : existing.first.id;
  }

  String _peerName(String endpointId, String fallback) {
    final matches = discoveredPeers.where((peer) => peer.id == endpointId);
    return matches.isEmpty ? fallback : matches.first.name;
  }

  Future<String> _senderUserId() async {
    final userId = currentUserIdProvider?.call();
    if (userId != null && userId.isNotEmpty) return userId;
    return identity.getDeviceId();
  }

  void _updatePeerIdentity(
    String? endpointId,
    String deviceId, {
    String? displayName,
    List<String>? capabilities,
  }) {
    if (endpointId == null) return;
    endpointToDeviceId[endpointId] = deviceId;
    deviceToEndpointId[deviceId] = endpointId;
    final index = discoveredPeers.indexWhere((peer) => peer.id == endpointId);
    if (index == -1) return;
    final peer = discoveredPeers[index];
    discoveredPeers[index] = NearbyPeer(
      id: endpointId,
      name: displayName ?? peer.name,
      connected:
          peer.connected ||
          peerStates[endpointId] == NearbyConnectionState.connected,
      deviceId: deviceId,
      capabilities: capabilities ?? peer.capabilities,
      identityFingerprintHint: peer.identityFingerprintHint,
    );
    _log('identity established endpoint=$endpointId');
  }

  List<String> _capabilitiesFrom(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  DeviceStatus _statusFrom(String value) => DeviceStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => DeviceStatus.normal,
  );

  MessageType _mediaMessageType(String value) => switch (value) {
    'video' => MessageType.video,
    _ => MessageType.image,
  };

  MediaType _mediaType(String value) => switch (value) {
    'video' => MediaType.video,
    _ => MediaType.image,
  };

  String _safeError(Object error) => error is NearbyTransportException
      ? error.message
      : error.toString().replaceFirst('Exception: ', '');

  String? _safeNativeDetails(Object? details) {
    if (details == null) return null;
    const safeKeys = {'statusCode', 'status', 'errorCode', 'operation', 'name'};
    if (details is Map) {
      return details.entries
          .where((entry) => safeKeys.contains(entry.key.toString()))
          .take(8)
          .map((entry) => '${entry.key}=${entry.value}')
          .join(', ');
    }
    final text = details.toString();
    final matches = RegExp(
      r'(?:statusCode\s*[=:]\s*\d+|STATUS_[A-Z0-9_]+)',
    ).allMatches(text).map((match) => match.group(0)!).toSet();
    return matches.isEmpty ? null : matches.join(', ');
  }

  String _diagnosticPacket(RelioPacket packet) => jsonEncode({
    'type': packet.type.name,
    'packetId': packet.packetId,
    'senderDeviceId': packet.senderDeviceId,
  });

  void _log(String message) {
    eventLog.insert(0, '${DateTime.now().toIso8601String()} $message');
    if (eventLog.length > 80) eventLog.removeLast();
    debugPrint('[RELIO][NEARBY] $message');
  }

  void _track(Future<void> operation) {
    late final Future<void> tracked;
    tracked = operation.whenComplete(() => _inFlightOperations.remove(tracked));
    _inFlightOperations.add(tracked);
  }

  void _fail(String message, {String code = 'application_error'}) {
    final safeMessage = message.split(':').first;
    lastError = safeMessage;
    lastErrorCode = code;
    _log('ERROR code=$code category=$safeMessage');
    notifyListeners();
  }

  String _errorCode(Object error) => error is NearbyTransportException
      ? '${error.apiStatusCode ?? error.apiStatusName ?? error.code}'
      : error is String
      ? error
      : error.runtimeType.toString();

  @override
  void dispose() {
    super.dispose();
    unawaited(close());
  }

  Future<void> close() async {
    if (_closed) return;
    _recordSessionStop(
      caller: 'NearbyService.close',
      reason: 'service_dispose',
    );
    _closed = true;
    for (final timer in _identityHandshakeTimeouts.values) {
      timer.cancel();
    }
    _identityHandshakeTimeouts.clear();
    for (final timer in _connectionSoftTimeouts.values) {
      timer.cancel();
    }
    _connectionSoftTimeouts.clear();
    for (final timer in _connectionHardWatchdogs.values) {
      timer.cancel();
    }
    _connectionHardWatchdogs.clear();
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    while (_inFlightOperations.isNotEmpty) {
      try {
        await Future.wait(_inFlightOperations.toList(), eagerError: false);
      } on Object {
        // Cleanup must finish even when a transport callback failed.
      }
    }
    await transport.dispose();
  }
}
