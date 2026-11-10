import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../app/environment.dart';
import '../../data/models/prototype_models.dart';
import '../domain/relio_entities.dart';
import '../identity/owner_context.dart';
import '../diagnostics/diagnostics_log_service.dart';
import '../connectivity/runtime_connectivity.dart';
import '../device/battery_info_service.dart';
import '../media/media_storage_service.dart';
import '../repositories/profile_avatar_repository.dart';
import '../notifications/local_notification_service.dart';
import '../notifications/notification_preview.dart';
import '../presentation/peer_connection_presence.dart';
import '../repositories/local_repositories.dart';
import '../relay/relay_engine.dart';
import '../relay/relay_models.dart';
import '../relay/relay_route_planner.dart';
import '../location/location_service.dart';
import '../location/nearby_map_calculations.dart';
import '../location/nearby_location_quality.dart';
import 'nearby_location_sharing_coordinator.dart';
import 'nearby_transport.dart';
import 'nearby_readiness.dart';
import 'peer_identity_crypto.dart';
import 'nearby_reachability.dart';
import 'relio_packet.dart';

// ประสาน lifecycle ของ Nearby, identity handshake, packet และ Repository
// สถานะ discovery/connection เป็นข้อมูล runtime; device identity จะเชื่อถือได้หลัง handshake
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
    required this.packet,
    required this.publicKey,
    required this.fingerprint,
    required this.wasPinned,
    required this.pinnedMatches,
    required this.previousFingerprint,
  });

  final RelioPacket packet;
  final String publicKey;
  final String fingerprint;
  final bool wasPinned;
  final bool pinnedMatches;
  final String? previousFingerprint;
}

class _QaRelayRouteCheck {
  _QaRelayRouteCheck(this.endpointId, this.destinationHash, this.session);
  final String endpointId;
  final String destinationHash;
  final String? session;
  final result = Completer<({bool connected, String? principal})>();
}

class NearbyService extends ChangeNotifier {
  static final Stopwatch _diagnosticClock = Stopwatch()..start();
  static const _relayRouteModeSetting = 'qa_plaintext_text_route_mode_v2';
  static const _qaTextRelayCapability = RelayPolicy.qaPlaintextTextCapability;
  static const _relayMiddleSetting = 'qa_text_relay_middle_device';
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
    this.profileAvatar,
    this.localNotifications,
    this.relayEngine,
    this.reachabilityRelayAllowed,
    this.backgroundRelayAllowed,
    this.diagnostics,
    this.readRuntimeSnapshot,
    this.batteryInfo,
    this.locationService,
    PeerIdentityCrypto? identityCrypto,
    this.handshakeTimeout = const Duration(seconds: 30),
    this.connectionAttemptTimeout = const Duration(seconds: 35),
    this.incomingApprovalTimeout = const Duration(seconds: 90),
    this.hardNegotiationTimeout = const Duration(seconds: 90),
    this.advertisingStartWatchdog = const Duration(seconds: 12),
  }) : identityCrypto =
           identityCrypto ??
           (transport is MockNearbyTransport
               ? MockPeerIdentityCrypto('mock-local-device')
               : AndroidPeerIdentityCrypto()) {
    identity.profiles.addListener(_onProfileChanged);
    addListener(_updateReachabilityTopology);
    unawaited(_restoreCachedPeerAvatars());
    if (locationService != null) {
      _locationCoordinator = NearbyLocationSharingCoordinator(
        nearbyService: this,
        locationService: locationService!,
        diagnostics: diagnostics,
        initiallyEnabled: false,
        initiallyForeground: false,
        onLocationForDisplay: _onLocalLocationForDisplay,
        onStateChanged: notifyListeners,
      );
    }
  }

  OwnerContext get _owners => conversations is DriftConversationRepository
      ? (conversations as DriftConversationRepository).ownerContext
      : identity.profiles.owners;
  final Map<String, String> _remotePrincipals = {};
  final Map<String, _QaRelayRouteCheck> _qaRelayRouteChecks = {};
  final RelayRoutePlanner _relayRoutePlanner = const RelayRoutePlanner();
  RelayTextRouteMode _textRouteMode = RelayTextRouteMode.directOnly;
  String? _forcedRelayMiddleDeviceId;
  RelayRoutePlan? _lastTextRoutePlan;
  final Set<String> _textSendsInProgress = {};
  final Map<String, Future<void>> _textConversationTails = {};
  Timer? _qaRelayRetryTimer;
  bool _qaRelayRetryRunning = false;
  String? _qaRestrictedDeviceId;
  DateTime? _qaRestrictionExpiresAt;
  Timer? _qaRestrictionExpiry;

  String? get qaRestrictedDeviceId =>
      _qaRestrictionActive ? _qaRestrictedDeviceId : null;
  bool get _qaRestrictionActive =>
      RelioBuildInfo.isTest &&
      _qaRestrictedDeviceId != null &&
      _qaRestrictionExpiresAt?.isAfter(DateTime.now().toUtc()) == true;

  /// מגביל זמנית peer מאומת ב-QA בלבד. המגבלה אינה נוגעת ב-trust/blocked.
  Future<void> setQaDirectLinkRestriction(String? deviceId) async {
    if (!RelioBuildInfo.isTest) {
      throw StateError('QA link restriction is available only in TEST.');
    }
    final id = deviceId?.trim();
    if (id != null && (id.isEmpty || id.length > 128)) {
      throw ArgumentError.value(deviceId, 'deviceId');
    }
    final restrictionWasCleared = id == null && _qaRestrictedDeviceId != null;
    _qaRestrictionExpiry?.cancel();
    _qaRestrictedDeviceId = id;
    _qaRestrictionExpiresAt = id == null
        ? null
        : DateTime.now().toUtc().add(const Duration(minutes: 15));
    if (id != null) {
      _qaRestrictionExpiry = Timer(const Duration(minutes: 15), () {
        _qaRestrictedDeviceId = null;
        _qaRestrictionExpiresAt = null;
        _track(_refreshDiscoveryAfterQaRestriction(reason: 'expired'));
        notifyListeners();
      });
      final endpoint = deviceToEndpointId[id];
      if (endpoint != null &&
          peerStates[endpoint] == NearbyConnectionState.connected) {
        await disconnect(endpoint, reason: 'qa_direct_link_restriction');
      }
    }
    diagnostics?.record(
      'connection',
      id == null
          ? 'qa_direct_link_restriction_disabled'
          : 'qa_direct_link_restriction_enabled',
      operation: 'qaLinkPolicy',
      fields: {'expiresAt': _qaRestrictionExpiresAt?.toIso8601String()},
    );
    notifyListeners();
    if (restrictionWasCleared) {
      await _refreshDiscoveryAfterQaRestriction(reason: 'cleared');
    }
  }

  Future<void> _refreshDiscoveryAfterQaRestriction({
    required String reason,
  }) async {
    if (_closed ||
        _diagnosticRole != NearbyDiagnosticRole.auto ||
        !isAdvertising ||
        hasActiveConnectionAttempts) {
      diagnostics?.record(
        'connection',
        'qa_restriction_discovery_refresh_skipped',
        operation: 'refreshNearbyDiscovery',
        reason: reason,
        fields: {
          'closed': _closed,
          'qaRole': _diagnosticRole.name,
          'advertisingActive': isAdvertising,
          'activeAttempts': hasActiveConnectionAttempts,
        },
      );
      return;
    }
    final starting = _startSessionOperation;
    if (starting != null) await starting;
    if (_closed ||
        _diagnosticRole != NearbyDiagnosticRole.auto ||
        !isAdvertising ||
        hasActiveConnectionAttempts) {
      return;
    }
    diagnostics?.record(
      'connection',
      'qa_restriction_discovery_refresh_started',
      operation: 'refreshNearbyDiscovery',
      reason: reason,
      fields: {'discoveryEpoch': transport.discoveryEpoch},
    );
    if (isDiscovering) await stopDiscovery();
    if (isDiscovering) {
      diagnostics?.record(
        'connection',
        'qa_restriction_discovery_refresh_failed',
        severity: 'warning',
        operation: 'stopDiscovery',
        reason: 'discovery_remained_active',
      );
      return;
    }
    if (_closed ||
        _diagnosticRole != NearbyDiagnosticRole.auto ||
        !isAdvertising ||
        hasActiveConnectionAttempts) {
      return;
    }
    await startDiscovery();
    diagnostics?.record(
      'connection',
      isDiscovering
          ? 'qa_restriction_discovery_refresh_completed'
          : 'qa_restriction_discovery_refresh_failed',
      severity: isDiscovering ? 'info' : 'warning',
      operation: 'startDiscovery',
      reason: reason,
      fields: {'discoveryEpoch': transport.discoveryEpoch},
    );
  }

  RelayTextRouteMode get textRouteMode => _textRouteMode;
  bool get qaPlaintextTextEnabled =>
      RelioBuildInfo.isTest && _textRouteMode != RelayTextRouteMode.directOnly;
  bool get canOpenRemoteTextChat =>
      RelioBuildInfo.isTest && _textRouteMode == RelayTextRouteMode.automatic;

  Future<RelioConversation?> openRemoteTextConversation(String deviceId) =>
      _owners.run(() async {
        final owner = _owners.capture();
        final peer = remoteReachablePeers
            .where((peer) => peer.deviceId == deviceId)
            .firstOrNull;
        if (peer == null ||
            !canOpenRemoteTextChat ||
            (await nearbyDevices.getDevice(deviceId))?.isBlocked == true) {
          return null;
        }
        final principal = await _resolveRemoteTextPrincipal(deviceId);
        _owners.requireCurrent(owner);
        if (principal == null || !canOpenRemoteTextChat) return null;
        return conversations.ensureConversation(
          id: deviceId,
          participantId: deviceId,
          displayName: peer.name,
          participantStatus: DeviceStatus.normal,
          remotePrincipalId: principal,
        );
      });
  String? get forcedRelayMiddleDeviceId => _forcedRelayMiddleDeviceId;
  RelayRoutePlan? get lastTextRoutePlan => _lastTextRoutePlan;

  Future<void> configureTextRouteMode(
    RelayTextRouteMode mode, {
    String? forcedMiddleDeviceId,
  }) async {
    if (!RelioBuildInfo.isTest) {
      throw StateError('Automatic Relay routing is available only in TEST.');
    }
    final middle = forcedMiddleDeviceId?.trim();
    if (mode == RelayTextRouteMode.qaForcedRelay &&
        (middle == null || middle.isEmpty || middle.length > 128)) {
      throw ArgumentError.value(forcedMiddleDeviceId, 'forcedMiddleDeviceId');
    }
    _textRouteMode = mode;
    _forcedRelayMiddleDeviceId = mode == RelayTextRouteMode.qaForcedRelay
        ? middle
        : null;
    _lastTextRoutePlan = null;
    await settings?.setValue(_relayRouteModeSetting, mode.name);
    if (_forcedRelayMiddleDeviceId case final selected?) {
      await settings?.setValue(_relayMiddleSetting, selected);
    } else {
      await settings?.remove(_relayMiddleSetting);
    }
    notifyListeners();
    for (final peer in authenticatedConnectedPeers) {
      _track(sendHello(peerId: peer.endpointId).catchError((Object _) {}));
    }
  }

  Future<String?> _resolveRemoteTextPrincipal(String deviceId) async {
    if (!canOpenRemoteTextChat) return null;
    final owner = _owners.capture();
    final local = await identity.getDeviceId();
    final neighbors = _reachabilityNeighbors;
    final routes =
        _reachability
            .active(
              neighbors.map(_reachabilitySession).toSet(),
              _reachabilityClock.elapsed,
            )
            .where((route) => route.deviceId == deviceId)
            .toList()
          ..sort((a, b) => a.path.length.compareTo(b.path.length));
    final attempted = <String>{};
    for (final route in routes) {
      final peer = neighbors
          .where((peer) => peer.deviceId == route.path.first)
          .firstOrNull;
      if (peer == null ||
          !peer.capabilities.contains(_qaTextRelayCapability) ||
          !attempted.add(peer.endpointId)) {
        continue;
      }
      final reply = await _probeQaRelayEndpoint(
        endpointId: peer.endpointId,
        destinationHash: sha256.convert(utf8.encode(deviceId)).toString(),
        path: [local],
        maxHops: route.path.length - 1,
        resolvePrincipal: true,
      );
      _owners.requireCurrent(owner);
      if (!canOpenRemoteTextChat) return null;
      if (reply.principal != null &&
          remoteReachablePeers.any((peer) => peer.deviceId == deviceId)) {
        return reply.principal;
      }
    }
    return null;
  }

  Future<RelayRoutePlan> planTextRoute(
    String destinationDeviceId, {
    bool preferRelay = false,
    String? expectedPrincipal,
  }) async {
    final sourceDeviceId = await identity.getDeviceId();
    final routeMode = RelioBuildInfo.isTest
        ? _textRouteMode
        : RelayTextRouteMode.directOnly;
    final routeMaxHops = routeMode == RelayTextRouteMode.qaForcedRelay
        ? 2
        : RelayPolicy.qaAutomaticTextMaxHops;
    final plan = await _relayRoutePlanner.plan(
      mode: routeMode,
      sourceDeviceId: sourceDeviceId,
      destinationDeviceId: destinationDeviceId,
      connectedPeers: connectedPeers.where(
        (peer) =>
            identityCrypto is MockPeerIdentityCrypto ||
            _completedIdentityHandshakes.contains(peer.endpointId),
      ),
      forcedMiddleDeviceId: _forcedRelayMiddleDeviceId,
      preferRelay: preferRelay,
      // The origin already holds the recipient principal from its trusted
      // conversation. A relay hop only verifies the destination device route;
      // it must not require each intermediary to have that principal mapped.
      verifyRelay: (middle, destination) async =>
          (expectedPrincipal == null ||
              RelioPacket.validPrincipal(expectedPrincipal)) &&
          await checkQaRelayRoute(
            middleDeviceId: middle,
            destinationDeviceId: destination,
            maxHops: routeMaxHops - 1,
          ),
    );
    _lastTextRoutePlan = plan;
    diagnostics?.record(
      'relay',
      'route_selected',
      peerIdentifier: destinationDeviceId,
      fields: {
        'routeMode': plan.mode.name,
        'routeKind': plan.kind.name,
        if (preferRelay) 'replannedAfterDirectFailure': true,
        'originAlias': DiagnosticsLogService.peerAlias(sourceDeviceId),
        'destinationAlias': DiagnosticsLogService.peerAlias(
          destinationDeviceId,
        ),
        if (plan.middleDeviceId case final middle?)
          'middleAlias': DiagnosticsLogService.peerAlias(middle),
        'reason': ?plan.reason,
      },
    );
    notifyListeners();
    return plan;
  }

  /// ตรวจเส้นทางปลายทางแบบชั่วคราวจาก peer ถัดไป ไม่เก็บ topology เป็นข้อมูลถาวร
  Future<bool> checkQaRelayRoute({
    required String middleDeviceId,
    required String destinationDeviceId,
    int maxHops = RelayPolicy.qaAutomaticTextMaxHops - 1,
    String? expectedPrincipal,
  }) async {
    if (!RelioBuildInfo.isTest ||
        _closed ||
        middleDeviceId == destinationDeviceId ||
        maxHops < 1 ||
        maxHops > RelioPacket.maxQaRelayRouteHops) {
      return false;
    }
    final sourceDeviceId = await identity.getDeviceId();
    if (sourceDeviceId == middleDeviceId ||
        sourceDeviceId == destinationDeviceId) {
      return false;
    }
    final peers = connectedPeers
        .where(
          (peer) =>
              peer.deviceId == middleDeviceId &&
              peer.capabilities.contains('relay-v1') &&
              (relayEngine?.qaPlaintextTextAllowed == null ||
                  peer.capabilities.contains(_qaTextRelayCapability)) &&
              _completedIdentityHandshakes.contains(peer.endpointId),
        )
        .toList();
    if (peers.length != 1) return false;
    final hash = sha256.convert(utf8.encode(destinationDeviceId)).toString();
    final reply = await _probeQaRelayEndpoint(
      endpointId: peers.single.endpointId,
      destinationHash: hash,
      path: [sourceDeviceId],
      maxHops: maxHops,
      resolvePrincipal: expectedPrincipal != null,
    );
    return reply.connected &&
        (expectedPrincipal == null || reply.principal == expectedPrincipal);
  }

  Future<({bool connected, String? principal})> _probeQaRelayEndpoint({
    required String endpointId,
    required String destinationHash,
    required List<String> path,
    required int maxHops,
    bool resolvePrincipal = false,
  }) async {
    const unavailable = (connected: false, principal: null);
    if (_closed ||
        !_completedIdentityHandshakes.contains(endpointId) ||
        maxHops < 1 ||
        maxHops > RelioPacket.maxQaRelayRouteHops ||
        path.isEmpty ||
        path.length > RelioPacket.maxQaRelayRouteHops ||
        path.toSet().length != path.length) {
      return unavailable;
    }
    final checkId = const Uuid().v4();
    final pending = _QaRelayRouteCheck(
      endpointId,
      destinationHash,
      _connectionTraces[endpointId],
    );
    _qaRelayRouteChecks[checkId] = pending;
    try {
      await _sendApplicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: await identity.getDeviceId(),
          senderUserId: await _senderUserId(),
          displayName: await identity.getDisplayName(),
          status: await currentStatus(),
          qaRelayCheckId: checkId,
          qaRelayDestinationHash: destinationHash,
          qaRelayPath: path,
          qaRelayMaxHops: maxHops,
          qaRelayResolvePrincipal: resolvePrincipal ? true : null,
        ),
        peerId: endpointId,
      );
      final confirmed = await pending.result.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => unavailable,
      );
      return confirmed.connected &&
              !_closed &&
              _connectionTraces[endpointId] == pending.session &&
              authenticatedConnectedPeers.any(
                (peer) =>
                    peer.endpointId == endpointId &&
                    peer.capabilities.contains('relay-v1'),
              )
          ? confirmed
          : unavailable;
    } on Object {
      return unavailable;
    } finally {
      _qaRelayRouteChecks.remove(checkId);
    }
  }

  final Map<String, int> _remotePrincipalEpochs = {};
  final Map<String, int> _remoteProfileRevisions = {};
  static const _privateTypes = {
    RelioPacketType.textMessage,
    RelioPacketType.locationMessage,
    RelioPacketType.mediaMetadata,
    RelioPacketType.mediaAck,
    RelioPacketType.readReceipt,
  };
  bool _isPrivate(RelioPacket packet) =>
      _privateTypes.contains(packet.type) ||
      (packet.type == RelioPacketType.ack &&
          (packet.payload['messageId'] != null ||
              _packetMessageIds.containsKey(packet.payload['packetId'])));

  void _onProfileChanged() {
    refreshReachabilityConsent();
    _remoteAvatarPaths.clear();
    unawaited(_restoreCachedPeerAvatars());
    notifyListeners();
    if (connectedPeers.isEmpty) return;
    _track(
      _owners
          .run(() async {
            for (final peer in connectedPeers.toList()) {
              await sendHello(peerId: peer.endpointId);
              await _announceLocalAvatar(peer.endpointId);
            }
          })
          .catchError((Object _) {}),
    );
  }

  Future<String> _activePrincipal() async {
    final owner = _owners.capture();
    final id = await identity.profiles.principalFor(owner);
    _owners.requireCurrent(owner);
    return id;
  }

  Future<bool> _validPrivateRecipient(
    String endpoint,
    RelioPacket packet,
  ) async {
    final owner = _owners.capture();
    final local = await _activePrincipal();
    _owners.requireCurrent(owner);
    if (!RelioPacket.validPrincipal(packet.senderPrincipal) ||
        packet.recipientPrincipal != local ||
        _remotePrincipals[endpoint] != packet.senderPrincipal) {
      return false;
    }
    if (packet.type == RelioPacketType.ack ||
        packet.type == RelioPacketType.mediaAck ||
        packet.type == RelioPacketType.readReceipt) {
      final id =
          packet.payload['messageId'] as String? ??
          _packetMessageIds[packet.payload['packetId']];
      final message = id == null ? null : await messages.getMessage(id);
      if (message?.conversationId == null ||
          conversations is! DriftConversationRepository) {
        return false;
      }
      final remote = await (conversations as DriftConversationRepository)
          .remotePrincipalForConversation(message!.conversationId!);
      _owners.requireCurrent(owner);
      return remote == packet.senderPrincipal;
    }
    return true;
  }

  Future<String?> _sendApplicationBytes(
    RelioPacket packet, {
    String? peerId,
    RelioPacket? replyTo,
  }) async {
    final owner = _owners.capture();
    final local = await _activePrincipal();
    String? recipient;
    if (_isPrivate(packet)) {
      if (peerId == null) throw const OwnerChangedException();
      if (replyTo != null) {
        if (!await _validPrivateRecipient(peerId, replyTo)) {
          throw const OwnerChangedException();
        }
        recipient = replyTo.senderPrincipal;
      } else {
        final messageId = packet.payload['messageId'] as String?;
        final message = messageId == null
            ? null
            : await messages.getMessage(messageId);
        if (message?.conversationId == null ||
            conversations is! DriftConversationRepository) {
          throw const OwnerChangedException();
        }
        recipient = await (conversations as DriftConversationRepository)
            .remotePrincipalForConversation(message!.conversationId!);
      }
      if (!RelioPacket.validPrincipal(recipient) ||
          _remotePrincipals[peerId] != recipient) {
        throw const OwnerChangedException();
      }
    }
    final announcement =
        packet.type == RelioPacketType.hello ||
        packet.type == RelioPacketType.deviceStatus;
    final profile = announcement
        ? await identity.profiles.forPrincipal(local)
        : null;
    _owners.requireCurrent(owner);
    final outgoing = packet.withPrincipals(
      local,
      recipient,
      profileRevision: profile?.revision,
    );
    final wire = profile == null
        ? outgoing
        : RelioPacket(
            protocolVersion: outgoing.protocolVersion,
            packetId: outgoing.packetId,
            type: outgoing.type,
            senderDeviceId: outgoing.senderDeviceId,
            senderUserId: outgoing.senderUserId,
            createdAt: outgoing.createdAt,
            senderPrincipal: local,
            recipientPrincipal: recipient,
            payload: {
              ...outgoing.payload,
              'displayName': profile.displayName,
              'principalGeneration': owner.generation,
            },
          );
    _owners.requireCurrent(owner);
    return transport.sendBytes(
      wire.toBytes(),
      peerId: peerId,
      capturePayloadDiagnostics:
          packet.type == RelioPacketType.mediaMetadata ||
          packet.type == RelioPacketType.mediaAck,
    );
  }

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
  final ProfileAvatarRepository? profileAvatar;
  final LocalNotificationSink? localNotifications;
  final RelayEngine? relayEngine;
  final Future<bool> Function()? reachabilityRelayAllowed;
  final bool Function()? backgroundRelayAllowed;
  final DiagnosticsLogService? diagnostics;
  final Future<RuntimeConnectivitySnapshot> Function()? readRuntimeSnapshot;
  final BatteryInfoService? batteryInfo;
  final LocationService? locationService;
  NearbyLocationSharingCoordinator? _locationCoordinator;
  NearbyLocationSharingCoordinator? get locationCoordinator =>
      _locationCoordinator;
  LocationData? _lastLiveLocation;
  LocationData? get lastLiveLocation => _lastLiveLocation;
  bool? _liveLocationSharingConsent;
  bool? get liveLocationSharingConsent => _liveLocationSharingConsent;
  bool _developerLocationSharingOverrideEnabled = true;
  bool get developerLocationSharingOverrideEnabled =>
      _developerLocationSharingOverrideEnabled;
  bool _locationSettingsLoaded = false;
  bool get locationSettingsLoaded => _locationSettingsLoaded;
  bool get liveLocationSharingEnabled =>
      _liveLocationSharingConsent == true &&
      _developerLocationSharingOverrideEnabled;
  bool _localSosActive = false;
  final PeerIdentityCrypto identityCrypto;
  final Duration handshakeTimeout;
  final Duration incomingApprovalTimeout;

  /// Google ระบุ callback ผลลัพธ์ แต่ไม่ได้กำหนด maximum resolution time
  /// ค่านี้จึงมีไว้กัน native attempt ค้างถาวร ไม่ใช่ UX timeout
  final Duration hardNegotiationTimeout;
  final Duration connectionAttemptTimeout;
  // Google Nearby บาง Bluetooth stack ค้างระหว่าง advertising; discovery
  // แยกทำงานได้ จึงต้องไม่ปล่อยให้ peer ที่ประกาศอยู่แล้วหายไปจากการค้นหา
  final Duration advertisingStartWatchdog;
  NearbyReadiness? readiness;
  NearbyDiagnosticRole _diagnosticRole = NearbyDiagnosticRole.auto;
  NearbyApplicationState? _transition;
  bool _sessionFailed = false;
  String? _readinessSignature;
  String appLifecycleState = 'unknown';
  String screenRoute = 'unknown';
  Future<void>? _startSessionOperation;
  Future<void>? _disconnectDiscoveryRecovery;
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
    final previousLifecycle = appLifecycleState;
    if (appLifecycleState != lifecycleState) {
      for (final record in _activeTransportAttempts.values) {
        record['lifecycleChanged'] = true;
      }
    }
    appLifecycleState = lifecycleState;
    if (previousLifecycle != lifecycleState) refreshReachabilityConsent();
    screenRoute = route;
    unawaited(_locationCoordinator?.setForeground(lifecycleState == 'resumed'));
    if (lifecycleState == 'resumed' && previousLifecycle != 'resumed') {
      unawaited(_locationCoordinator?.onAppResumed());
    }
    final allowBackgroundRelay = backgroundRelayAllowed?.call() ?? false;
    if (RelioBuildInfo.isTest &&
        (lifecycleState == 'resumed' || allowBackgroundRelay) &&
        transport is! MockNearbyTransport) {
      _qaRelayRetryTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
        unawaited(_retryQaPendingText());
      });
    } else {
      _qaRelayRetryTimer?.cancel();
      _qaRelayRetryTimer = null;
    }
    if (RelioBuildInfo.isTest &&
        (lifecycleState == 'resumed' || allowBackgroundRelay)) {
      unawaited(_retryQaPendingText());
    }
  }

  Future<void> _retryQaPendingText() async {
    if (!RelioBuildInfo.isTest ||
        _closed ||
        _qaRelayRetryRunning ||
        (appLifecycleState != 'resumed' &&
            appLifecycleState != 'unknown' &&
            !(backgroundRelayAllowed?.call() ?? false))) {
      return;
    }
    _qaRelayRetryRunning = true;
    try {
      await _owners.run(() async {
        for (final conversation in await conversations.listConversations()) {
          final pending = (await messages.listMessages(conversation.id))
              .where(
                (message) =>
                    message.outgoing &&
                    message.type == MessageType.text &&
                    (message.status == DeliveryStatus.pending ||
                        message.status == DeliveryStatus.nearbySent),
              )
              .take(20);
          for (final message in pending) {
            await sendMessage(message);
          }
        }
        await relayEngine?.forwardPending();
      });
    } on Object {
      // เปลี่ยน owner ระหว่าง retry แล้วรอรอบใหม่ โดยไม่ย้าย ownership
    } finally {
      _qaRelayRetryRunning = false;
    }
  }

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
  final Map<String, Set<String>> _pendingSosAcks = {};
  final Map<String, String> _sosEventIdsByPacketId = {};
  final Map<String, int> _localSosRevisions = {};
  final Map<String, int> _receivedSosRevisions = {};
  final Map<String, Future<void>> _sosReceiveQueues = {};
  Future<void> _sosRevisionQueue = Future<void>.value();
  final Set<String> _pendingConversationFlushes = {};
  final Set<String> _incomingTextMessagesInProgress = {};
  final Map<String, RelioPacket> _mediaMetadataByPayload = {};
  final Map<String, OwnerSnapshot> _mediaMetadataOwners = {};
  final Map<String, Future<void>> _incomingMediaOperations = {};
  final Map<String, NearbyFilePayloadEvent> _mediaFilesByPayload = {};
  final Map<String, String> _payloadTransferIds = {};
  final Map<String, Stopwatch> _mediaPipelineClocks = {};
  final Map<String, Stopwatch> _mediaAckClocks = {};
  final Map<String, int> _mediaProgressMilestones = {};
  final Map<String, Map<String, Object?>> _avatarMetadataByPayload = {};
  final Map<String, String> _remoteAvatarPaths = {};
  final Map<String, DateTime> _avatarRequestAt = {};
  final Set<String> _avatarTransfersInProgress = {};
  final Map<String, String> endpointToDeviceId = {};
  final Map<String, String> deviceToEndpointId = {};
  final Map<String, NearbyConnectionState> peerStates = {};
  final Map<String, NearbyConnectionEvent> pendingConnectionRequests = {};
  final Set<String> _approvedConnectionEndpoints = {};
  final Set<String> _provisionalConnectionEndpoints = {};
  final Map<String, NearbyConnectionEvent> _provisionalIncomingRequests = {};
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
  final Set<String> _nativeAcceptInFlight = {};
  final Set<String> _retiredConnectionEndpoints = {};
  final Map<String, Future<void>> _disconnectTasks = {};
  final Map<String, int> _connectionCancellationEpochs = {};
  final Set<String> _incomingSosNotificationClaims = {};
  final Map<String, _AppDisconnectRequest> _appDisconnectRequests = {};
  final Set<String> _automaticConnectionAttempts = {};
  final Map<String, String> _reconnectFingerprintByEndpoint = {};
  final Map<String, String> _fingerprintEndpointReservations = {};
  final Map<String, NearbyPeer> _endpointLifecycle = {};
  final Map<String, bool> _freshEndpointRetryByFingerprint = {};
  final Set<String> _freshEndpointRetryEndpoints = {};
  final List<Map<String, Object?>> _transportAttemptResults = [];
  final Map<String, Map<String, Object?>> _activeTransportAttempts = {};
  final Map<String, DateTime> _nextReconnectAt = {};
  final Map<String, int> _reconnectAttemptCounts = {};
  final Map<String, DateTime> _receivedChallengeExpiries = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, Timer> _secondaryInitiatorFallbackTimers = {};
  final Set<String> _secondaryInitiatorFingerprints = {};
  final Map<String, DeviceStatus> peerStatuses = {};
  final Map<String, bool> _peerRescueActive = {};
  final Map<String, DateTime> _lastPeerStatusUpdatedAt = {};
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
  bool _discoveryPausedForNegotiation = false;
  final BatteryPublishPolicy _batteryPublishPolicy =
      const BatteryPublishPolicy();
  BatterySnapshot? _lastPublishedBattery;
  StreamSubscription<void>? _batteryStateSubscription;
  Timer? _batteryRefreshTimer;

  void startBatteryMetadataUpdates() {
    final source = batteryInfo;
    if (source == null || _batteryStateSubscription != null) return;
    _batteryStateSubscription = source.stateChanges.listen((_) {
      unawaited(_publishBatteryMetadata());
    });
    _batteryRefreshTimer = Timer.periodic(
      _batteryPublishPolicy.refreshInterval,
      (_) => unawaited(_publishBatteryMetadata()),
    );
  }

  void stopBatteryMetadataUpdates() {
    _batteryRefreshTimer?.cancel();
    _batteryRefreshTimer = null;
    unawaited(_batteryStateSubscription?.cancel());
    _batteryStateSubscription = null;
  }

  Future<void> _publishBatteryMetadata() async {
    final source = batteryInfo;
    if (source == null || connectedPeers.isEmpty) return;
    final battery = await source.readSnapshot();
    if (battery == null ||
        !_batteryPublishPolicy.shouldPublish(
          previous: _lastPublishedBattery,
          current: battery,
          now: DateTime.now(),
        )) {
      return;
    }
    final deviceId = await identity.getDeviceId();
    final status = await currentStatus();
    final rescueActive =
        settings != null &&
        await settings!.getBool('rescue_mode', defaultValue: false);
    for (final peer in connectedPeers) {
      if (!_completedIdentityHandshakes.contains(peer.endpointId)) continue;
      await _sendPacket(
        RelioPacket.deviceStatus(
          senderDeviceId: deviceId,
          senderUserId: await _senderUserId(),
          displayName: await identity.getDisplayName(),
          status: status,
          rescueActive: rescueActive,
          batteryLevel: battery.level,
          isCharging: battery.isCharging,
          batteryUpdatedAt: battery.updatedAt,
          deviceModel: _deviceModel,
        ),
        description: 'peer battery update',
        peerId: peer.endpointId,
      );
    }
    _lastPublishedBattery = battery;
  }

  Future<void> publishMapLocation(
    LocationData location, {
    String? targetEndpointId,
  }) async {
    if (!NearbyMapCalculations.isValidPoint(
      location.latitude,
      location.longitude,
    )) {
      return;
    }
    final deviceId = await identity.getDeviceId();
    final status = await currentStatus();
    final rescueActive =
        settings != null &&
        await settings!.getBool('rescue_mode', defaultValue: false);
    final battery = await batteryInfo?.readSnapshot();
    final targets = targetEndpointId != null
        ? connectedPeers.where((peer) => peer.endpointId == targetEndpointId)
        : connectedPeers;
    for (final peer in targets) {
      if (!_completedIdentityHandshakes.contains(peer.endpointId)) continue;
      await _sendPacket(
        RelioPacket.deviceStatus(
          senderDeviceId: deviceId,
          senderUserId: await _senderUserId(),
          displayName: await identity.getDisplayName(),
          status: status,
          rescueActive: rescueActive,
          batteryLevel: battery?.level,
          isCharging: battery?.isCharging,
          batteryUpdatedAt: battery?.updatedAt,
          latitude: location.latitude,
          longitude: location.longitude,
          locationAccuracy: location.accuracyMeters,
          locationCapturedAt: location.capturedAt,
          deviceModel: _deviceModel,
        ),
        description: 'shared nearby location',
        peerId: peer.endpointId,
      );
    }
  }

  Future<void> setLiveLocationConsent(bool enabled) async {
    if (_liveLocationSharingConsent == enabled) return;
    _liveLocationSharingConsent = enabled;
    await settings?.setBool('nearby_live_location_enabled', enabled);
    await _reconcileLiveLocationSharing();
  }

  Future<void> setDeveloperLocationSharingOverride(bool enabled) async {
    if (!RelioBuildInfo.developerDiagnosticsEnabled) {
      throw StateError('Developer location control is unavailable.');
    }
    if (_developerLocationSharingOverrideEnabled == enabled) return;
    _developerLocationSharingOverrideEnabled = enabled;
    // ปิด stream ก่อนเขียนค่า เพื่อให้ OFF หยุดแชร์ทันที
    await _reconcileLiveLocationSharing();
    await settings?.setBool('nearby_live_location_dev_override', enabled);
  }

  Future<void> _reconcileLiveLocationSharing() async {
    await _locationCoordinator?.setEnabled(liveLocationSharingEnabled);
    notifyListeners();
  }

  Future<void> setLocalSosActive(bool active) async {
    if (_localSosActive == active) return;
    _localSosActive = active;
    await _locationCoordinator?.setLocalSosActive(active);
  }

  void _onLocalLocationForDisplay(LocationData location) {
    _lastLiveLocation = location;
    notifyListeners();
  }

  NearbyTransportTestMode get transportTestMode => transport.testMode;

  NearbyDiagnosticRole get diagnosticRole => _diagnosticRole;

  Future<void> configureDiagnosticRole(NearbyDiagnosticRole role) async {
    if (!NearbyTransportTestMode.isAvailableIn(RelioBuildInfo.environment) ||
        !RelioBuildInfo.developerDiagnosticsEnabled) {
      throw StateError('Nearby role diagnostics are unavailable.');
    }
    if (hasActiveConnectionAttempts || connectedPeers.isNotEmpty) {
      throw StateError('Finish Nearby connections before changing roles.');
    }
    if (compatibilityModeActive) {
      throw StateError('Disable Bluetooth Classic before changing roles.');
    }

    // รอ startup reconciliation เดิมก่อน เพื่อไม่ให้มันเปิดอีกฝั่งทับ role QA
    final pendingStart = _startSessionOperation;
    if (pendingStart != null) await pendingStart;

    await stopDiscovery();
    await stopAdvertising();
    _diagnosticRole = role;
    switch (role) {
      case NearbyDiagnosticRole.auto:
        await startAdvertising();
        if (isAdvertising) await startDiscovery();
        break;
      case NearbyDiagnosticRole.advertiserOnly:
        await startAdvertising();
        break;
      case NearbyDiagnosticRole.discovererOnly:
        await startDiscovery();
        break;
      case NearbyDiagnosticRole.stopped:
        break;
    }
    diagnostics?.record(
      'nearby',
      'qa_nearby_role_selected',
      operation: 'configureDiagnosticRole',
      fields: {
        'role': role.name,
        'advertising': isAdvertising,
        'discovery': isDiscovering,
        'strategy': transport.strategyName,
      },
    );
    notifyListeners();
  }

  bool get compatibilityFallbackAvailable =>
      transport is CompatibilityTransport;

  bool get compatibilityModeActive =>
      transport is CompatibilityTransport &&
      (transport as CompatibilityTransport).compatibilityModeActive;

  bool get _diagnosticRoleReady => switch (_diagnosticRole) {
    NearbyDiagnosticRole.auto => isAdvertising && isDiscovering,
    NearbyDiagnosticRole.advertiserOnly => isAdvertising && !isDiscovering,
    NearbyDiagnosticRole.discovererOnly => isDiscovering && !isAdvertising,
    NearbyDiagnosticRole.stopped => !isAdvertising && !isDiscovering,
  };

  Future<void> activateCompatibilityMode({
    required bool serverRole,
    bool bondedOnly = false,
  }) async {
    if (transport is! CompatibilityTransport) return;
    await (transport as CompatibilityTransport).activateCompatibilityMode(
      serverRole: serverRole,
      bondedOnly: bondedOnly,
    );
    _sessionFailed = false;
    lastError = null;
    lastErrorCode = null;
    notifyListeners();
  }

  Future<List<BondedBluetoothDevice>> bondedBluetoothDevices() async {
    if (transport is! CompatibilityTransport) return const [];
    return (transport as CompatibilityTransport).bondedBluetoothDevices();
  }

  Map<String, Object?> _radioSnapshotFields() => {
    'bluetoothEnabled': readiness?.bluetoothEnabled,
    'wifiEnabled': readiness?.wifiEnabled,
    'locationEnabled': readiness?.locationEnabled,
    'discoveryActive': isDiscovering,
    'advertisingActive': isAdvertising,
    'activeConnectionAttempts': activeConnectionAttempts,
    'pendingIncomingRequests': pendingConnectionRequests.length,
    'appLifecycleState': appLifecycleState,
    'androidApi': readiness?.policy.sdkInt,
    'googlePlayServicesVersionName':
        nativeTransportSnapshot['googlePlayServicesVersionName'],
    'googlePlayServicesVersionCode':
        nativeTransportSnapshot['googlePlayServicesVersionCode'],
    'nearbyLibraryVersion': nativeTransportSnapshot['nearbyLibraryVersion'],
    'strategy': transport.strategyName,
    'transportTestMode': transport.testMode.diagnosticName,
    'discoveryEpoch': transport.discoveryEpoch,
  };

  List<Map<String, Object?>> get endpointLifecycleSnapshot => _endpointLifecycle
      .values
      .map((peer) {
        final age = peer.foundAt == null
            ? null
            : DateTime.now().toUtc().difference(peer.foundAt!).inMilliseconds;
        return {
          'endpointAlias': DiagnosticsLogService.peerAlias(peer.endpointId),
          'discoveryEpoch': peer.discoveryEpoch,
          'foundAt': peer.foundAt?.toIso8601String(),
          'lastSeenAt': peer.lastSeenAt?.toIso8601String(),
          'lostAt': peer.lostAt?.toIso8601String(),
          'endpointAgeMs': age,
          'isCurrent':
              peer.isCurrent &&
              !peer.isLost &&
              peer.discoveryEpoch == transport.discoveryEpoch,
          'isMarkedLost': peer.isLost,
          'stablePeerHintAvailable': peer.identityFingerprintHint != null,
        };
      })
      .toList(growable: false);

  List<Map<String, Object?>> get transportAttemptResults =>
      _transportAttemptResults
          .map((record) => Map<String, Object?>.unmodifiable(record))
          .toList(growable: false);

  void clearTransportTestResults() {
    _transportAttemptResults.clear();
    diagnostics?.record('nearby', 'transport_test_results_cleared');
    notifyListeners();
  }

  void _beginTransportAttempt(String endpointId, {required String role}) {
    final traceId = _connectionTraces[endpointId];
    if (traceId == null) return;
    final peer =
        _endpointLifecycle[endpointId] ??
        discoveredPeers
            .where((candidate) => candidate.endpointId == endpointId)
            .firstOrNull;
    final started = _connectionStartedAt[endpointId] ?? DateTime.now().toUtc();
    _activeTransportAttempts[endpointId] = <String, Object?>{
      'attemptId': traceId.substring(0, 4).toUpperCase(),
      'transportTestMode': transport.testMode.diagnosticName,
      'startTime': started.toIso8601String(),
      'endTime': null,
      'role': role,
      'endpointAlias': DiagnosticsLogService.peerAlias(endpointId),
      'endpointEpoch': peer?.discoveryEpoch,
      'endpointCurrentAtRequest':
          peer != null &&
          peer.isCurrent &&
          !peer.isLost &&
          peer.discoveryEpoch == transport.discoveryEpoch,
      'endpointAgeMs': peer?.foundAt == null
          ? null
          : started.difference(peer!.foundAt!).inMilliseconds,
      'requestTaskResult': role == 'initiator' ? 'pending' : 'not_applicable',
      'acceptTaskResult': role == 'responder' ? 'pending' : 'not_applicable',
      'nativeStatusCode': null,
      'nativeStatusName': null,
      'connected': false,
      'elapsedMs': null,
      'endpointLostDuringAttempt': false,
      'discoveryVisibility': 'visible',
      'discoveryActiveDuringNegotiation': isDiscovering,
      'advertisingActiveDuringNegotiation': isAdvertising,
      'lifecycleChanged': false,
      'sessionRestarted': false,
      'timelineMs': <String, int>{'attemptStarted': 0},
    };
  }

  void _markTransportPhase(String endpointId, String phase) {
    final record = _activeTransportAttempts[endpointId];
    if (record == null) return;
    final started = DateTime.tryParse(record['startTime']! as String);
    if (started == null) return;
    final timeline = record['timelineMs']! as Map<String, int>;
    timeline[phase] = DateTime.now().toUtc().difference(started).inMilliseconds;
  }

  void _finishTransportAttempt(
    String endpointId, {
    required bool connected,
    int? nativeStatusCode,
    String? nativeStatusName,
    bool endpointLost = false,
  }) {
    final record = _activeTransportAttempts.remove(endpointId);
    if (record == null) return;
    final start = DateTime.tryParse(record['startTime']! as String);
    final end = DateTime.now().toUtc();
    record
      ..['endTime'] = end.toIso8601String()
      ..['connected'] = connected
      ..['nativeStatusCode'] = nativeStatusCode
      ..['nativeStatusName'] = nativeStatusName
      ..['endpointLostDuringAttempt'] = endpointLost
      ..['elapsedMs'] = start == null
          ? null
          : end.difference(start).inMilliseconds;
    _transportAttemptResults.insert(0, Map<String, Object?>.from(record));
    if (_transportAttemptResults.length > 5) {
      _transportAttemptResults.removeRange(5, _transportAttemptResults.length);
    }
    notifyListeners();
  }

  bool isEndpointCurrent(String endpointId) {
    final peer = discoveredPeers
        .where((candidate) => candidate.endpointId == endpointId)
        .firstOrNull;
    return peer != null &&
        !peer.isLost &&
        peer.isCurrent &&
        peer.discoveryEpoch == transport.discoveryEpoch;
  }

  Future<void> configureTransportTestMode(NearbyTransportTestMode mode) async {
    if (!NearbyTransportTestMode.isAvailableIn(RelioBuildInfo.environment) ||
        !RelioBuildInfo.developerDiagnosticsEnabled) {
      throw StateError('Nearby transport diagnostics are unavailable.');
    }
    if (hasActiveConnectionAttempts || connectedPeers.isNotEmpty) {
      throw StateError('Finish Nearby connections before changing mode.');
    }
    final wasAdvertising = isAdvertising;
    final wasDiscovering = isDiscovering;
    await stopDiscovery();
    await stopAdvertising();
    await transport.configureTestMode(mode);
    if (wasAdvertising) await startAdvertising();
    if (wasDiscovering) await startDiscovery();
    await _captureTransportSnapshot();
    diagnostics?.record(
      'nearby',
      'transport_test_mode_selected',
      fields: {
        'transportTestMode': mode.diagnosticName,
        'strategy': mode.strategyName,
      },
    );
    notifyListeners();
  }

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

  List<NearbyPeer> get authenticatedConnectedPeers => connectedPeers
      .where(
        (peer) =>
            peer.deviceId != null &&
            _completedIdentityHandshakes.contains(peer.endpointId),
      )
      .toList(growable: false);

  int get connectedPeerCount =>
      authenticatedConnectedPeers.map((peer) => peer.deviceId!).toSet().length;

  final _reachability = NearbyReachabilityTable();
  final _reachabilityClock = Stopwatch()..start();
  Set<String> _reachabilityTopology = {};
  Timer? _reachabilityPublishTimer;
  Timer? _reachabilityExpiryTimer;
  var _reachabilitySequence = 0;
  var _reachabilityPublishing = false;
  var _reachabilityDirty = false;
  final _advertisedReachability = <String>{};

  List<NearbyPeer> get _reachabilityNeighbors => authenticatedConnectedPeers
      .where(
        (peer) =>
            deviceToEndpointId[peer.deviceId] == peer.endpointId &&
            _connectionTraces.containsKey(peer.endpointId) &&
            peer.capabilities.contains(nearbyReachabilityCapability),
      )
      .toList();

  String _reachabilitySession(NearbyPeer peer) =>
      _connectionTraces[peer.endpointId]!;

  List<NearbyReachablePeer> get remoteReachablePeers {
    final direct = authenticatedConnectedPeers
        .map((peer) => peer.deviceId)
        .toSet();
    return NearbyReachabilityTable.best(
      _reachability
          .active(
            _reachabilityNeighbors.map(_reachabilitySession).toSet(),
            _reachabilityClock.elapsed,
          )
          .where((route) => !direct.contains(route.deviceId)),
    ).map((route) => route.peer).toList(growable: false);
  }

  /// Currently active routes from authenticated sessions, excluding expired
  /// leases. Used by UI to describe live reachability rather than send history.
  List<NearbyReachabilityRoute> get activeReachabilityRoutes {
    final sessions = _reachabilityNeighbors.map(_reachabilitySession).toSet();
    return NearbyReachabilityTable.best(
      _reachability.active(sessions, _reachabilityClock.elapsed),
    );
  }

  int get reachablePeerCount =>
      connectedPeerCount + remoteReachablePeers.length;

  void _updateReachabilityTopology() {
    if (_closed) return;
    final sessions = _reachabilityNeighbors.map(_reachabilitySession).toSet();
    final topology = {
      ...sessions,
      for (final peer in authenticatedConnectedPeers)
        'direct:${peer.deviceId}:${peer.name}',
    };
    if (setEquals(topology, _reachabilityTopology)) return;
    _reachabilityTopology = topology;
    _reachability.retainSessions(sessions);
    _advertisedReachability.retainAll(sessions);
    _scheduleReachabilityExpiry();
    refreshReachabilityConsent();
  }

  void refreshReachabilityConsent() {
    if (_closed || reachabilityRelayAllowed == null) return;
    _reachabilityPublishTimer?.cancel();
    _reachabilityDirty = true;
    if (_reachabilityNeighbors.isEmpty || _reachabilityPublishing) return;
    _reachabilityPublishTimer = Timer(
      const Duration(milliseconds: 150),
      () => _track(_publishReachability()),
    );
  }

  void _scheduleReachabilityExpiry() {
    _reachabilityExpiryTimer?.cancel();
    final now = _reachabilityClock.elapsed;
    Duration? next;
    for (final route in _reachability.active(
      _reachabilityNeighbors.map(_reachabilitySession).toSet(),
      now,
    )) {
      if (next == null || route.expiresAt < next) next = route.expiresAt;
    }
    if (next == null) return;
    _reachabilityExpiryTimer = Timer(next - now, () {
      notifyListeners();
      _scheduleReachabilityExpiry();
      refreshReachabilityConsent();
    });
  }

  Future<void> _publishReachability() async {
    _reachabilityPublishing = true;
    _reachabilityDirty = false;
    try {
      if (reachabilityRelayAllowed == null) return;
      final local = await identity.getDeviceId();
      final allowed =
          await reachabilityRelayAllowed!() &&
          (appLifecycleState == 'resumed' ||
              appLifecycleState == 'unknown' ||
              backgroundRelayAllowed?.call() == true);
      if (_closed || _reachabilityDirty) return;
      final neighbors = _reachabilityNeighbors;
      final now = _reachabilityClock.elapsed;
      final candidates = [
        if (allowed)
          for (final peer in authenticatedConnectedPeers)
            if (peer.deviceId != local &&
                NearbyReachabilityRoute.validId(peer.deviceId) &&
                peer.name.trim().isNotEmpty)
              NearbyReachabilityRoute(
                [peer.deviceId!],
                peer.name.length > 80 ? peer.name.substring(0, 80) : peer.name,
                now + nearbyReachabilityLease,
              ),
        if (allowed)
          ..._reachability
              .active(neighbors.map(_reachabilitySession).toSet(), now)
              .where(
                (route) =>
                    route.path.length < nearbyReachabilityMaxHops &&
                    route.expiresAt - now > const Duration(seconds: 1),
              ),
      ];
      final sequence = ++_reachabilitySequence;
      await Future.wait(
        neighbors.map((peer) async {
          final session = _reachabilitySession(peer);
          final routes = NearbyReachabilityTable.best(
            candidates.where((route) => !route.path.contains(peer.deviceId)),
          ).take(nearbyReachabilityMaxRoutes).toList();
          if (routes.isEmpty && !_advertisedReachability.contains(session)) {
            return;
          }
          // เก็บ lease เดิมเมื่อส่งต่อ เพื่อให้เส้นทางปลายทางหมดอายุได้จริง
          if (routes.isNotEmpty) _advertisedReachability.add(session);
          try {
            await transport.sendBytes(
              RelioPacket(
                protocolVersion: 1,
                packetId: const Uuid().v4(),
                type: RelioPacketType.reachabilitySnapshot,
                senderDeviceId: local,
                senderUserId: local,
                createdAt: DateTime.now().toUtc(),
                payload: {
                  'sequence': sequence,
                  'routes': routes.map((route) => route.encode(now)).toList(),
                },
              ).toBytes(),
              peerId: peer.endpointId,
            );
            if (routes.isEmpty) _advertisedReachability.remove(session);
          } on Object {
            // Snapshot ถัดไปหรือ lease expiry จะจัดการเมื่อส่งไม่สำเร็จ
          }
        }),
      );
    } on Object {
      // หากอ่าน consent หรือ identity ไม่ได้ ให้ lease เดิมหมดอายุเอง
    } finally {
      _reachabilityPublishing = false;
      if (!_closed && _reachabilityNeighbors.isNotEmpty) {
        if (_reachabilityDirty) {
          refreshReachabilityConsent();
        } else if (_advertisedReachability.isNotEmpty) {
          _reachabilityPublishTimer = Timer(
            const Duration(seconds: 10),
            () => _track(_publishReachability()),
          );
        }
      }
    }
  }

  Future<void> _receiveReachability(String endpoint, RelioPacket packet) async {
    // เส้นทางที่อยู่ไกลอาศัยคำรายงานจาก next hop ที่ยืนยันแล้ว
    // จึงใช้เพื่อแสดง reachability เท่านั้น ไม่สร้าง trust pin หรือเส้นทางแชต
    final peer = _reachabilityNeighbors
        .where((peer) => peer.endpointId == endpoint)
        .firstOrNull;
    if (peer == null) return;
    final session = _reachabilitySession(peer);
    final now = _reachabilityClock.elapsed;
    final local = await identity.getDeviceId();
    if (!_isCurrentConnectionSession(endpoint, session) ||
        !isEndpointVerifiedConnected(endpoint)) {
      return;
    }
    final routes = [
      for (final raw in packet.payload['routes']! as List)
        ?NearbyReachabilityRoute.decode(
          raw,
          sender: packet.senderDeviceId,
          local: local,
          now: now,
        ),
    ];
    final sessions = _reachabilityNeighbors.map(_reachabilitySession).toSet();
    Set<String> routeShape() => {
      for (final route in _reachability.active(sessions, now))
        jsonEncode([route.path, route.name]),
    };
    final before = routeShape();
    if (!_reachability.replace(
      session,
      packet.payload['sequence']! as int,
      routes,
    )) {
      return;
    }
    _scheduleReachabilityExpiry();
    if (!setEquals(before, routeShape())) {
      refreshReachabilityConsent();
      notifyListeners();
      if (canOpenRemoteTextChat) _track(_retryQaPendingText());
    }
  }

  bool isDeviceConnected(String deviceId) =>
      isDeviceVerifiedConnected(deviceId);

  bool isDeviceVerifiedConnected(String deviceId) =>
      authenticatedConnectedPeers.any((peer) => peer.deviceId == deviceId);

  bool isEndpointVerifiedConnected(String endpointId) =>
      peerStates[endpointId] == NearbyConnectionState.connected &&
      _completedIdentityHandshakes.contains(endpointId);

  PeerConnectionPresence presenceForDevice(String deviceId) {
    if (deviceId.trim().isEmpty) return PeerConnectionPresence.unknown;
    if (isDeviceVerifiedConnected(deviceId)) {
      return PeerConnectionPresence.online;
    }
    if (!initialized || readiness?.ready != true) {
      return PeerConnectionPresence.unknown;
    }
    final hasUnverifiedSession = discoveredPeers.any((peer) {
      if (peer.deviceId != deviceId) return false;
      final state = peerStates[peer.endpointId];
      return state == NearbyConnectionState.connecting ||
          state == NearbyConnectionState.incomingRequest ||
          (state == NearbyConnectionState.connected &&
              !_completedIdentityHandshakes.contains(peer.endpointId));
    });
    if (hasUnverifiedSession) return PeerConnectionPresence.unknown;
    // หน้าที่เรียกส่ง canonical deviceId จาก conversation หรือ peer record
    // เมื่อ Nearby พร้อมและไม่มี session ที่ยืนยันแล้ว สถานะจึงเป็น Offline
    return PeerConnectionPresence.offline;
  }

  PeerConnectionPresence presenceForPrincipal(
    String deviceId,
    String? principal,
  ) {
    final presence = presenceForDevice(deviceId);
    if (presence != PeerConnectionPresence.online) return presence;
    if (principal == null) return PeerConnectionPresence.unknown;
    return endpointToDeviceId.entries.any(
          (entry) =>
              entry.value == deviceId &&
              _completedIdentityHandshakes.contains(entry.key) &&
              _remotePrincipals[entry.key] == principal,
        )
        ? PeerConnectionPresence.online
        : PeerConnectionPresence.offline;
  }

  String? deviceIdForEndpoint(String endpointId) =>
      endpointToDeviceId[endpointId];

  String? connectionTraceForEndpoint(String endpointId) =>
      _connectionTraces[endpointId];

  Future<void> initialize() async {
    if (initialized) return;
    initialized = true;
    if (settings != null) {
      _liveLocationSharingConsent = await settings!.getNullableBool(
        'nearby_live_location_enabled',
      );
      _developerLocationSharingOverrideEnabled = await settings!.getBool(
        'nearby_live_location_dev_override',
        defaultValue: true,
      );
    }
    _locationSettingsLoaded = true;
    await _locationCoordinator?.setEnabled(liveLocationSharingEnabled);
    await _locationCoordinator?.setForeground(appLifecycleState == 'resumed');
    notifyListeners();
    if (RelioBuildInfo.isTest && settings != null) {
      final savedMode = await settings!.getValue(_relayRouteModeSetting);
      _textRouteMode = RelayTextRouteMode.values.firstWhere(
        (mode) => mode.name == savedMode,
        orElse: () => RelayTextRouteMode.directOnly,
      );
      final savedMiddle = await settings!.getValue(_relayMiddleSetting);
      _forcedRelayMiddleDeviceId = savedMiddle == null || savedMiddle.isEmpty
          ? null
          : savedMiddle;
      if (_textRouteMode == RelayTextRouteMode.qaForcedRelay &&
          _forcedRelayMiddleDeviceId == null) {
        _textRouteMode = RelayTextRouteMode.directOnly;
      }
    }
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
    final fields = <String, Object?>{
      'elapsedMs': _diagnosticClock.elapsedMilliseconds,
      ...event.fields,
    };
    if (RelioBuildInfo.isTest) {
      fields.addAll({
        'qaRole': _diagnosticRole.name,
        'transportStrategy': transport.strategyName,
        'transportTestMode': transport.testMode.diagnosticName,
        'discoveryEpoch': transport.discoveryEpoch,
      });
    }
    final endpointId = fields['endpointId'] as String?;
    fields.remove('endpointId');
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
      connectionTraceId:
          (fields['connectionTraceId'] ?? fields['traceId']) as String?,
      operation: fields['operation'] as String?,
      nativeCode: fields['rawStatusCode'],
      nativeMessage: fields['rawStatusMessage'] as String?,
      fields: fields,
      peerIdentifier: endpointId,
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
      diagnostics?.record(
        'nearby',
        'advertising_start_begin',
        operation: 'startAdvertising',
        fields: {'qaRole': _diagnosticRole.name},
      );
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
        fields: {'fingerprintAvailable': true, 'qaRole': _diagnosticRole.name},
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
    final recovery = _disconnectDiscoveryRecovery;
    if (recovery != null) return recovery;
    if (_closed || _diagnosticRoleReady) return Future.value();
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
    switch (_diagnosticRole) {
      case NearbyDiagnosticRole.auto:
        final advertising = startAdvertising();
        var advertisingStartTimedOut = false;
        try {
          await advertising.timeout(advertisingStartWatchdog);
        } on TimeoutException {
          advertisingStartTimedOut = true;
          diagnostics?.record(
            'nearby',
            'advertising_start_watchdog_elapsed',
            severity: 'warning',
            operation: 'startAdvertising',
            fields: {
              'watchdogMs': advertisingStartWatchdog.inMilliseconds,
              'strategy': transport.strategyName,
              ..._radioSnapshotFields(),
            },
          );
          _log('advertising start remains pending; starting discovery');
        }
        // P2P_CLUSTER ทำ discovery แยกจาก local advertising ได้ จึงไม่ให้
        // native advertising ที่ค้างปิดกั้นการพบ peer ที่อีกฝั่งประกาศอยู่
        if (isAdvertising || advertisingStartTimedOut) {
          await startDiscovery();
        } else {
          _log('discovery skipped because advertising did not start');
        }
        break;
      case NearbyDiagnosticRole.advertiserOnly:
        await startAdvertising();
        break;
      case NearbyDiagnosticRole.discovererOnly:
        await startDiscovery();
        break;
      case NearbyDiagnosticRole.stopped:
        break;
    }
    _transition = null;
    if (_diagnosticRoleReady) {
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
      'NEARBY_STOP_REQUESTED',
      operation: 'stopNearbySession',
      reason: reason,
      fields: {
        'elapsedMs': _diagnosticClock.elapsedMilliseconds,
        'caller': caller,
        'activeConnections': connectedPeerCount,
        'appLifecycleState': appLifecycleState,
      },
    );
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
    if (_diagnosticRole == NearbyDiagnosticRole.advertiserOnly ||
        _diagnosticRole == NearbyDiagnosticRole.stopped) {
      diagnostics?.record(
        'nearby',
        'discovery_suppressed_by_qa_role',
        operation: 'startDiscovery',
        fields: {'qaRole': _diagnosticRole.name},
      );
      return;
    }
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
      diagnostics?.record(
        'nearby',
        'discovery_epoch_started',
        fields: {
          'discoveryEpoch': transport.discoveryEpoch,
          'transportTestMode': transport.testMode.diagnosticName,
          'strategy': transport.strategyName,
          'qaRole': _diagnosticRole.name,
        },
      );
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
      for (var index = 0; index < discoveredPeers.length; index++) {
        final peer = discoveredPeers[index];
        discoveredPeers[index] = NearbyPeer(
          id: peer.id,
          name: peer.name,
          deviceId: peer.deviceId,
          connected: peer.connected,
          identityFingerprintHint: peer.identityFingerprintHint,
          capabilities: peer.capabilities,
          discoveryEpoch: peer.discoveryEpoch,
          foundAt: peer.foundAt,
          lastSeenAt: peer.lastSeenAt,
          lostAt: peer.lostAt,
          isCurrent: false,
        );
        _endpointLifecycle[peer.endpointId] = discoveredPeers[index];
      }
      diagnostics?.record(
        'nearby',
        'discovery_epoch_ended',
        fields: {
          'discoveryEpoch': transport.discoveryEpoch,
          'transportTestMode': transport.testMode.diagnosticName,
        },
      );
      _log('หยุด Discovery แล้ว');
      notifyListeners();
    } on Object catch (error) {
      _fail('หยุด Discovery ไม่สำเร็จ: $error', code: _errorCode(error));
    }
  }

  Future<void> connect(String peerId) async {
    await _connect(peerId, userInitiated: true);
  }

  List<NearbyPeer> get currentPeers {
    final selected = <String, NearbyPeer>{};
    for (final peer in discoveredPeers) {
      final connected =
          peerStates[peer.endpointId] == NearbyConnectionState.connected;
      if (!connected && !isEndpointCurrent(peer.endpointId)) continue;
      final key =
          peer.identityFingerprintHint ?? peer.deviceId ?? peer.endpointId;
      final previous = selected[key];
      final previousConnected =
          previous != null &&
          peerStates[previous.endpointId] == NearbyConnectionState.connected;
      final newer =
          previous == null ||
          (peer.lastSeenAt ??
                  peer.foundAt ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .isAfter(
                previous.lastSeenAt ??
                    previous.foundAt ??
                    DateTime.fromMillisecondsSinceEpoch(0),
              );
      if (previous == null ||
          (connected && !previousConnected) ||
          (connected == previousConnected && newer)) {
        selected[key] = peer;
      }
    }
    return selected.values.toList(growable: false);
  }

  Future<void> connectPeer(NearbyPeer selected) async {
    final candidates = currentPeers.where(
      (peer) => selected.identityFingerprintHint != null
          ? peer.identityFingerprintHint == selected.identityFingerprintHint
          : selected.deviceId != null
          ? peer.deviceId == selected.deviceId
          : peer.endpointId == selected.endpointId,
    );
    final target = candidates.firstOrNull;
    if (target == null ||
        !isEndpointCurrent(target.endpointId) ||
        (selected.deviceId != null &&
            target.deviceId != null &&
            selected.deviceId != target.deviceId)) {
      peerErrors[selected.endpointId] = 'waiting_for_fresh_endpoint';
      notifyListeners();
      return;
    }
    // ชื่อไม่ใช่ identity; row ที่ผู้ใช้เลือกต้องตรงกับ candidate ล่าสุดก่อนเรียก native
    diagnostics?.record(
      'connection',
      'canonical_connect_target_selected',
      peerIdentifier: target.endpointId,
      fields: {
        'canonicalPeerAlias': target.deviceId == null
            ? null
            : DiagnosticsLogService.peerAlias(target.deviceId!),
        'fingerprintAlias': target.identityFingerprintHint == null
            ? null
            : DiagnosticsLogService.peerAlias(target.identityFingerprintHint!),
        'discoveryEpoch': target.discoveryEpoch,
      },
    );
    await _connect(target.endpointId, userInitiated: true);
  }

  Future<void> _connect(String peerId, {required bool userInitiated}) async {
    final teardown = _disconnectTasks[peerId];
    if (teardown != null) await teardown;
    final recovery = _disconnectDiscoveryRecovery;
    if (recovery != null) await recovery;
    if (_closed) return;
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
    if (!isEndpointCurrent(peerId)) {
      diagnostics?.record(
        'connection',
        'stale_endpoint_connect_blocked',
        operation: 'requestConnection',
        peerIdentifier: peerId,
        reason: 'waiting_for_fresh_endpoint',
        fields: {
          'currentDiscoveryEpoch': transport.discoveryEpoch,
          'endpoint': endpointLifecycleSnapshot.firstWhere(
            (entry) =>
                entry['endpointAlias'] ==
                DiagnosticsLogService.peerAlias(peerId),
            orElse: () => const <String, Object?>{},
          ),
        },
      );
      peerErrors[peerId] = 'waiting_for_fresh_endpoint';
      notifyListeners();
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
    _retiredConnectionEndpoints.remove(peerId);
    _connectionTraces[peerId] = traceId;
    _connectionStartedAt[peerId] = DateTime.now().toUtc();
    _beginTransportAttempt(peerId, role: 'initiator');
    _markTransportPhase(peerId, 'requestConnectionCalled');
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
        ..._radioSnapshotFields(),
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
      await _pauseDiscoveryForNegotiation(peerId);
      if (!_isCurrentConnectionSession(peerId, traceId)) return;
      final localIdentity = await identityCrypto.getPublicIdentity();
      if (!_isCurrentConnectionSession(peerId, traceId)) return;
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
      if (!_isCurrentConnectionSession(peerId, traceId)) return;
      _activeTransportAttempts[peerId]?['requestTaskResult'] = 'success';
      _markTransportPhase(peerId, 'requestConnectionTaskSuccess');
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
      if (!_isCurrentConnectionSession(peerId, traceId)) return;
      if (_errorCode(error) == '8003') {
        final discovered = discoveredPeers
            .where((peer) => peer.endpointId == peerId)
            .firstOrNull;
        if (discovered != null && isEndpointCurrent(peerId)) {
          diagnostics?.record(
            'connection',
            'already_connected_task_exception_reconciled',
            connectionTraceId: traceId,
            operation: 'requestConnection',
            peerIdentifier: peerId,
            nativeCode: 8003,
            reason: 'native_endpoint_already_connected',
          );
          // Nearby SDK อาจส่ง 8003 เป็น task exception แทน connection callback
          // แต่ native ยืนยันว่า endpoint ต่ออยู่แล้ว จึงทำ identity handshake ต่อ
          _onConnection(
            NearbyConnectionEvent(
              peer: discovered,
              state: NearbyConnectionState.failed,
              rawStatusCode: 8003,
              rawStatusName: 'STATUS_ALREADY_CONNECTED_TO_ENDPOINT',
              rawStatusMessage: error is NearbyTransportException
                  ? error.platformMessage ?? error.message
                  : null,
              operation: 'requestConnection',
              connectionTraceId: traceId,
            ),
          );
          return;
        }
      }
      _activeTransportAttempts[peerId]?['requestTaskResult'] = 'failure';
      _markTransportPhase(peerId, 'requestConnectionTaskFailure');
      _finishTransportAttempt(
        peerId,
        connected: false,
        nativeStatusCode: _errorCode(error) == '8011' ? 8011 : null,
      );
      _cancelConnectionTimers(peerId);
      _connectionPhases[peerId] = NearbyConnectionPhase.nativeResult;
      peerStates[peerId] = NearbyConnectionState.failed;
      _fingerprintEndpointReservations.removeWhere(
        (_, endpoint) => endpoint == peerId,
      );
      _clearConnectionSession(peerId, cancelRetry: false);
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
      await _resumeDiscoveryAfterNegotiation('request_failure');
    }
  }

  Future<void> _pauseDiscoveryForNegotiation(String endpointId) async {
    if (transport.testMode != NearbyTransportTestMode.clusterPauseDiscovery ||
        !isDiscovering ||
        _discoveryPausedForNegotiation) {
      return;
    }
    _discoveryPausedForNegotiation = true;
    // โหมด B หยุดเฉพาะ Discovery เพื่อคง Advertising และ endpoint ที่กำลัง negotiate
    diagnostics?.record(
      'connection',
      'discovery_paused_for_negotiation',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'stopDiscovery',
      peerIdentifier: endpointId,
      fields: {
        'transportTestMode': transport.testMode.diagnosticName,
        'advertisingActive': isAdvertising,
      },
    );
    await stopDiscovery();
  }

  Future<void> _resumeDiscoveryAfterNegotiation(String reason) async {
    if (!_discoveryPausedForNegotiation || hasActiveConnectionAttempts) return;
    _discoveryPausedForNegotiation = false;
    if (isAdvertising && !isDiscovering) {
      diagnostics?.record(
        'connection',
        'discovery_resumed_after_negotiation',
        operation: 'startDiscovery',
        reason: reason,
        fields: {'transportTestMode': transport.testMode.diagnosticName},
      );
      await startDiscovery();
    }
  }

  Future<void> _recoverDiscoveryAfterDisconnect() {
    final current = _disconnectDiscoveryRecovery;
    if (current != null) return current;
    if (_closed ||
        _diagnosticRole != NearbyDiagnosticRole.auto ||
        compatibilityModeActive ||
        !isAdvertising ||
        connectedPeers.isNotEmpty ||
        hasActiveConnectionAttempts) {
      return Future.value();
    }
    // native discovery อาจยังจำ endpoint เดิม โดยฝั่งรับไม่เคยได้ endpointFound;
    // เปิด epoch ใหม่ทั้งสองฝั่งเมื่อ connection สุดท้ายจบ ไม่ยก incoming เป็น endpoint สดเอง
    final operation = Future<void>(() async {
      final starting = _startSessionOperation;
      if (starting != null) await starting;
      if (_closed || connectedPeers.isNotEmpty || hasActiveConnectionAttempts) {
        return;
      }
      diagnostics?.record(
        'connection',
        'discovery_recovery_after_disconnect',
        operation: 'refreshNearbyDiscovery',
        fields: {'discoveryEpoch': transport.discoveryEpoch},
      );
      await stopDiscovery();
      if (_closed || connectedPeers.isNotEmpty || hasActiveConnectionAttempts) {
        return;
      }
      await stopAdvertising();
      if (_closed || connectedPeers.isNotEmpty || hasActiveConnectionAttempts) {
        return;
      }
      if (transport case NearbyIdleSessionRecovery recovery) {
        await recovery.clearIdleEndpoints();
        diagnostics?.record(
          'connection',
          'idle_native_endpoints_cleared',
          operation: 'clearIdleEndpoints',
        );
      }
      if (_closed) return;
      await _startSession();
    });
    _disconnectDiscoveryRecovery = operation;
    return operation.whenComplete(() {
      if (identical(_disconnectDiscoveryRecovery, operation)) {
        _disconnectDiscoveryRecovery = null;
      }
    });
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

  bool _isCurrentConnectionSession(String endpointId, String? traceId) =>
      !_closed && traceId != null && _connectionTraces[endpointId] == traceId;

  // ล้างเฉพาะ session ของ endpoint นี้; trust และประวัติใน SQLite ยังคงอยู่
  void _clearConnectionSession(String endpointId, {bool cancelRetry = true}) {
    if (cancelRetry) {
      _connectionCancellationEpochs.update(
        endpointId,
        (epoch) => epoch + 1,
        ifAbsent: () => 1,
      );
    }
    final fingerprint =
        _reconnectFingerprintByEndpoint[endpointId] ??
        discoveredPeers
            .where((peer) => peer.endpointId == endpointId)
            .firstOrNull
            ?.identityFingerprintHint;
    final reservedEndpoint = fingerprint == null
        ? null
        : _fingerprintEndpointReservations[fingerprint];
    if (fingerprint != null &&
        (reservedEndpoint == null || reservedEndpoint == endpointId)) {
      _automaticConnectionAttempts.remove(fingerprint);
      if (cancelRetry) {
        _reconnectTimers.remove(fingerprint)?.cancel();
        _cancelSecondaryInitiatorFallback(fingerprint, resetElection: true);
        _nextReconnectAt.remove(fingerprint);
        _reconnectAttemptCounts.remove(fingerprint);
        _freshEndpointRetryByFingerprint.remove(fingerprint);
      }
    }
    _cancelConnectionTimers(endpointId);
    _identityHandshakeTimeouts.remove(endpointId)?.cancel();
    _nativeAcceptInFlight.remove(endpointId);
    pendingConnectionRequests.remove(endpointId);
    _approvedConnectionEndpoints.remove(endpointId);
    _provisionalConnectionEndpoints.remove(endpointId);
    _provisionalIncomingRequests.remove(endpointId);
    _userInitiatedEndpoints.remove(endpointId);
    _identityChallenges.remove(endpointId);
    _remotePrincipals.remove(endpointId);
    _remotePrincipalEpochs.remove(endpointId);
    _remoteProfileRevisions.remove(endpointId);
    _completedIdentityHandshakes.remove(endpointId);
    _locationCoordinator?.onPeerDisconnected(endpointId);
    _reconnectFingerprintByEndpoint.remove(endpointId);
    _freshEndpointRetryEndpoints.remove(endpointId);
    final deviceId = endpointToDeviceId.remove(endpointId);
    if (deviceId != null && deviceToEndpointId[deviceId] == endpointId) {
      deviceToEndpointId.remove(deviceId);
    }
    _fingerprintEndpointReservations.removeWhere(
      (_, endpoint) => endpoint == endpointId,
    );
    _finishTransportAttempt(endpointId, connected: false);
    _connectionTraces.remove(endpointId);
    _connectionStartedAt.remove(endpointId);
    _connectionPhases.remove(endpointId);
    _connectionPhaseStartedAt.remove(endpointId);
    _retiredConnectionEndpoints.add(endpointId);
    final index = discoveredPeers.indexWhere(
      (peer) => peer.endpointId == endpointId,
    );
    if (index != -1) {
      discoveredPeers[index] = discoveredPeers[index].withIdentity(
        connected: false,
      );
    }
    if (!hasActiveConnectionAttempts) _sessionRestartDeferred = false;
  }

  @visibleForTesting
  Map<String, int> get transientConnectionCounts => {
    'pending': pendingConnectionRequests.length,
    'attempts': activeConnectionAttempts,
    'endpointMappings': endpointToDeviceId.length,
    'deviceMappings': deviceToEndpointId.length,
    'softTimeouts': _connectionSoftTimeouts.length,
    'hardWatchdogs': _connectionHardWatchdogs.length,
    'handshakeTimeouts': _identityHandshakeTimeouts.length,
    'nativeAccepts': _nativeAcceptInFlight.length,
    'provisionalRequests': _provisionalIncomingRequests.length,
    'approvedEndpoints': _approvedConnectionEndpoints.length,
    'userInitiatedEndpoints': _userInitiatedEndpoints.length,
    'identityChallenges': _identityChallenges.length,
    'completedHandshakes': _completedIdentityHandshakes.length,
    'reservations': _fingerprintEndpointReservations.length,
    'reconnectTimers': _reconnectTimers.length,
    'secondaryInitiatorFallbackTimers':
        _secondaryInitiatorFallbackTimers.length,
    'automaticAttempts': _automaticConnectionAttempts.length,
    'reconnectEndpoints': _reconnectFingerprintByEndpoint.length,
    'freshEndpointRetries': _freshEndpointRetryByFingerprint.length,
    'transportAttempts': _activeTransportAttempts.length,
    'sessions': _connectionTraces.length,
  };

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
    diagnostics?.record(
      'connection',
      'connection_hard_watchdog_fired',
      severity: 'error',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'connectionNegotiation',
      peerIdentifier: endpointId,
      fields: {'phase': _connectionPhases[endpointId]?.name},
    );
    final traceId = _connectionTraces[endpointId];
    final softTimeoutElapsed = peerErrors[endpointId] == 'connection_slow';
    final operation = _approvedConnectionEndpoints.contains(endpointId)
        ? 'acceptConnection'
        : 'requestConnection';
    _cancelConnectionTimers(endpointId);
    _nativeAcceptInFlight.remove(endpointId);
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
      final teardown = disconnect(
        endpointId,
        reason: 'hard_negotiation_timeout',
      );
      peerStates[endpointId] = NearbyConnectionState.failed;
      await teardown;
    } on Object {
      // การ cleanup หลัง timeout อาจไม่สำเร็จ แต่ state ชั่วคราวในเครื่องยังหมดอายุตามกำหนด      // Timeout cleanup is best effort; local transient state still expires.
    }
    if (_closed || _connectionTraces.containsKey(endpointId)) return;
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
    if (_completedIdentityHandshakes.contains(endpointId)) return;
    final traceId = _connectionTraces[endpointId];
    final isAutomaticTrustedReconnect =
        !pendingConnectionRequests.containsKey(endpointId) &&
        _approvedConnectionEndpoints.contains(endpointId);
    if (!pendingConnectionRequests.containsKey(endpointId) &&
        !isAutomaticTrustedReconnect) {
      return;
    }
    if (!_nativeAcceptInFlight.add(endpointId)) {
      diagnostics?.record(
        'connection',
        'duplicate_accept_suppressed',
        connectionTraceId: _connectionTraces[endpointId],
        operation: 'acceptConnection',
        peerIdentifier: endpointId,
      );
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
      fields: {
        'automaticTrustedReconnect': isAutomaticTrustedReconnect,
        ..._radioSnapshotFields(),
      },
    );
    _markTransportPhase(endpointId, 'acceptTapped');
    _activeTransportAttempts[endpointId]?['acceptTaskResult'] = 'pending';
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
      await _pauseDiscoveryForNegotiation(endpointId);
      if (!_isCurrentConnectionSession(endpointId, traceId)) return;
      _markTransportPhase(endpointId, 'acceptConnectionCalled');
      await transport.acceptConnection(
        endpointId,
        connectionTraceId: _connectionTraces[endpointId],
      );
      if (!_isCurrentConnectionSession(endpointId, traceId)) return;
      _activeTransportAttempts[endpointId]?['acceptTaskResult'] = 'success';
      _markTransportPhase(endpointId, 'acceptConnectionTaskSuccess');
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
      if (!_isCurrentConnectionSession(endpointId, traceId)) return;
      _nativeAcceptInFlight.remove(endpointId);
      _activeTransportAttempts[endpointId]?['acceptTaskResult'] = 'failure';
      _markTransportPhase(endpointId, 'acceptConnectionTaskFailure');
      _finishTransportAttempt(
        endpointId,
        connected: false,
        nativeStatusCode: _errorCode(error) == '8011' ? 8011 : null,
      );
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
      final teardown = disconnect(
        endpointId,
        reason: 'accept_connection_failed',
      );
      peerStates[endpointId] = NearbyConnectionState.failed;
      await teardown;
    }
  }

  Future<void> rejectConnectionRequest(String endpointId) async {
    diagnostics?.record(
      'connection',
      'reject_tapped',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'rejectConnection',
      peerIdentifier: endpointId,
    );
    await disconnect(endpointId, reason: 'identity_approval_rejected');
  }

  Future<void> disconnect(String peerId, {String reason = 'user_requested'}) {
    final existing = _disconnectTasks[peerId];
    if (existing != null) return existing;
    late final Future<void> task;
    task = _disconnectEndpoint(peerId, reason: reason).whenComplete(() {
      if (identical(_disconnectTasks[peerId], task)) {
        _disconnectTasks.remove(peerId);
      }
    });
    _disconnectTasks[peerId] = task;
    return task;
  }

  Future<void> _disconnectEndpoint(
    String peerId, {
    required String reason,
  }) async {
    final wasConnected = peerStates[peerId] == NearbyConnectionState.connected;
    final traceId = _connectionTraces[peerId];
    final rejectPending =
        pendingConnectionRequests.containsKey(peerId) &&
        peerStates[peerId] != NearbyConnectionState.connected;
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
    // ยกเลิก state ทันที ไม่รอ native callback; reconnect รอ teardown ของ endpoint เดิม
    peerStates[peerId] = NearbyConnectionState.disconnected;
    _clearConnectionSession(peerId);
    notifyListeners();
    try {
      if (rejectPending) {
        try {
          await transport.rejectConnection(peerId, connectionTraceId: traceId);
        } on Object {
          // reject อาจหมดอายุแล้ว แต่ยังต้องเรียก native disconnect ต่อ
        }
      }
      await transport.disconnect(peerId);
      _log('ตัดการเชื่อมต่อ ${DiagnosticsLogService.peerAlias(peerId)}');
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
    } finally {
      _appDisconnectRequests.remove(peerId);
      await _resumeDiscoveryAfterNegotiation('disconnected');
      if (wasConnected) await _recoverDiscoveryAfterDisconnect();
    }
  }

  Future<void> cancelConnection(String peerId) =>
      disconnect(peerId, reason: 'user_cancelled_connection');

  Future<void> removeTrustedPeer(String deviceId) async {
    final saved = await nearbyDevices.getDevice(deviceId);
    final fingerprint = saved?.publicIdentityFingerprint;
    // ถอนสิทธิ์ใน SQLite ก่อนหยุด session เพื่อไม่ให้ Nearby เริ่มต่ออัตโนมัติระหว่าง cleanup
    await nearbyDevices.removeTrustedPeer(deviceId);
    if (fingerprint != null) {
      _automaticConnectionAttempts.remove(fingerprint);
      _reconnectTimers.remove(fingerprint)?.cancel();
      _nextReconnectAt.remove(fingerprint);
      _reconnectAttemptCounts.remove(fingerprint);
      _fingerprintEndpointReservations.remove(fingerprint);
      _freshEndpointRetryByFingerprint.remove(fingerprint);
    }
    final endpoints = <String>{
      if (deviceToEndpointId[deviceId] case final String endpoint) endpoint,
      for (final peer in discoveredPeers)
        if (peer.deviceId == deviceId ||
            (fingerprint != null &&
                peer.identityFingerprintHint == fingerprint))
          peer.endpointId,
      for (final entry in _reconnectFingerprintByEndpoint.entries)
        if (entry.value == fingerprint) entry.key,
    };
    for (final endpointId in endpoints) {
      _reconnectFingerprintByEndpoint.remove(endpointId);
      final state = peerStates[endpointId];
      if (pendingConnectionRequests.containsKey(endpointId) ||
          state == NearbyConnectionState.incomingRequest) {
        await rejectConnectionRequest(endpointId);
      } else if (state == NearbyConnectionState.connected ||
          state == NearbyConnectionState.connecting) {
        await disconnect(endpointId, reason: 'trusted_peer_removed');
      }
    }
    notifyListeners();
  }

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
    final status = await currentStatus();
    final rescueActive =
        settings != null &&
        await settings!.getBool('rescue_mode', defaultValue: false);
    final battery = await batteryInfo?.readSnapshot();
    final packet = RelioPacket.hello(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: await _senderUserId(),
      displayName: await identity.getDisplayName(),
      status: status,
      rescueActive: rescueActive,
      batteryLevel: battery?.level,
      isCharging: battery?.isCharging,
      batteryUpdatedAt: battery?.updatedAt,
      deviceModel: _deviceModel,
      capabilities: RelioBuildInfo.isTest
          ? [
              'textMessage',
              'deviceStatus',
              'ack',
              'relay-v1',
              if (qaPlaintextTextEnabled) _qaTextRelayCapability,
              nearbyReachabilityCapability,
              'avatar-v1',
            ]
          : const [
              'textMessage',
              'deviceStatus',
              'ack',
              'relay-v1',
              nearbyReachabilityCapability,
            ],
    );
    await _sendPacket(packet, description: 'Hello RELIO', peerId: peerId);
    if (battery?.isValid == true) _lastPublishedBattery = battery;
  }

  Future<void> propagateCurrentStatus() async {
    final deviceId = await identity.getDeviceId();
    final status = await currentStatus();
    final rescueActive =
        settings != null &&
        await settings!.getBool('rescue_mode', defaultValue: false);
    final battery = await batteryInfo?.readSnapshot();
    await _sendPacket(
      RelioPacket.deviceStatus(
        senderDeviceId: deviceId,
        senderUserId: await _senderUserId(),
        displayName: await identity.getDisplayName(),
        status: status,
        rescueActive: rescueActive,
        batteryLevel: battery?.level,
        isCharging: battery?.isCharging,
        batteryUpdatedAt: battery?.updatedAt,
        deviceModel: _deviceModel,
      ),
      description: 'deviceStatus ${status.name}',
    );
    try {
      await _propagateRescueStatusViaRelay(
        deviceId: deviceId,
        displayName: await identity.getDisplayName(),
        rescueActive: rescueActive,
      );
    } on Object catch (error) {
      _log('Rescue relay status deferred: ${_errorCode(error)}');
    }
    final latest = await sos?.readLatest(ownerDeviceId: deviceId);
    if (latest != null) await sendSos(latest);
  }

  Future<void> _propagateRescueStatusViaRelay({
    required String deviceId,
    required String displayName,
    required bool rescueActive,
  }) async {
    final engine = relayEngine;
    if (engine == null) return;
    final routes = activeReachabilityRoutes;
    if (routes.isEmpty) return;
    final revision = await _nextLocalRescueRevision(deviceId);
    final basePacket = RelioPacket.rescueStatus(
      senderDeviceId: deviceId,
      senderUserId: await _senderUserId(),
      rescueId: const Uuid().v4(),
      displayName: displayName,
      rescueActive: rescueActive,
      updatedAt: DateTime.now().toUtc(),
      stateRevision: revision,
    );
    final identityProof = await identityCrypto.getPublicIdentity();
    for (final route in routes) {
      if (route.path.length != 2 || route.path.last != route.deviceId) {
        continue;
      }
      final nextHops = authenticatedConnectedPeers.where(
        (peer) =>
            peer.deviceId == route.path.first &&
            peer.capabilities.contains('relay-v1'),
      );
      if (nextHops.length != 1) continue;
      final proofPayload = {
        ...basePacket.payload,
        'relayDestinationDeviceId': route.deviceId,
      };
      final unsignedPacket = RelioPacket(
        protocolVersion: basePacket.protocolVersion,
        packetId: basePacket.packetId,
        type: basePacket.type,
        senderDeviceId: basePacket.senderDeviceId,
        senderUserId: basePacket.senderUserId,
        createdAt: basePacket.createdAt,
        payload: proofPayload,
      );
      final signature = await identityCrypto.sign(
        _originProofMessage(unsignedPacket),
      );
      final signedPacket = RelioPacket(
        protocolVersion: basePacket.protocolVersion,
        packetId: basePacket.packetId,
        type: basePacket.type,
        senderDeviceId: basePacket.senderDeviceId,
        senderUserId: basePacket.senderUserId,
        createdAt: basePacket.createdAt,
        payload: {
          ...proofPayload,
          'originPublicKey': identityProof.publicKey,
          'originFingerprint': identityProof.fingerprint,
          'originSignature': signature,
        },
      );
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: signedPacket,
        destinationDeviceId: route.deviceId,
        maxHops: route.path.length,
        priority: 50,
      ).copyWith(firstHopDeviceId: route.path.first);
      await engine.enqueueEnvelope(envelope);
    }
  }

  Future<int> _nextLocalRescueRevision(String deviceId) async {
    final key = 'nearby_rescue_revision_$deviceId';
    final stored = settings == null
        ? 0
        : await settings!.getInt(key, defaultValue: 0);
    final next = stored + 1;
    await settings?.setInt(key, next);
    return next;
  }

  Future<void> sendSos(RelioSosEvent event, {String? peerId}) async {
    final deviceId = await identity.getDeviceId();
    final displayName = await identity.getDisplayName();
    final stateRevision = await _nextLocalSosRevision(deviceId);
    final packet = RelioPacket.sos(
      senderDeviceId: deviceId,
      senderUserId: event.ownerUserId.isNotEmpty ? event.ownerUserId : deviceId,
      displayName: displayName,
      sosId: event.id,
      message: event.message,
      latitude: event.latitude,
      longitude: event.longitude,
      accuracyMeters: event.locationAccuracy,
      locationCapturedAt: event.locationCapturedAt,
      createdAt: event.createdAt,
      isActive: event.isActive,
      stateRevision: stateRevision,
    );
    final candidates = peerId == null
        ? connectedPeers
        : connectedPeers.where((peer) => peer.endpointId == peerId);
    final targetsByDevice = <String, NearbyPeer>{};
    for (final peer in candidates) {
      final connectionStillActive =
          peerStates[peer.endpointId] == NearbyConnectionState.connected;
      // Discovery มองไม่เห็น peer แล้วไม่ได้แปลว่า transport ที่เชื่อมอยู่หลุด
      if ((_endpointLifecycle[peer.endpointId]?.isLost == true ||
              peer.isLost) &&
          !connectionStillActive) {
        _recordSosSend(
          'outbound_send_skipped',
          eventId: event.id,
          isActive: event.isActive,
          stateRevision: stateRevision,
          peer: peer,
          reason: 'endpoint_lost',
        );
        continue;
      }
      final relioDeviceId = endpointToDeviceId[peer.endpointId];
      final identityEstablished =
          relioDeviceId != null &&
          relioDeviceId == peer.deviceId &&
          _completedIdentityHandshakes.contains(peer.endpointId);
      if (!identityEstablished && transport is! MockNearbyTransport) {
        _recordSosSend(
          'outbound_send_skipped',
          eventId: event.id,
          isActive: event.isActive,
          peer: peer,
          reason: 'identity_not_established',
        );
        continue;
      }
      final key = relioDeviceId ?? peer.deviceId ?? peer.endpointId;
      final previous = targetsByDevice[key];
      if (previous == null ||
          (!previous.endpointId.startsWith('classic:') &&
              peer.endpointId.startsWith('classic:'))) {
        targetsByDevice[key] = peer;
      }
    }

    final targets = targetsByDevice.values.toList(growable: false);
    if (targets.isNotEmpty) {
      _pendingSosAcks[packet.packetId] = targets
          .map((peer) => endpointToDeviceId[peer.endpointId] ?? peer.deviceId)
          .whereType<String>()
          .toSet();
      _sosEventIdsByPacketId[packet.packetId] = event.id;
    }
    var successes = 0;
    final failures = <String>[];
    for (final peer in targets) {
      final transportName = peer.endpointId.startsWith('classic:')
          ? 'RFCOMM'
          : 'Nearby';
      _recordSosSend(
        'outbound_send_start',
        eventId: event.id,
        isActive: event.isActive,
        stateRevision: stateRevision,
        peer: peer,
        transportName: transportName,
      );
      try {
        await transport.sendBytes(packet.toBytes(), peerId: peer.endpointId);
        successes++;
        _recordSosSend(
          'outbound_send_success',
          eventId: event.id,
          isActive: event.isActive,
          stateRevision: stateRevision,
          peer: peer,
          transportName: transportName,
        );
        _log(
          'SOS send success event=${event.id} '
          'peer=${peer.deviceId ?? 'unknown'} transport=$transportName',
        );
      } on Object catch (error) {
        final relioDeviceId = endpointToDeviceId[peer.endpointId];
        if (relioDeviceId != null) {
          _pendingSosAcks[packet.packetId]?.remove(relioDeviceId);
        }
        final code = _errorCode(error);
        failures.add('${peer.endpointId}:$code');
        _recordSosSend(
          'outbound_send_failure',
          eventId: event.id,
          isActive: event.isActive,
          stateRevision: stateRevision,
          peer: peer,
          transportName: transportName,
          reason: code,
        );
        _log(
          'SOS send failure event=${event.id} '
          'peer=${peer.deviceId ?? 'unknown'} transport=$transportName code=$code',
        );
      }
    }
    var relayed = 0;
    final routes = peerId != null || relayEngine == null
        ? const <NearbyReachabilityRoute>[]
        : activeReachabilityRoutes;
    final directDeviceIds = targets
        .map((peer) => endpointToDeviceId[peer.endpointId] ?? peer.deviceId)
        .whereType<String>()
        .toSet();
    if (routes.isNotEmpty) {
      try {
        final identityProof = await identityCrypto.getPublicIdentity();
        final source = await identity.getDeviceId();
        for (final route in routes) {
          if (route.path.length != 2 ||
              route.path.first == source ||
              route.path.length > RelayPolicy().maxHops ||
              directDeviceIds.contains(route.deviceId)) {
            continue;
          }
          final firstHop = route.path.first;
          final nextHop = authenticatedConnectedPeers.where(
            (peer) =>
                peer.deviceId == firstHop &&
                peer.capabilities.contains('relay-v1'),
          );
          if (nextHop.length != 1) continue;
          final proofPayload = {
            ...packet.payload,
            'relayDestinationDeviceId': route.deviceId,
          };
          final unsignedRelayPacket = RelioPacket(
            protocolVersion: packet.protocolVersion,
            packetId: event.id,
            type: packet.type,
            senderDeviceId: packet.senderDeviceId,
            senderUserId: packet.senderUserId,
            createdAt: packet.createdAt,
            payload: proofPayload,
          );
          final signature = await identityCrypto.sign(
            _originProofMessage(unsignedRelayPacket),
          );
          final relayPacket = RelioPacket(
            protocolVersion: packet.protocolVersion,
            packetId: event.id,
            type: packet.type,
            senderDeviceId: packet.senderDeviceId,
            senderUserId: packet.senderUserId,
            createdAt: packet.createdAt,
            payload: {
              ...proofPayload,
              'originPublicKey': identityProof.publicKey,
              'originFingerprint': identityProof.fingerprint,
              'originSignature': signature,
            },
          );
          final envelope = RelayEnvelope.fromPayloadPacket(
            packet: relayPacket,
            destinationDeviceId: route.deviceId,
            maxHops: route.path.length,
            priority: 100,
          ).copyWith(firstHopDeviceId: firstHop);
          final result = await relayEngine!.enqueueEnvelope(envelope);
          if (result == RelayResult.stored ||
              result == RelayResult.forwarded ||
              result == RelayResult.duplicate) {
            relayed++;
          }
        }
      } on Object catch (error) {
        _log('SOS relay preparation failed: ${_errorCode(error)}');
      }
    }
    if (_pendingSosAcks[packet.packetId]?.isEmpty == true) {
      _pendingSosAcks.remove(packet.packetId);
      _sosEventIdsByPacketId.remove(packet.packetId);
    }
    if (successes == 0 && relayed == 0) {
      _pendingSosAcks.remove(packet.packetId);
      _sosEventIdsByPacketId.remove(packet.packetId);
      _recordSosSend(
        'outbound_send_failed',
        eventId: event.id,
        reason: targets.isEmpty
            ? 'no_direct_or_relay_route'
            : 'all_routes_failed',
      );
      _fail('ส่ง SOS ไม่สำเร็จ: ยังไม่มีเส้นทางถึงผู้รับ');
      return;
    }
    lastSentPacket = _diagnosticPacket(packet);
    _log(
      'ส่ง SOS ${event.id} direct=$successes/${targets.length} relay=$relayed'
      '${failures.isEmpty ? '' : ' failed=${failures.length}'}',
    );
    notifyListeners();
  }

  Uint8List _originProofMessage(RelioPacket packet) {
    final payload = Map<String, Object?>.of(packet.payload)
      ..remove('originPublicKey')
      ..remove('originFingerprint')
      ..remove('originSignature');
    final payloadId = payload['sosId'] ?? payload['rescueId'];
    if (payloadId is! String || payloadId.isEmpty) {
      throw const FormatException('Signed relay payload has no identity.');
    }
    return RelioPacket(
      protocolVersion: packet.protocolVersion,
      packetId: payloadId,
      type: packet.type,
      senderDeviceId: packet.senderDeviceId,
      senderUserId: packet.senderUserId,
      createdAt: packet.createdAt,
      payload: payload,
    ).toBytes();
  }

  Future<bool> verifyRelayedOrigin(
    RelayEnvelope envelope,
    RelioPacket packet,
  ) async {
    final validOwner = switch (packet.type) {
      RelioPacketType.sos =>
        packet.payload['ownerDeviceId'] == packet.senderDeviceId,
      RelioPacketType.rescueStatus =>
        packet.payload['deviceId'] == packet.senderDeviceId,
      _ => false,
    };
    if (!validOwner ||
        envelope.originDeviceId != packet.senderDeviceId ||
        packet.payload['relayDestinationDeviceId'] !=
            envelope.destinationDeviceId) {
      return false;
    }
    final publicKey = packet.payload['originPublicKey'];
    final fingerprint = packet.payload['originFingerprint'];
    final signature = packet.payload['originSignature'];
    if (publicKey is! String ||
        fingerprint is! String ||
        signature is! String ||
        signature.isEmpty) {
      return false;
    }
    try {
      final saved = await nearbyDevices.getDevice(packet.senderDeviceId);
      if (saved?.publicIdentityKey != publicKey ||
          saved?.publicIdentityFingerprint != fingerprint ||
          await identityCrypto.fingerprint(publicKey) != fingerprint) {
        return false;
      }
      return identityCrypto.verify(
        publicKey: publicKey,
        message: _originProofMessage(packet),
        signature: signature,
      );
    } on Object {
      return false;
    }
  }

  Future<void> receiveRelayedSos(String endpointId, RelioPacket packet) =>
      _handleSos(endpointId, packet, viaRelay: true);

  Future<void> receiveRelayedRescue(
    String endpointId,
    RelioPacket packet,
  ) async {
    if (packet.type != RelioPacketType.rescueStatus) return;
    final payload = packet.payload;
    final deviceId = packet.senderDeviceId;
    final revision = payload['stateRevision'];
    final updatedAt = DateTime.tryParse(payload['updatedAt']! as String);
    if (revision is! int || updatedAt == null) return;
    final key = 'nearby_rescue_revision_$deviceId';
    final lastRevision = settings == null
        ? 0
        : await settings!.getInt(key, defaultValue: 0);
    if (revision <= lastRevision) return;
    await _handleDeviceStatus(
      RelioPacket.deviceStatus(
        senderDeviceId: deviceId,
        senderUserId: packet.senderUserId,
        displayName: payload['displayName']! as String,
        status: payload['rescueActive']! as bool
            ? DeviceStatus.rescue
            : DeviceStatus.normal,
        rescueActive: payload['rescueActive']! as bool,
        updatedAt: updatedAt,
      ),
    );
    await settings?.setInt(key, revision);
  }

  Future<int> _nextLocalSosRevision(String deviceId) {
    final completer = Completer<int>();
    final key = 'nearby_sos_revision_$deviceId';
    _sosRevisionQueue = _sosRevisionQueue.then((_) async {
      try {
        final stored = settings == null
            ? (_localSosRevisions[deviceId] ?? 0)
            : await settings!.getInt(
                key,
                defaultValue: _localSosRevisions[deviceId] ?? 0,
              );
        final next = stored + 1;
        _localSosRevisions[deviceId] = next;
        await settings?.setInt(key, next);
        completer.complete(next);
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _recordSosSend(
    String event, {
    required String eventId,
    int? stateRevision,
    bool? isActive,
    NearbyPeer? peer,
    String? transportName,
    String? reason,
  }) {
    diagnostics?.record(
      'sos',
      event,
      severity: event.endsWith('failure') ? 'error' : 'info',
      connectionTraceId: peer == null
          ? null
          : _connectionTraces[peer.endpointId],
      operation: 'sendSos',
      peerIdentifier: peer?.endpointId,
      reason: reason,
      fields: {
        'sosEventId': eventId,
        'stateRevision': stateRevision,
        'isActive': isActive,
        'remoteRelioDeviceId': peer == null
            ? null
            : endpointToDeviceId[peer.endpointId] ?? peer.deviceId,
        'transport': transportName,
        'sessionState': peer == null ? null : peerStates[peer.endpointId]?.name,
      },
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
    if (_closed || !_textSendsInProgress.add(message.id)) return;
    final key = message.conversationId ?? message.id;
    final owner = _owners.capture();
    final previous = _textConversationTails[key] ?? Future<void>.value();
    final operation = previous
        .then(
          (_) => _owners.run(() async {
            if (_closed) return;
            _owners.requireCurrent(owner);
            await _sendMessageOwned(message);
          }),
        )
        .catchError((Object _) {});
    _textConversationTails[key] = operation;
    try {
      await operation;
    } finally {
      _textSendsInProgress.remove(message.id);
      if (identical(_textConversationTails[key], operation)) {
        _textConversationTails.remove(key);
      }
    }
  }

  Future<void> _sendMessageOwned(RelioMessage message) async {
    final owner = _owners.capture();
    final saved = await messages.getMessage(message.id);
    _owners.requireCurrent(owner);
    if (saved == null ||
        !saved.outgoing ||
        saved.type != MessageType.text ||
        saved.status == DeliveryStatus.delivered ||
        saved.status == DeliveryStatus.synced) {
      return;
    }
    final origin = await identity.getDeviceId();
    if (RelioBuildInfo.isTest && relayEngine != null) {
      final locked = await relayEngine!.repository.getForPayload(
        origin,
        message.id,
      );
      _owners.requireCurrent(owner);
      if (locked != null) {
        if (locked.envelope.toPayloadPacket().senderPrincipal !=
            await _activePrincipal()) {
          return;
        }
        _owners.requireCurrent(owner);
        if (locked.state == RelayPacketState.delivered) {
          await messages.advanceTextRouteStatus(
            message.id,
            DeliveryStatus.delivered,
          );
        } else if (locked.state == RelayPacketState.blocked ||
            locked.state == RelayPacketState.expired) {
          await messages.markFailed(message.id, locked.state.name);
        }
        await relayEngine!.forwardPending();
        return;
      }
      if (saved.status == DeliveryStatus.nearbySent && !canOpenRemoteTextChat) {
        return;
      }
    }
    final packet = RelioPacket.textMessage(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: message.senderId ?? await _senderUserId(),
      messageId: message.id,
      conversationId: message.conversationId ?? 'somchai',
      text: message.text,
      timestamp: message.createdAt ?? DateTime.now(),
    );
    _packetMessageIds[packet.packetId] = message.id;
    final destinationDeviceId = await _destinationDeviceForMessage(message);
    _owners.requireCurrent(owner);
    if (destinationDeviceId == null) return;
    final expectedPrincipal =
        qaPlaintextTextEnabled &&
            relayEngine?.qaPlaintextTextAllowed != null &&
            message.conversationId != null
        ? await conversations.remotePrincipalForConversation(
            message.conversationId!,
          )
        : null;
    final route = RelioBuildInfo.isTest
        ? await planTextRoute(
            destinationDeviceId,
            expectedPrincipal: expectedPrincipal,
          )
        : RelayRoutePlan(
            mode: RelayTextRouteMode.directOnly,
            kind: RelayRouteKind.direct,
            sourceDeviceId: await identity.getDeviceId(),
            destinationDeviceId: destinationDeviceId,
            directEndpointId: await _endpointForMessage(message),
            verifiedAt: DateTime.now().toUtc(),
          );
    _owners.requireCurrent(owner);
    if (!route.ready ||
        (route.kind == RelayRouteKind.direct &&
            route.directEndpointId == null)) {
      lastError = route.mode == RelayTextRouteMode.directOnly
          ? 'ยังไม่พบการเชื่อมต่อโดยตรงของผู้รับข้อความ'
          : 'ยังไม่พบเส้นทาง Direct หรือ Relay ที่พร้อม';
      _log('เก็บข้อความ ${message.id} ไว้ pending: route unavailable');
      notifyListeners();
      return;
    }
    if (route.kind == RelayRouteKind.relay) {
      await _sendTextViaRelay(message, packet, route, owner);
      return;
    }
    final peerId = route.directEndpointId!;
    try {
      await _sendApplicationBytes(packet, peerId: peerId);
      if (RelioBuildInfo.isTest) {
        await messages.advanceTextRouteStatus(
          message.id,
          DeliveryStatus.nearbySent,
        );
      } else {
        await messages.updateDeliveryStatus(
          message.id,
          DeliveryStatus.nearbySent,
        );
      }
      if (RelioBuildInfo.isTest) {
        diagnostics?.record(
          'relay',
          'text_direct_sent',
          fields: {
            'payloadAlias': DiagnosticsLogService.peerAlias(message.id),
            'originAlias': DiagnosticsLogService.peerAlias(origin),
            'destinationAlias': DiagnosticsLogService.peerAlias(
              destinationDeviceId,
            ),
            'hopCount': 1,
            'maxHops': 1,
          },
        );
      }
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
            peerId: peerId,
            bytes: ack.toBytes(),
          );
        });
      }
    } on Object catch (error) {
      if (RelioBuildInfo.isTest &&
          route.mode == RelayTextRouteMode.automatic &&
          relayEngine != null) {
        diagnostics?.record(
          'relay',
          'text_direct_send_failed',
          fields: {
            'payloadAlias': DiagnosticsLogService.peerAlias(message.id),
            'originAlias': DiagnosticsLogService.peerAlias(origin),
            'destinationAlias': DiagnosticsLogService.peerAlias(
              destinationDeviceId,
            ),
            'fallbackAttempted': true,
          },
        );
        try {
          final fallback = await planTextRoute(
            destinationDeviceId,
            preferRelay: true,
            expectedPrincipal: expectedPrincipal,
          );
          _owners.requireCurrent(owner);
          if (fallback.kind == RelayRouteKind.relay) {
            await _sendTextViaRelay(message, packet, fallback, owner);
            return;
          }
        } on Object {
          // คงข้อความในเครื่องเป็น pending เพื่อให้ QA ลองส่งใหม่ในรอบถัดไป
        }
        lastError = 'ส่งตรงไม่สำเร็จ และยังไม่มีเส้นทาง Relay ที่พร้อม';
        _log('เก็บข้อความ ${message.id} ไว้ pending หลัง Direct ล้มเหลว');
        notifyListeners();
        return;
      }
      await messages.markFailed(message.id, '$error');
      _fail('ส่งข้อความไม่สำเร็จ: $error');
    }
  }

  // ผูก principal ผู้ส่งและผู้รับกับซอง Text ก่อนใช้เส้นทาง Relay ที่ตรวจสอบไว้
  Future<void> _sendTextViaRelay(
    RelioMessage message,
    RelioPacket packet,
    RelayRoutePlan route,
    OwnerSnapshot owner,
  ) async {
    final engine = relayEngine;
    final middle = route.middleDeviceId;
    if (!qaPlaintextTextEnabled || engine == null || middle == null) {
      return;
    }
    try {
      if (message.conversationId == null ||
          conversations is! DriftConversationRepository) {
        throw const OwnerChangedException();
      }
      final localPrincipal = await _activePrincipal();
      final remotePrincipal =
          await (conversations as DriftConversationRepository)
              .remotePrincipalForConversation(message.conversationId!);
      _owners.requireCurrent(owner);
      if (!RelioPacket.validPrincipal(remotePrincipal)) {
        throw const OwnerChangedException();
      }
      final privatePacket = packet.withPrincipals(
        localPrincipal,
        remotePrincipal,
      );
      final maxHops = route.mode == RelayTextRouteMode.automatic
          ? RelayPolicy.qaAutomaticTextMaxHops
          : 2;
      final envelope = RelayEnvelope.fromPayloadPacket(
        packet: privatePacket,
        destinationDeviceId: route.destinationDeviceId,
        maxHops: maxHops,
      );
      final pinFirstHop =
          route.mode == RelayTextRouteMode.qaForcedRelay || route.forceFirstHop;
      final result = pinFirstHop
          ? await engine.enqueueQaEnvelopeVia(
              envelope,
              firstHopDeviceId: middle,
            )
          : await engine.enqueueEnvelope(envelope);
      _owners.requireCurrent(owner);
      if (result == RelayResult.blocked || result == RelayResult.expired) {
        await messages.markFailed(message.id, result.name);
        return;
      }
      diagnostics?.record(
        'relay',
        'text_route_started',
        peerIdentifier: route.destinationDeviceId,
        fields: {
          'payloadAlias': DiagnosticsLogService.peerAlias(message.id),
          'relayPacketAlias': DiagnosticsLogService.peerAlias(
            envelope.packetId,
          ),
          'originAlias': DiagnosticsLogService.peerAlias(route.sourceDeviceId),
          'middleAlias': DiagnosticsLogService.peerAlias(middle),
          'firstHopIsPinned': pinFirstHop,
          'destinationAlias': DiagnosticsLogService.peerAlias(
            route.destinationDeviceId,
          ),
          'routeMode': route.mode.name,
          'hopCount': 0,
          'maxHops': maxHops,
        },
      );
      lastSentPacket = _diagnosticPacket(packet);
      _log('เริ่มส่ง textMessage ${message.id} ผ่าน Relay');
      notifyListeners();
    } on Object catch (error) {
      await messages.markFailed(message.id, '$error');
      _fail('ส่งข้อความผ่าน Relay ไม่สำเร็จ: $error');
    }
  }

  Future<void> sendLocationMessage(RelioMessage message) => _owners
      .run(() => _sendLocationMessageOwned(message))
      .catchError((Object _) {});

  Future<void> _sendLocationMessageOwned(RelioMessage message) async {
    if (message.latitude == null || message.longitude == null) {
      await messages.markFailed(message.id, 'location_unavailable');
      return;
    }
    final peerId = await _endpointForMessage(message);
    if (peerId == null) return;
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
      await _sendApplicationBytes(packet, peerId: peerId);
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
            peerId: peerId,
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
    RelioMediaAttachment attachment, {
    Stopwatch? pipelineClock,
  }) => _owners
      .run(() => _sendMediaOwned(message, attachment, pipelineClock))
      .catchError((Object _) {});

  Future<void> _sendMediaOwned(
    RelioMessage message,
    RelioMediaAttachment attachment,
    Stopwatch? suppliedPipelineClock,
  ) async {
    if (attachments == null || mediaStorage == null) return;
    final peerId = await _endpointForMessage(message);
    if (peerId == null) {
      _recordMediaStage(null, 'media_queued_offline');
      return;
    }
    var sendCheckpoint = 'integrity';
    try {
      final pipelineClock = suppliedPipelineClock ?? (Stopwatch()..start());
      _mediaPipelineClocks[attachment.transferId] = pipelineClock;
      _recordMediaStage(
        peerId,
        'MEDIA_PIPELINE_STARTED',
        fields: {
          'traceId': attachment.transferId,
          'messageId': message.id,
          'attachmentId': attachment.id,
        },
      );
      if (readRuntimeSnapshot != null) {
        try {
          final snapshot = await readRuntimeSnapshot!();
          _recordMediaStage(
            peerId,
            'MEDIA_ENVIRONMENT_SNAPSHOT',
            fields: {
              'traceId': attachment.transferId,
              'messageId': message.id,
              'attachmentId': attachment.id,
              'wifiEnabled': snapshot.wifiEnabled,
              'bluetoothEnabled': snapshot.bluetoothEnabled,
              'internetValidated': snapshot.internetValidated,
              'hasInternetRoute': snapshot.hasInternetRoute,
              'appLifecycleState': appLifecycleState,
              'nearbyConnected': connectedPeers.isNotEmpty,
              'activeNetworkType': 'not_exposed',
              'wifiAssociated': 'not_exposed',
            },
          );
        } on Object {
          _recordMediaStage(peerId, 'MEDIA_ENVIRONMENT_SNAPSHOT_UNAVAILABLE');
        }
      }
      _recordMediaStage(
        peerId,
        'INTEGRITY_CHECK_START',
        fields: {
          'traceId': attachment.transferId,
          'messageId': message.id,
          'attachmentId': attachment.id,
          'mediaType': attachment.mediaType.name,
          'sizeBytes': attachment.byteSize,
        },
      );
      final remote = conversations is DriftConversationRepository
          ? await (conversations as DriftConversationRepository)
                .remotePrincipalForConversation(message.conversationId!)
          : null;
      if (_remotePrincipals[peerId] != remote ||
          !RelioPacket.validPrincipal(remote)) {
        return;
      }
      sendCheckpoint = 'file';
      _recordMediaStage(
        peerId,
        'FILE_SEND_START',
        fields: {
          'traceId': attachment.transferId,
          'messageId': message.id,
          'attachmentId': attachment.id,
          'sizeBytes': attachment.byteSize,
          'payloadType': 'FILE',
          'direction': 'TX',
        },
      );
      _owners.requireCurrent(_owners.capture());
      final hashClock = Stopwatch()..start();
      // เริ่ม Nearby ก่อนอ่านไฟล์ทั้งก้อนเพื่อให้การตรวจ SHA-256 ซ้อนกับช่วงส่งได้
      final fileAndHash = await Future.wait<String>([
        transport.sendFile(attachment.localPath, peerId: peerId),
        mediaStorage!.sha256ForFile(attachment.localPath),
      ]);
      final payloadId = fileAndHash[0];
      final digest = fileAndHash[1];
      _recordMediaStage(
        peerId,
        'INTEGRITY_CHECK_RESULT',
        fields: {
          'traceId': attachment.transferId,
          'messageId': message.id,
          'attachmentId': attachment.id,
          'durationMs': hashClock.elapsedMilliseconds,
          'result': 'success',
          'direction': 'TX',
        },
      );
      _owners.requireCurrent(_owners.capture());
      _payloadTransferIds[payloadId] = attachment.transferId;
      _recordMediaStage(
        peerId,
        'FILE_SEND_ACCEPTED',
        fields: {
          'traceId': attachment.transferId,
          'messageId': message.id,
          'attachmentId': attachment.id,
          'payloadId': payloadId,
          'payloadType': 'FILE',
          'direction': 'TX',
        },
      );
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
      _recordMediaStage(
        peerId,
        'METADATA_SEND_START',
        fields: {
          'traceId': attachment.transferId,
          'messageId': message.id,
          'attachmentId': attachment.id,
          'filePayloadId': payloadId,
          'payloadType': 'BYTES',
          'direction': 'TX',
        },
      );
      sendCheckpoint = 'metadata';
      final metadataClock = Stopwatch()..start();
      final metadataPayloadId = await _sendApplicationBytes(
        packet,
        peerId: peerId,
      );
      _recordMediaStage(
        peerId,
        'METADATA_SEND_SUCCESS',
        fields: {
          'traceId': attachment.transferId,
          'messageId': message.id,
          'attachmentId': attachment.id,
          'payloadId': metadataPayloadId,
          'filePayloadId': payloadId,
          'durationMs': metadataClock.elapsedMilliseconds,
          'payloadType': 'BYTES',
          'direction': 'TX',
        },
      );
      _mediaAckClocks[attachment.transferId] = Stopwatch()..start();
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
            peerId: peerId,
            bytes: ack.toBytes(),
          );
        });
      }
    } on Object catch (error) {
      _mediaAckClocks.remove(attachment.transferId);
      _mediaPipelineClocks.remove(attachment.transferId);
      _recordMediaStage(
        peerId,
        switch (sendCheckpoint) {
          'integrity' => 'INTEGRITY_CHECK_FAILURE',
          'file' => 'FILE_FAILURE',
          _ => 'METADATA_SEND_FAILURE',
        },
        severity: 'error',
        reason: 'media_send_stage_failed',
        nativeCode: _errorCode(error),
        fields: {
          'traceId': attachment.transferId,
          'messageId': message.id,
          'attachmentId': attachment.id,
          'checkpoint': sendCheckpoint,
        },
      );
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
    final deviceId = await _destinationDeviceForMessage(message);
    return deviceId == null ? null : deviceToEndpointId[deviceId];
  }

  Future<String?> _destinationDeviceForMessage(RelioMessage message) async {
    final conversationId = message.conversationId;
    if (conversationId == null) return null;
    final conversation = await conversations.getConversation(conversationId);
    if (conversation == null) return null;
    return conversation.participantId;
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
      await _sendApplicationBytes(packet, peerId: peerId);
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
    _endpointLifecycle[peer.endpointId] = peer;
    if (peer.isLost) {
      final activeAttempt = _activeTransportAttempts[peer.endpointId];
      final state = peerStates[peer.endpointId];
      final activeNegotiation =
          activeAttempt != null &&
          (state == NearbyConnectionState.connecting ||
              state == NearbyConnectionState.incomingRequest);
      if (activeAttempt != null) {
        activeAttempt
          ..['endpointLostDuringAttempt'] = true
          ..['discoveryVisibility'] = 'lost'
          ..['discoveryVisibilityLostAt'] =
              (peer.lostAt ?? DateTime.now().toUtc()).toIso8601String()
          ..['discoveryVisibilityLostEpoch'] = peer.discoveryEpoch;
      }
      diagnostics?.record(
        'nearby',
        'endpoint_visibility_lost',
        connectionTraceId: _connectionTraces[peer.endpointId],
        operation: 'onEndpointLost',
        peerIdentifier: peer.endpointId,
        fields: {
          'activeNegotiation': activeNegotiation,
          'negotiationPhase': _connectionPhases[peer.endpointId]?.name,
          'discoveryEpoch': peer.discoveryEpoch,
          'currentDiscoveryEpoch': transport.discoveryEpoch,
          'foundAt': peer.foundAt?.toIso8601String(),
          'lostAt': peer.lostAt?.toIso8601String(),
          'endpointAgeMs': peer.foundAt == null
              ? null
              : DateTime.now().toUtc().difference(peer.foundAt!).inMilliseconds,
          'isMarkedLost': true,
        },
      );
      if (activeNegotiation) {
        diagnostics?.record(
          'connection',
          'endpoint_loss_ignored_for_active_negotiation',
          severity: 'warning',
          connectionTraceId: _connectionTraces[peer.endpointId],
          operation: 'onEndpointLost',
          peerIdentifier: peer.endpointId,
          fields: {
            'activeNegotiation': true,
            'negotiationPhase': _connectionPhases[peer.endpointId]?.name,
            'discoveryEpoch': peer.discoveryEpoch,
            'appLifecycleState': appLifecycleState,
            'screenRoute': screenRoute,
          },
        );
        // แยก discovery visibility ออกจาก ConnectionLifecycle; attempt ที่กำลังทำงาน
        // ต้องรอ native callback ต่อ จึงไม่ยกเลิก timer หรือ state เดิม
        discoveredPeers.removeWhere(
          (item) => item.endpointId == peer.endpointId,
        );
      } else {
        _finishTransportAttempt(
          peer.endpointId,
          connected: false,
          endpointLost: true,
        );
        if (state != NearbyConnectionState.connected) {
          discoveredPeers.removeWhere(
            (item) => item.endpointId == peer.endpointId,
          );
        }
      }
      _log(
        'endpoint lost alias=${DiagnosticsLogService.peerAlias(peer.endpointId)}',
      );
      notifyListeners();
      return;
    }
    final index = discoveredPeers.indexWhere((item) => item.id == peer.id);
    diagnostics?.record(
      'nearby',
      index == -1 ? 'endpoint_found' : 'endpoint_refreshed',
      operation: 'onEndpointFound',
      peerIdentifier: peer.endpointId,
      fields: {
        'discoveryEpoch': peer.discoveryEpoch,
        'currentDiscoveryEpoch': transport.discoveryEpoch,
        'foundAt': peer.foundAt?.toIso8601String(),
        'lastSeenAt': peer.lastSeenAt?.toIso8601String(),
        'endpointAgeMs': peer.foundAt == null
            ? null
            : DateTime.now().toUtc().difference(peer.foundAt!).inMilliseconds,
      },
    );
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
      final previous = discoveredPeers[index];
      final sameCandidate =
          peer.identityFingerprintHint == null ||
          previous.identityFingerprintHint == null ||
          peer.identityFingerprintHint == previous.identityFingerprintHint;
      if (!sameCandidate &&
          peerStates[peer.endpointId] == NearbyConnectionState.connected) {
        return;
      }
      // callback refresh อธิบาย endpoint ของ transport ไม่ใช่ RELIO identity ที่ยืนยันแล้ว
      // จึงคง field ที่ได้จาก handshake ไว้เมื่อ metadata เปลี่ยน      // Transport refresh callbacks describe an endpoint, not the authenticated
      // RELIO identity. Keep handshake-owned fields across a metadata refresh.
      discoveredPeers[index] = NearbyPeer(
        id: peer.endpointId,
        // Android อาจ refresh endpoint ด้วย fingerprint alias ชั่วคราวหลัง hello
        // เมื่อผูกกับ RELIO device แล้ว ให้คงชื่อ Profile ที่ยืนยันไว้จนมี hello ใหม่ที่ผ่านการตรวจ        // Android may refresh the endpoint with its temporary fingerprint
        // alias after hello. Once mapped to a RELIO device, keep the verified
        // Profile name until another verified hello updates it.
        name: previous.deviceId == null || !sameCandidate
            ? peer.name
            : previous.name,
        connected:
            peer.connected ||
            peerStates[peer.endpointId] == NearbyConnectionState.connected,
        deviceId: peer.deviceId ?? (sameCandidate ? previous.deviceId : null),
        identityFingerprintHint:
            peer.identityFingerprintHint ?? previous.identityFingerprintHint,
        capabilities: peer.capabilities.isEmpty
            ? previous.capabilities
            : peer.capabilities,
        discoveryEpoch: peer.discoveryEpoch,
        foundAt: peer.foundAt,
        lastSeenAt: peer.lastSeenAt,
        isCurrent: peer.isCurrent,
      );
    }
    final activeAttempt = _activeTransportAttempts[peer.endpointId];
    if (activeAttempt != null) {
      activeAttempt['discoveryVisibility'] = 'visible';
      _markTransportPhase(peer.endpointId, 'endpointRefound');
    }
    peerStates.putIfAbsent(
      peer.endpointId,
      () => peer.connected
          ? NearbyConnectionState.connected
          : NearbyConnectionState.disconnected,
    );
    _log(
      'endpoint found alias=${DiagnosticsLogService.peerAlias(peer.endpointId)}',
    );
    notifyListeners();
    final fingerprint = peer.identityFingerprintHint;
    if (fingerprint != null &&
        _freshEndpointRetryByFingerprint.containsKey(fingerprint) &&
        isEndpointCurrent(peer.endpointId)) {
      final automatic = _freshEndpointRetryByFingerprint.remove(fingerprint)!;
      _freshEndpointRetryEndpoints.add(peer.endpointId);
      diagnostics?.record(
        'connection',
        'fresh_endpoint_retry_started',
        connectionTraceId: _connectionTraces[peer.endpointId],
        operation: 'requestConnection',
        peerIdentifier: peer.endpointId,
        fields: {'discoveryEpoch': peer.discoveryEpoch},
      );
      _track(_connect(peer.endpointId, userInitiated: !automatic));
      return;
    }
    _track(_maybeReconnect(peer));
  }

  void _invalidateEndpoint(String endpointId, {DateTime? lostAt}) {
    final peer =
        discoveredPeers
            .where((candidate) => candidate.endpointId == endpointId)
            .firstOrNull ??
        _endpointLifecycle[endpointId];
    if (peer == null) return;
    final invalid = NearbyPeer(
      id: peer.id,
      name: peer.name,
      deviceId: peer.deviceId,
      connected: peer.connected,
      identityFingerprintHint: peer.identityFingerprintHint,
      capabilities: peer.capabilities,
      isLost: true,
      discoveryEpoch: peer.discoveryEpoch,
      foundAt: peer.foundAt,
      lastSeenAt: peer.lastSeenAt,
      lostAt: lostAt ?? DateTime.now().toUtc(),
      isCurrent: false,
    );
    _endpointLifecycle[endpointId] = invalid;
    discoveredPeers.removeWhere(
      (candidate) => candidate.endpointId == endpointId,
    );
    diagnostics?.record(
      'nearby',
      'endpoint_invalidated',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'endpointLifecycle',
      peerIdentifier: endpointId,
      fields: {
        'discoveryEpoch': invalid.discoveryEpoch,
        'currentDiscoveryEpoch': transport.discoveryEpoch,
        'foundAt': invalid.foundAt?.toIso8601String(),
        'lostAt': invalid.lostAt?.toIso8601String(),
        'endpointAgeMs': invalid.foundAt == null
            ? null
            : DateTime.now()
                  .toUtc()
                  .difference(invalid.foundAt!)
                  .inMilliseconds,
        'isCurrentEpoch': invalid.discoveryEpoch == transport.discoveryEpoch,
        'isMarkedLost': true,
      },
    );
  }

  Future<void> _maybeReconnect(NearbyPeer peer) async {
    final cancellationEpoch = _connectionCancellationEpochs[peer.endpointId];
    if (_diagnosticRole != NearbyDiagnosticRole.auto) {
      diagnostics?.record(
        'trust',
        'auto_reconnect_suppressed',
        operation: 'candidateLookup',
        peerIdentifier: peer.endpointId,
        reason: 'qa_role_control_active',
        fields: {'qaRole': _diagnosticRole.name},
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
    if (_closed ||
        _connectionCancellationEpochs[peer.endpointId] != cancellationEpoch) {
      return;
    }
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
    if (_qaRestrictionActive && device.deviceId == _qaRestrictedDeviceId) {
      diagnostics?.record(
        'connection',
        'qa_direct_link_reconnect_suppressed',
        operation: 'candidateLookup',
        peerIdentifier: peer.endpointId,
        reason: 'qa_pair_restriction',
      );
      return;
    }
    final discoveredIndex = discoveredPeers.indexWhere(
      (item) => item.endpointId == peer.endpointId,
    );
    if (discoveredIndex != -1 && isEndpointCurrent(peer.endpointId)) {
      // fingerprint hint ใช้ผูก presentation กับแถวเดิมเท่านั้น ไม่สร้าง authenticated endpoint mapping
      discoveredPeers[discoveredIndex] = discoveredPeers[discoveredIndex]
          .withIdentity(deviceId: device.deviceId, name: device.displayName);
      notifyListeners();
    }
    final activeEndpoint =
        deviceToEndpointId[device.deviceId] ??
        _fingerprintEndpointReservations[hint];
    if (activeEndpoint != null &&
        activeEndpoint != peer.endpointId &&
        (peerStates[activeEndpoint] == NearbyConnectionState.connected ||
            peerStates[activeEndpoint] == NearbyConnectionState.connecting ||
            peerStates[activeEndpoint] ==
                NearbyConnectionState.incomingRequest)) {
      return;
    }
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
    if (_closed ||
        _connectionCancellationEpochs[peer.endpointId] != cancellationEpoch) {
      return;
    }
    if (local.fingerprint.compareTo(hint) >= 0) {
      if (!_secondaryInitiatorFingerprints.contains(hint)) {
        if (!_secondaryInitiatorFallbackTimers.containsKey(hint)) {
          diagnostics?.record(
            'trust',
            'auto_reconnect_suppressed',
            operation: 'candidateLookup',
            peerIdentifier: peer.endpointId,
            reason: 'other_peer_is_initiator',
          );
        }
        _scheduleSecondaryInitiatorFallback(peer, hint);
        return;
      }
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
    if ((_reconnectAttemptCounts[hint] ?? 0) >= 5) {
      diagnostics?.record(
        'trust',
        'retry_exhausted',
        operation: 'autoReconnect',
        peerIdentifier: peer.endpointId,
        fields: {'attempt': _reconnectAttemptCounts[hint], 'source': 'budget'},
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
    if (_closed ||
        _connectionCancellationEpochs[peer.endpointId] != cancellationEpoch) {
      return;
    }
    final resultingState = peerStates[peer.endpointId];
    if (resultingState == null ||
        resultingState == NearbyConnectionState.disconnected) {
      _automaticConnectionAttempts.remove(hint);
      _reconnectFingerprintByEndpoint.remove(peer.endpointId);
    }
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

  void _scheduleSecondaryInitiatorFallback(
    NearbyPeer peer,
    String fingerprint,
  ) {
    if (_closed ||
        _secondaryInitiatorFingerprints.contains(fingerprint) ||
        _secondaryInitiatorFallbackTimers.containsKey(fingerprint) ||
        (_reconnectAttemptCounts[fingerprint] ?? 0) >= 5) {
      return;
    }
    final delay = connectionAttemptTimeout;
    diagnostics?.record(
      'trust',
      'secondary_initiator_fallback_scheduled',
      operation: 'autoReconnect',
      peerIdentifier: peer.endpointId,
      fields: {'delayMs': delay.inMilliseconds},
    );
    _secondaryInitiatorFallbackTimers[fingerprint] = Timer(delay, () {
      _secondaryInitiatorFallbackTimers.remove(fingerprint);
      if (_closed) return;
      _secondaryInitiatorFingerprints.add(fingerprint);
      diagnostics?.record(
        'trust',
        'secondary_initiator_fallback_started',
        operation: 'autoReconnect',
        peerIdentifier: peer.endpointId,
        fields: {
          'attempt': (_reconnectAttemptCounts[fingerprint] ?? 0) + 1,
          'endpointCurrent': isEndpointCurrent(peer.endpointId),
        },
      );
      if (isEndpointCurrent(peer.endpointId)) {
        _track(_maybeReconnect(peer));
      }
    });
  }

  void _cancelSecondaryInitiatorFallback(
    String fingerprint, {
    bool resetElection = false,
  }) {
    _secondaryInitiatorFallbackTimers.remove(fingerprint)?.cancel();
    if (resetElection) _secondaryInitiatorFingerprints.remove(fingerprint);
  }

  void _onConnection(NearbyConnectionEvent event) {
    final endpointId = event.peer.endpointId;
    final fingerprint =
        event.peer.identityFingerprintHint ??
        _reconnectFingerprintByEndpoint[endpointId] ??
        discoveredPeers
            .where((peer) => peer.endpointId == endpointId)
            .firstOrNull
            ?.identityFingerprintHint;
    if (fingerprint != null &&
        (event.state == NearbyConnectionState.incomingRequest ||
            event.state == NearbyConnectionState.connecting ||
            event.state == NearbyConnectionState.connected)) {
      _cancelSecondaryInitiatorFallback(fingerprint);
    }
    final currentTrace = _connectionTraces[endpointId];
    if ((event.connectionTraceId != null &&
            currentTrace != null &&
            event.connectionTraceId != currentTrace) ||
        (_retiredConnectionEndpoints.contains(endpointId) &&
            currentTrace == null &&
            !(event.state == NearbyConnectionState.incomingRequest &&
                event.isIncomingRequest))) {
      if (currentTrace == null &&
          event.state == NearbyConnectionState.disconnected) {
        final requested = _appDisconnectRequests.remove(endpointId);
        _recordIdentityStage(
          endpointId,
          'native_endpoint_disconnected',
          reason: requested?.reason ?? 'not_requested_by_app',
          fields: {
            'disconnectRequester': requested == null
                ? 'nearby_or_remote'
                : 'app',
            'appDisconnectRequestFresh':
                requested != null &&
                DateTime.now().toUtc().difference(requested.requestedAt) <=
                    const Duration(seconds: 5),
          },
        );
      }
      diagnostics?.record(
        'connection',
        'retired_session_callback_ignored',
        peerIdentifier: endpointId,
        operation: event.operation,
        stateTo: event.state.name,
      );
      return;
    }
    if (event.state == NearbyConnectionState.incomingRequest) {
      _retiredConnectionEndpoints.remove(endpointId);
    }
    if (event.state == NearbyConnectionState.failed &&
        event.rawStatusCode == 8003) {
      diagnostics?.record(
        'connection',
        'already_connected_status_reconciled',
        connectionTraceId:
            event.connectionTraceId ?? _connectionTraces[endpointId],
        operation: event.operation ?? 'onConnectionResult',
        peerIdentifier: endpointId,
        nativeCode: event.rawStatusCode,
        reason: 'native_endpoint_already_connected',
      );
      // 8003 ยืนยันว่า endpoint เชื่อมต่ออยู่แล้ว จึงเริ่ม identity handshake ต่อ
      // โดยไม่เปิดทางส่งข้อมูล RELIO จนกว่า peer จะผ่านการยืนยันตัวตน
      if (peerStates[endpointId] == NearbyConnectionState.connected) return;
      _onConnection(
        NearbyConnectionEvent(
          peer: NearbyPeer(
            id: endpointId,
            name: event.peer.name,
            connected: true,
            deviceId: event.peer.deviceId ?? endpointToDeviceId[endpointId],
            identityFingerprintHint: event.peer.identityFingerprintHint,
          ),
          state: NearbyConnectionState.connected,
          rawStatusCode: event.rawStatusCode,
          rawStatusName:
              event.rawStatusName ?? 'STATUS_ALREADY_CONNECTED_TO_ENDPOINT',
          rawStatusMessage: event.rawStatusMessage,
          operation: event.operation ?? 'onConnectionResult',
          role: event.role,
          connectionTraceId: event.connectionTraceId,
        ),
      );
      return;
    }
    if (event.state == NearbyConnectionState.connected ||
        event.state == NearbyConnectionState.failed ||
        event.state == NearbyConnectionState.disconnected) {
      // ยกเลิก timer ก่อนบันทึก callback เพื่อไม่ให้ native failure
      // แข่งกับ soft timeout เก่าแล้วถูกระบุสาเหตุผิด
      _cancelConnectionTimers(endpointId);
      _nativeAcceptInFlight.remove(endpointId);
    }
    if (event.connectionTraceId != null) {
      _connectionTraces.putIfAbsent(endpointId, () => event.connectionTraceId!);
    }
    if (event.state == NearbyConnectionState.connected ||
        event.state == NearbyConnectionState.failed ||
        event.state == NearbyConnectionState.disconnected) {
      final traceId = _connectionTraces.putIfAbsent(
        endpointId,
        () => event.connectionTraceId ?? const Uuid().v4(),
      );
      diagnostics?.record(
        'connection',
        'transport_connection_state',
        connectionTraceId: traceId,
        operation: event.operation ?? 'connectionEvent',
        stateFrom: peerStates[endpointId]?.name ?? 'unknown',
        stateTo: event.state.name,
        peerIdentifier: endpointId,
        fields: {
          'role':
              event.role ??
              (event.isIncomingRequest ? 'responder' : 'initiator'),
          'remoteBluetoothAddress': endpointId.startsWith('classic:')
              ? endpointId.substring('classic:'.length)
              : null,
          'remoteRelioDeviceId': endpointToDeviceId[endpointId],
          'sessionId': traceId,
        },
      );
      diagnostics?.record(
        'lifecycle',
        event.state == NearbyConnectionState.connected
            ? 'NEARBY_CONNECTED'
            : event.state == NearbyConnectionState.disconnected
            ? 'NEARBY_DISCONNECTED'
            : 'NEARBY_CONNECTION_FAILED',
        connectionTraceId: traceId,
        peerIdentifier: endpointId,
        stateTo: event.state.name,
        fields: {'appLifecycleState': appLifecycleState},
      );
    }
    if (event.state == NearbyConnectionState.incomingRequest) {
      final traceId = _connectionTraces.putIfAbsent(
        endpointId,
        () => const Uuid().v4(),
      );
      _connectionStartedAt.putIfAbsent(endpointId, DateTime.now().toUtc);
      if (!_activeTransportAttempts.containsKey(endpointId)) {
        _beginTransportAttempt(
          endpointId,
          role: event.isIncomingRequest ? 'responder' : 'initiator',
        );
      }
      _markTransportPhase(endpointId, 'onConnectionInitiated');
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
          'qaRole': _diagnosticRole.name,
          'callbackRole': event.isIncomingRequest ? 'responder' : 'initiator',
          'userInitiatedAttempt': _userInitiatedEndpoints.contains(endpointId),
          ..._radioSnapshotFields(),
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
      // Both endpoints accept Native to exchange the signed identity proof.
      final initiatorAttemptIsConnecting =
          peerStates[endpointId] == NearbyConnectionState.connecting;
      // manual connect อาจชน trusted auto reconnect ของอีกฝั่งบน endpoint เดียวกัน
      // ต้อง accept native ครั้งเดียวและยังตรวจ cryptographic proof ตามเดิม
      if (event.isIncomingRequest &&
          initiatorAttemptIsConnecting &&
          fingerprint != null &&
          !_nativeAcceptInFlight.contains(endpointId) &&
          !pendingConnectionRequests.containsKey(endpointId)) {
        _track(_acceptKnownPeerRequest(resolvedEvent, fingerprint));
        return;
      }
      if (!event.isIncomingRequest &&
          (_userInitiatedEndpoints.contains(endpointId) ||
              initiatorAttemptIsConnecting)) {
        if (fingerprint != null) {
          _track(_acceptKnownPeerRequest(resolvedEvent, fingerprint));
          return;
        }
        diagnostics?.record(
          'connection',
          'initiator_verification_prompt_queued',
          connectionTraceId: traceId,
          operation: 'queueIncomingRequest',
          stateFrom: 'connecting',
          stateTo: 'incomingRequest',
          peerIdentifier: endpointId,
          fields: {
            'qaRole': _diagnosticRole.name,
            'userInitiatedEndpointTracked': _userInitiatedEndpoints.contains(
              endpointId,
            ),
            'connectingAtCallback': initiatorAttemptIsConnecting,
            'authenticationCodeAvailable':
                resolvedEvent.authenticationToken != null,
          },
        );
        _track(_acceptNativeForIdentityProof(endpointId));
        return;
      }
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
        _reconnectFingerprintByEndpoint[endpointId] ??
        discoveredPeers
            .where((peer) => peer.endpointId == endpointId)
            .firstOrNull
            ?.identityFingerprintHint;
    final wasAutomaticInitiator =
        eventFingerprint != null &&
        _automaticConnectionAttempts.contains(eventFingerprint);
    if (event.state == NearbyConnectionState.failed ||
        event.state == NearbyConnectionState.disconnected) {
      if (eventFingerprint != null) {
        _automaticConnectionAttempts.remove(eventFingerprint);
      }
      if (event.state == NearbyConnectionState.failed) {
        final fingerprint = eventFingerprint;
        final rawStatusCode = event.rawStatusCode;
        if (rawStatusCode == 8011) {
          final outgoing =
              _userInitiatedEndpoints.contains(endpointId) ||
              wasAutomaticInitiator;
          _invalidateEndpoint(endpointId);
          final isBoundedRetry = _freshEndpointRetryEndpoints.contains(
            endpointId,
          );
          if (outgoing &&
              !isBoundedRetry &&
              fingerprint != null &&
              !_freshEndpointRetryByFingerprint.containsKey(fingerprint)) {
            _freshEndpointRetryByFingerprint[fingerprint] =
                !_userInitiatedEndpoints.contains(endpointId);
            diagnostics?.record(
              'connection',
              'stale_endpoint_invalidated',
              severity: 'warning',
              connectionTraceId: _connectionTraces[endpointId],
              operation: event.operation ?? 'onConnectionResult',
              peerIdentifier: endpointId,
              nativeCode: rawStatusCode,
              fields: {'stablePeerHintAvailable': true},
            );
            diagnostics?.record(
              'connection',
              'fresh_endpoint_wait_started',
              connectionTraceId: _connectionTraces[endpointId],
              operation: 'onEndpointFound',
              peerIdentifier: endpointId,
              fields: {'retryLimit': 1},
            );
          }
          _freshEndpointRetryEndpoints.remove(endpointId);
        } else if (fingerprint != null && rawStatusCode != 13) {
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
    final wasConnected =
        peerStates[endpointId] == NearbyConnectionState.connected;
    peerStates[endpointId] = event.state;
    if (event.state == NearbyConnectionState.failed &&
        RelioBuildInfo.developerDiagnosticsEnabled) {
      lastNativeConnectionFailure = event;
      lastDiagnostic = event.rawStatusName ?? event.error;
    }
    if (event.state == NearbyConnectionState.connected ||
        event.state == NearbyConnectionState.failed) {
      diagnostics?.record(
        'connection',
        'connection_resolution_applied',
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
          'resolution': event.state == NearbyConnectionState.failed
              ? 'failure'
              : 'success',
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
            'googlePlayServicesVersionName':
                event.googlePlayServicesVersionName,
          if (RelioBuildInfo.developerDiagnosticsEnabled &&
              event.googlePlayServicesVersionCode != null)
            'googlePlayServicesVersionCode':
                event.googlePlayServicesVersionCode,
          if (RelioBuildInfo.developerDiagnosticsEnabled &&
              event.nearbyLibraryVersion != null)
            'nearbyLibraryVersion': event.nearbyLibraryVersion,
          if (RelioBuildInfo.developerDiagnosticsEnabled &&
              event.playServicesNearbyDependencyVersion != null)
            'playServicesNearbyDependencyVersion':
                event.playServicesNearbyDependencyVersion,
          if (_connectionStartedAt[endpointId] case final start?)
            'durationMs': DateTime.now()
                .toUtc()
                .difference(start)
                .inMilliseconds,
          ..._radioSnapshotFields(),
        },
      );
    }
    if (event.state == NearbyConnectionState.connected ||
        event.state == NearbyConnectionState.failed ||
        event.state == NearbyConnectionState.disconnected) {
      if (event.state != NearbyConnectionState.disconnected) {
        _markTransportPhase(endpointId, 'nativeNegotiationEnded');
      }
      _finishTransportAttempt(
        endpointId,
        connected: event.state == NearbyConnectionState.connected,
        nativeStatusCode: event.rawStatusCode,
        nativeStatusName: event.rawStatusName,
      );
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
            'endpointCurrentAtRequest': _transportAttemptResults
                .where(
                  (result) =>
                      result['endpointAlias'] ==
                          DiagnosticsLogService.peerAlias(endpointId) &&
                      result['attemptId'] ==
                          (event.connectionTraceId ??
                                  _connectionTraces[endpointId])
                              ?.substring(0, 4)
                              .toUpperCase(),
                )
                .firstOrNull?['endpointCurrentAtRequest'],
            'endpointEpochMatchesCurrent': isEndpointCurrent(endpointId),
            'endpointLostDuringAttempt': _transportAttemptResults
                .where(
                  (result) =>
                      result['endpointAlias'] ==
                          DiagnosticsLogService.peerAlias(endpointId) &&
                      result['attemptId'] ==
                          (event.connectionTraceId ??
                                  _connectionTraces[endpointId])
                              ?.substring(0, 4)
                              .toUpperCase(),
                )
                .firstOrNull?['endpointLostDuringAttempt'],
            'discoveryActive': isDiscovering,
            'advertisingActive': isAdvertising,
            'configuredStrategy': transport.strategyName,
            'lifecycleState': appLifecycleState,
            'sessionRestartDeferred': _sessionRestartDeferred,
            'googlePlayServicesVersionName':
                nativeTransportSnapshot['googlePlayServicesVersionName'],
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
      _remotePrincipals.remove(endpointId);
      _remotePrincipalEpochs.remove(endpointId);
      _remoteProfileRevisions.remove(endpointId);
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
      final previous = index == -1
          ? _endpointLifecycle[endpointId] ?? event.peer
          : discoveredPeers[index];
      final peer = previous.withIdentity(
        connected: true,
        deviceId: endpointToDeviceId[endpointId],
        fingerprint: event.peer.identityFingerprintHint,
      );
      if (index == -1) {
        discoveredPeers.add(peer);
      } else {
        discoveredPeers[index] = peer;
      }
      _track(_beginPeerHandshake(endpointId));
    } else if (event.state == NearbyConnectionState.failed) {
      _identityHandshakeTimeouts.remove(endpointId)?.cancel();
      peerErrors[endpointId] = event.error ?? 'connection failed';
    }
    if (event.state == NearbyConnectionState.failed ||
        event.state == NearbyConnectionState.disconnected) {
      _clearConnectionSession(
        endpointId,
        cancelRetry: event.state == NearbyConnectionState.disconnected,
      );
      if (_endpointLifecycle[endpointId]?.isLost == true) {
        discoveredPeers.removeWhere((peer) => peer.endpointId == endpointId);
      }
    }
    if (event.error != null) peerErrors[endpointId] = event.error!;
    _log(
      'connection state=${event.state.name} '
      'endpoint=${DiagnosticsLogService.peerAlias(endpointId)}'
      '${event.error == null ? '' : ' code=${_errorCode(event.error!)}'}',
    );
    if (event.state == NearbyConnectionState.disconnected ||
        event.state == NearbyConnectionState.failed) {
      _track(
        _resumeDiscoveryAfterNegotiation(
          event.state == NearbyConnectionState.failed
              ? 'failure'
              : 'disconnected',
        ),
      );
      _connectionTraces.remove(endpointId);
      _connectionStartedAt.remove(endpointId);
      _connectionPhases.remove(endpointId);
      _connectionPhaseStartedAt.remove(endpointId);
    }
    if (!hasActiveConnectionAttempts) _sessionRestartDeferred = false;
    if (wasConnected && event.state == NearbyConnectionState.disconnected) {
      _track(_recoverDiscoveryAfterDisconnect());
    }
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
    await _acceptNativeForIdentityProof(event.peer.endpointId);
  }

  Future<void> _acceptNativeForIdentityProof(String endpointId) async {
    _approvedConnectionEndpoints.add(endpointId);
    await acceptConnectionRequest(endpointId);
  }

  Future<void> _handshakeAndShareCurrentSos(String endpointId) async {
    _log(
      'connection result=connected endpoint=${DiagnosticsLogService.peerAlias(endpointId)}',
    );
    _log('hello send endpoint=${DiagnosticsLogService.peerAlias(endpointId)}');
    await sendHello(peerId: endpointId);
    final deviceId = await identity.getDeviceId();
    final latest = await sos?.readLatest(ownerDeviceId: deviceId);
    if (latest != null) await sendSos(latest, peerId: endpointId);
  }

  Future<void> _beginPeerHandshake(String endpointId) async {
    final traceId = _connectionTraces[endpointId];
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
      await _handshakeAndShareCurrentSos(endpointId);
      if (!_isCurrentConnectionSession(endpointId, traceId)) return;
      _completedIdentityHandshakes.add(endpointId);
      unawaited(relayEngine?.forwardPending());
      _identityHandshakeTimeouts.remove(endpointId)?.cancel();
      unawaited(_locationCoordinator?.onPeerHandshakeCompleted(endpointId));
      return;
    }
    try {
      await _sendIdentityChallenge(endpointId);
    } on Object catch (error) {
      if (!_isCurrentConnectionSession(endpointId, traceId)) return;
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
    if (event == 'identity_handshake_completed') {
      _track(_resumeDiscoveryAfterNegotiation('identity_stabilized'));
    }
  }

  void _queueIncomingRequest(NearbyConnectionEvent event) {
    final endpointId = event.peer.endpointId;
    final isNewRequest = !pendingConnectionRequests.containsKey(endpointId);
    pendingConnectionRequests[endpointId] = event;
    peerStates[endpointId] = event.state;
    _setConnectionPhase(endpointId, NearbyConnectionPhase.awaitingApproval);
    if (isNewRequest) {
      _connectionSoftTimeouts.remove(endpointId)?.cancel();
      _connectionSoftTimeouts[endpointId] = Timer(incomingApprovalTimeout, () {
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
      fields: {
        'approvalTimeoutMs': incomingApprovalTimeout.inMilliseconds,
        'isIncomingRequest': event.isIncomingRequest,
      },
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
    final event = pendingConnectionRequests[endpointId];
    if (event == null || _closed) return;
    await disconnect(endpointId, reason: 'incoming_request_timeout');
    if (_closed || _connectionTraces.containsKey(endpointId)) return;
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
      fields: {'approvalTimeoutMs': incomingApprovalTimeout.inMilliseconds},
    );
    notifyListeners();
  }

  Future<void> _acceptKnownPeerRequest(
    NearbyConnectionEvent event,
    String fingerprintHint,
  ) async {
    final endpointId = event.peer.endpointId;
    final traceId = _connectionTraces[endpointId];
    final devices = await nearbyDevices.listDevices();
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
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
      await _acceptNativeForIdentityProof(endpointId);
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
      if (identityCrypto is MockPeerIdentityCrypto) {
        _queueIncomingRequest(event);
        return;
      }
      await _acceptNativeForIdentityProof(endpointId);
      return;
    }
    diagnostics?.record(
      'trust',
      'trusted_reconnect_auto_accepting_transport',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'acceptConnection',
      peerIdentifier: endpointId,
      fields: {'identityProofRequired': true},
    );
    _approvedConnectionEndpoints.add(endpointId);
    await acceptConnectionRequest(endpointId);
  }

  Future<void> _sendIdentityChallenge(String endpointId) async {
    final traceId = _connectionTraces[endpointId];
    if (_identityChallenges.containsKey(endpointId)) {
      _recordIdentityStage(
        endpointId,
        'identity_challenge_suppressed',
        reason: 'challenge_already_pending',
      );
      return;
    }
    final localId = await identity.getDeviceId();
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
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
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
    await _sendApplicationBytes(packet, peerId: endpointId);
    _recordIdentityStage(endpointId, 'identity_challenge_sent');
  }

  Future<void> _handleIdentityChallenge(
    String endpointId,
    RelioPacket packet,
  ) async {
    final traceId = _connectionTraces[endpointId];
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
    _recordIdentityStage(endpointId, 'identity_challenge_received');
    final payload = packet.payload;
    final challengeId = payload['challengeId']! as String;
    final nonce = payload['nonce']! as String;
    final localId = await identity.getDeviceId();
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
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
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
    final signed = identityChallengeMessage(
      challengeId: challengeId,
      nonce: nonce,
      challengerDeviceId: packet.senderDeviceId,
      responderDeviceId: localId,
    );
    final signature = await identityCrypto.sign(signed);
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
    final proof = RelioPacket.identityProof(
      senderDeviceId: localId,
      senderUserId: await _senderUserId(),
      challengeId: challengeId,
      nonce: nonce,
      challengerDeviceId: packet.senderDeviceId,
      displayName: await identity.getDisplayName(),
      status: (await currentStatus()).name,
      capabilities: RelioBuildInfo.isTest
          ? [
              'textMessage',
              'deviceStatus',
              'ack',
              'relay-v1',
              if (qaPlaintextTextEnabled) _qaTextRelayCapability,
              nearbyReachabilityCapability,
              'avatar-v1',
            ]
          : const [
              'textMessage',
              'deviceStatus',
              'ack',
              'relay-v1',
              nearbyReachabilityCapability,
            ],
      publicKey: own.publicKey,
      fingerprint: own.fingerprint,
      signature: signature,
    );
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
    _recordIdentityStage(endpointId, 'identity_response_created');
    _recordIdentityStage(endpointId, 'identity_public_key_sent');
    await transport.sendBytes(proof.toBytes(), peerId: endpointId);
    _recordIdentityStage(endpointId, 'identity_response_sent');
  }

  Future<void> _handleIdentityProof(
    String endpointId,
    RelioPacket packet,
  ) async {
    final traceId = _connectionTraces[endpointId];
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
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
      if (!_isCurrentConnectionSession(endpointId, traceId)) return;
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
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
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
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
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
    if (_qaRestrictionActive && deviceId == _qaRestrictedDeviceId) {
      diagnostics?.record(
        'connection',
        'qa_direct_link_rejected_after_identity_verification',
        connectionTraceId: traceId,
        operation: 'identityProof',
        peerIdentifier: endpointId,
        reason: 'qa_pair_restriction',
      );
      await disconnect(endpointId, reason: 'qa_direct_link_restriction');
      return;
    }
    final saved = await nearbyDevices.getDevice(deviceId);
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
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
    _recordIdentityStage(
      endpointId,
      'identity_proof_verified',
      fields: {'pinnedIdentityMatched': pinnedMatches},
    );
    final pendingIdentity = _PendingVerifiedIdentity(
      packet: packet,
      publicKey: publicKey,
      fingerprint: fingerprint,
      wasPinned: wasPinned,
      pinnedMatches: pinnedMatches,
      previousFingerprint: saved?.publicIdentityFingerprint,
    );
    final trustedAutoReconnect =
        pinnedMatches && saved.isTrusted && saved.autoReconnectEnabled;
    if (wasPinned && !pinnedMatches) {
      _recordIdentityStage(
        endpointId,
        'trusted_candidate_rejected_identity_mismatch',
        severity: 'error',
        reason: 'pinned_identity_mismatch',
      );
      peerErrors[endpointId] = 'identity_proof_invalid';
      await disconnect(endpointId, reason: 'pinned_identity_mismatch');
      return;
    }
    diagnostics?.record(
      'trust',
      'trusted_candidate_verified',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'identityProof',
      peerIdentifier: endpointId,
      fields: {'automaticTrustedReconnect': trustedAutoReconnect},
    );
    await _finalizeVerifiedIdentity(endpointId, pendingIdentity);
  }

  Future<void> _finalizeVerifiedIdentity(
    String endpointId,
    _PendingVerifiedIdentity pending,
  ) async {
    final traceId = _connectionTraces[endpointId];
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
    final packet = pending.packet;
    final payload = packet.payload;
    final deviceId = packet.senderDeviceId;
    final saved = await nearbyDevices.getDevice(deviceId);
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
    if (saved?.isBlocked == true) {
      await disconnect(endpointId, reason: 'peer_blocked');
      return;
    }
    final currentFingerprint = saved?.publicIdentityFingerprint;
    final pinUnchanged = currentFingerprint == pending.previousFingerprint;
    if (!pinUnchanged ||
        (pending.wasPinned &&
            (saved?.publicIdentityFingerprint != pending.fingerprint ||
                saved?.publicIdentityKey != pending.publicKey))) {
      peerErrors[endpointId] = 'pinned_identity_changed';
      await disconnect(endpointId, reason: 'pinned_identity_changed');
      return;
    }
    final status = _statusFrom(payload['status']! as String);
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
    if (!_isCurrentConnectionSession(endpointId, traceId)) return;
    if (!pending.pinnedMatches) {
      await nearbyDevices.setTrustedIdentity(
        deviceId: deviceId,
        publicIdentityKey: pending.publicKey,
        fingerprint: pending.fingerprint,
      );
      if (!_isCurrentConnectionSession(endpointId, traceId)) return;
      _recordIdentityStage(
        endpointId,
        'identity_fingerprint_pinned',
        fields: {'fingerprintPrefix': pending.fingerprint.substring(0, 12)},
      );
      _recordIdentityStage(endpointId, 'identity_enrollment_completed');
    }
    // เผย session mapping หลัง SQLite บันทึก trust pin แล้ว เพื่อให้ reconnect ทันทีใช้ pin ได้
    _updatePeerIdentity(
      endpointId,
      deviceId,
      displayName: payload['displayName']! as String,
      capabilities: _capabilitiesFrom(payload['capabilities']),
      fingerprint: pending.fingerprint,
    );
    _approvedConnectionEndpoints.add(endpointId);
    _provisionalConnectionEndpoints.remove(endpointId);
    _provisionalIncomingRequests.remove(endpointId);
    peerStates[endpointId] = NearbyConnectionState.connected;
    diagnostics?.record(
      'connection',
      'relio_identity_session_established',
      connectionTraceId: _connectionTraces[endpointId],
      operation: 'identityProof',
      stateFrom: 'verifyingIdentity',
      stateTo: NearbyConnectionState.connected.name,
      peerIdentifier: endpointId,
      fields: {
        'role': _activeTransportAttempts[endpointId]?['role'],
        'remoteRelioDeviceAlias': DiagnosticsLogService.peerAlias(deviceId),
        'sessionId': _connectionTraces[endpointId],
      },
    );
    _recordVerifiedEndpointBinding(endpointId, deviceId, 'identityProof');
    _reconnectFingerprintByEndpoint.remove(endpointId);
    final fingerprint = pending.fingerprint;
    _automaticConnectionAttempts.remove(fingerprint);
    _reconnectTimers.remove(fingerprint)?.cancel();
    _cancelSecondaryInitiatorFallback(fingerprint, resetElection: true);
    _nextReconnectAt.remove(fingerprint);
    _reconnectAttemptCounts.remove(fingerprint);
    _completedIdentityHandshakes.add(endpointId);
    unawaited(relayEngine?.forwardPending());
    final announcedAvatarRevision = packet.payload['avatarRevision'];
    if (announcedAvatarRevision is String && _supportsAvatarSync(endpointId)) {
      unawaited(
        _announceRemoteAvatar(
          endpointId,
          packet.senderDeviceId,
          announcedAvatarRevision,
        ),
      );
    }
    _identityHandshakeTimeouts.remove(endpointId)?.cancel();
    peerErrors.remove(endpointId);
    _recordIdentityStage(endpointId, 'identity_handshake_completed');
    _recordIdentityStage(endpointId, 'identity_hello_sent');
    await sendHello(peerId: endpointId);
    final latest = await sos?.readLatest(
      ownerDeviceId: await identity.getDeviceId(),
    );
    if (latest != null) await sendSos(latest, peerId: endpointId);
    unawaited(_locationCoordinator?.onPeerHandshakeCompleted(endpointId));
  }

  Future<void> _expireHandshake(String endpointId) async {
    if (peerStates[endpointId] != NearbyConnectionState.connected ||
        _completedIdentityHandshakes.contains(endpointId)) {
      return;
    }
    peerErrors[endpointId] = 'identity_handshake_timeout';
    await disconnect(endpointId, reason: 'identity_handshake_timeout');
    if (_closed || _connectionTraces.containsKey(endpointId)) return;
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
    _recordMediaStage(
      event.peerId,
      'FILE_PAYLOAD_RECEIVED',
      fields: {
        'payloadId': event.payloadId,
        'payloadType': 'FILE',
        'direction': 'RX',
      },
    );
    _track(_tryCompleteIncomingMedia(event.payloadId));
    _track(_tryCompleteIncomingAvatar(event.payloadId));
  }

  void _onTransfer(NearbyTransferEvent event) {
    final transferId = _payloadTransferIds[event.payloadId];
    final percent = event.totalBytes <= 0
        ? 0
        : (event.bytesTransferred * 100 ~/ event.totalBytes)
              .clamp(0, 100)
              .toInt();
    final milestone = percent >= 100 ? 100 : (percent ~/ 25) * 25;
    final lastMilestone = _mediaProgressMilestones[event.payloadId] ?? -1;
    if (milestone > lastMilestone ||
        event.status == NearbyTransferStatus.failure ||
        event.status == NearbyTransferStatus.cancelled ||
        event.status == NearbyTransferStatus.success) {
      _mediaProgressMilestones[event.payloadId] = milestone;
      _recordMediaStage(
        event.peerId,
        event.status == NearbyTransferStatus.success
            ? 'FILE_SUCCESS'
            : event.status == NearbyTransferStatus.failure ||
                  event.status == NearbyTransferStatus.cancelled
            ? 'FILE_FAILURE'
            : 'FILE_PROGRESS',
        reason: event.error,
        fields: {
          'traceId': transferId,
          'payloadId': event.payloadId,
          'payloadType': event.payloadType ?? 'FILE',
          'direction': event.direction ?? 'TX',
          'progressPercent': milestone,
          'bytesTransferred': event.bytesTransferred,
          'totalBytes': event.totalBytes,
          'durationMs': event.durationMs,
        },
      );
    }
    if (transferId == null || attachments == null) return;
    if (event.status == NearbyTransferStatus.success ||
        event.status == NearbyTransferStatus.failure ||
        event.status == NearbyTransferStatus.cancelled) {
      _payloadTransferIds.remove(event.payloadId);
      _mediaProgressMilestones.remove(event.payloadId);
    }
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

  final Map<String, Future<void>> _applicationPayloadTails = {};
  Future<void> _handlePayload(NearbyPayloadEvent event) {
    final owner = _owners.capture();
    final arrivalSession = _connectionTraces[event.peerId];
    final previous =
        _applicationPayloadTails[event.peerId] ?? Future<void>.value();
    final next = previous
        .then(
          (_) => _owners.run(() async {
            _owners.requireCurrent(owner);
            await _handleOwnedPayload(event, arrivalSession);
          }),
        )
        .catchError((Object _) {});
    _applicationPayloadTails[event.peerId] = next;
    return next;
  }

  Future<void> _handleOwnedPayload(
    NearbyPayloadEvent event,
    String? arrivalSession,
  ) async {
    RelioPacket? receivedPacket;
    try {
      final packet = RelioPacket.fromBytes(event.bytes);
      receivedPacket = packet;
      if (packet.type == RelioPacketType.mediaMetadata ||
          packet.type == RelioPacketType.mediaAck) {
        diagnostics?.record(
          'native_nearby',
          'native_payload_received',
          peerIdentifier: event.peerId,
          fields: {
            'elapsedMs': _diagnosticClock.elapsedMilliseconds,
            'payloadId': event.nativePayloadId,
            'payloadType': 'BYTES',
            'direction': 'RX',
            'bytesTransferred': event.bytes.length,
            'totalBytes': event.bytes.length,
            'connectionState': peerStates[event.peerId]?.name ?? 'unknown',
            'traceId': packet.payload['transferId'],
            'messageId': packet.payload['messageId'],
            'attachmentId': packet.payload['attachmentId'],
          },
        );
      }
      final mappedDeviceId = endpointToDeviceId[event.peerId];
      final isIdentityHandshake =
          packet.type == RelioPacketType.identityChallenge ||
          packet.type == RelioPacketType.identityProof;
      if (!isIdentityHandshake &&
          mappedDeviceId != null &&
          deviceToEndpointId[mappedDeviceId] != event.peerId) {
        protocolErrorCount++;
        _log(
          'packet rejected from retired endpoint alias=${DiagnosticsLogService.peerAlias(event.peerId)}',
        );
        return;
      }
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
      if (_isPrivate(packet) &&
          !await _validPrivateRecipient(event.peerId, packet)) {
        protocolErrorCount++;
        return;
      }
      // Packet อาจมีข้อความ/SOS/พิกัดส่วนตัว จึงเก็บ diagnostics แค่ type กับ ID
      // และไม่เปิดเผย payload ใน log ปกติ
      lastReceivedPacket = _diagnosticPacket(packet);
      _log(
        'รับ ${packet.type.name} จาก ${DiagnosticsLogService.peerAlias(event.peerId)}',
      );
      switch (packet.type) {
        case RelioPacketType.reachabilitySnapshot:
          if (_isCurrentConnectionSession(event.peerId, arrivalSession)) {
            await _receiveReachability(event.peerId, packet);
          }
          return;
        case RelioPacketType.identityChallenge:
          await _handleIdentityChallenge(event.peerId, packet);
        case RelioPacketType.identityProof:
          await _handleIdentityProof(event.peerId, packet);
        case RelioPacketType.hello:
          await _handleHello(event.peerId, packet);
        case RelioPacketType.textMessage:
          await _handleText(event.peerId, packet);
        case RelioPacketType.deviceStatus:
          if (packet.payload.containsKey('qaRelayCheckId')) {
            // ให้ response ผ่านคิว endpoint ได้ระหว่างรอ probe ของ hop ถัดไป
            _track(
              _handleQaRelayRouteCheck(
                event.peerId,
                packet,
              ).catchError((Object _) {}),
            );
            return;
          }
          await _handleDeviceStatus(packet);
        case RelioPacketType.ack:
          await _handleAck(event.peerId, packet);
        case RelioPacketType.sos:
          await _handleSos(event.peerId, packet);
        case RelioPacketType.rescueStatus:
          protocolErrorCount++;
          _log('ปฏิเสธ rescueStatus ที่ไม่ได้มากับ Relay envelope');
          return;
        case RelioPacketType.mediaMetadata:
          await _handleMediaMetadata(
            event.peerId,
            packet,
            event.nativePayloadId,
          );
        case RelioPacketType.mediaAck:
          await _handleMediaAck(packet, event.nativePayloadId);
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
      if (receivedPacket?.type == RelioPacketType.hello ||
          receivedPacket?.type == RelioPacketType.sos) {
        final isSos = receivedPacket?.type == RelioPacketType.sos;
        diagnostics?.record(
          isSos ? 'sos' : 'nearby',
          isSos ? 'sos_packet_processing_failed' : 'hello_processing_failed',
          severity: 'error',
          peerIdentifier: event.peerId,
          reason: error.runtimeType.toString(),
          fields: {'packetType': receivedPacket?.type.name},
        );
      }
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
    String? nativePayloadId,
  ) async {
    final payloadId = packet.payload['payloadId'] as String?;
    if (payloadId == null || payloadId.isEmpty) {
      _fail('mediaMetadata ไม่มี payloadId');
      return;
    }
    _mediaMetadataOwners[payloadId] = _owners.capture();
    _mediaMetadataByPayload[payloadId] = packet;
    _recordMediaStage(
      endpointId,
      'METADATA_RECEIVED',
      fields: {
        'traceId': packet.payload['transferId'],
        'messageId': packet.payload['messageId'],
        'attachmentId': packet.payload['attachmentId'],
        'payloadId': nativePayloadId,
        'filePayloadId': payloadId,
        'payloadType': 'BYTES',
        'direction': 'RX',
      },
    );
    // คงชื่อ event เดิมไว้ให้ตัวตรวจและชุดทดสอบที่อาศัย diagnostics รุ่นก่อน
    _recordMediaStage(
      endpointId,
      'media_metadata_received',
      fields: {
        'traceId': packet.payload['transferId'],
        'messageId': packet.payload['messageId'],
        'attachmentId': packet.payload['attachmentId'],
        'payloadId': nativePayloadId,
        'filePayloadId': payloadId,
        'payloadType': 'BYTES',
        'direction': 'RX',
      },
    );
    await _tryCompleteIncomingMedia(payloadId);
  }

  Future<void> _tryCompleteIncomingMedia(String payloadId) async {
    final owner = _mediaMetadataOwners[payloadId];
    if (owner != null && !_owners.isCurrent(owner)) {
      _mediaMetadataByPayload.remove(payloadId);
      _mediaMetadataOwners.remove(payloadId);
      _mediaFilesByPayload.remove(payloadId);
      return;
    }
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
    _recordMediaStage(
      file.peerId,
      'METADATA_FILE_MATCHED',
      fields: {
        'traceId': packet.payload['transferId'],
        'messageId': messageId,
        'attachmentId': packet.payload['attachmentId'],
        'payloadId': payloadId,
        'payloadType': 'FILE',
        'direction': 'RX',
      },
    );
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
  ) => _owners
      .run(() => _persistIncomingMediaOwned(payloadId, packet, file))
      .catchError((Object _) {});

  Future<void> _persistIncomingMediaOwned(
    String payloadId,
    RelioPacket packet,
    NearbyFilePayloadEvent file,
  ) async {
    if (!await _validPrivateRecipient(file.peerId, packet)) return;
    final payload = packet.payload;
    var receiveStage = 'source_identity';
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
      final fileCheck = File(file.filePath);
      final fileExistsClock = Stopwatch()..start();
      final sourceExists = await fileCheck.exists();
      _recordMediaStage(
        file.peerId,
        'FILE_EXISTS_CHECK',
        fields: {
          'traceId': payload['transferId'],
          'messageId': payload['messageId'],
          'attachmentId': payload['attachmentId'],
          'payloadId': payloadId,
          'exists': sourceExists,
          'durationMs': fileExistsClock.elapsedMilliseconds,
        },
      );
      receiveStage = 'file_validation_and_storage';
      final persistClock = Stopwatch()..start();
      _recordMediaStage(
        file.peerId,
        'INTEGRITY_CHECK_START',
        fields: {
          'traceId': payload['transferId'],
          'messageId': payload['messageId'],
          'attachmentId': payload['attachmentId'],
          'payloadId': payloadId,
          'direction': 'RX',
        },
      );
      _recordMediaStage(
        file.peerId,
        'FILE_PERSIST_START',
        fields: {
          'traceId': payload['transferId'],
          'messageId': payload['messageId'],
          'attachmentId': payload['attachmentId'],
          'payloadId': payloadId,
          'direction': 'RX',
        },
      );
      if (diagnostics?.enabled == true) {
        final sourceFile = File(file.filePath);
        final exists = await sourceFile.exists();
        _recordMediaStage(
          file.peerId,
          'media_receive_validation_started',
          fields: {
            'payloadId': payloadId,
            'transferId': payload['transferId'],
            'mediaType': payload['mediaType'],
            'mimeType': payload['mimeType'],
            'expectedBytes': payload['byteSize'],
            'sourceExists': exists,
            if (exists) 'receivedBytes': await sourceFile.length(),
          },
        );
      }
      final storedPath = await mediaStorage!.storeIncomingFile(
        sourcePath: file.filePath,
        fileName: payload['fileName']! as String,
        expectedMimeType: payload['mimeType']! as String,
        expectedBytes: (payload['byteSize']! as num).toInt(),
        expectedSha256: payload['sha256'] as String?,
      );
      _recordMediaStage(
        file.peerId,
        'FILE_PERSIST_RESULT',
        fields: {
          'traceId': payload['transferId'],
          'messageId': payload['messageId'],
          'attachmentId': payload['attachmentId'],
          'payloadId': payloadId,
          'result': 'success',
          'validationAndStorageDurationMs': persistClock.elapsedMilliseconds,
          'direction': 'RX',
        },
      );
      _recordMediaStage(
        file.peerId,
        'INTEGRITY_CHECK_RESULT',
        fields: {
          'traceId': payload['transferId'],
          'messageId': payload['messageId'],
          'attachmentId': payload['attachmentId'],
          'payloadId': payloadId,
          'result': 'success',
          'durationMs': persistClock.elapsedMilliseconds,
          'direction': 'RX',
        },
      );
      receiveStage = 'conversation_resolution';
      final conversationId = await _conversationIdForDevice(
        packet.senderDeviceId,
        packet.senderDeviceId,
      );
      final conversation = await conversations.ensureConversation(
        id: conversationId,
        participantId: packet.senderDeviceId,
        displayName: _peerName(file.peerId, packet.senderUserId),
        participantStatus: DeviceStatus.normal,
      );
      receiveStage = 'message_persistence';
      final message = await messages.createIncomingMedia(
        conversationId: conversation.id,
        senderId: packet.senderUserId,
        senderDeviceId: packet.senderDeviceId,
        messageId: payload['messageId']! as String,
        type: _mediaMessageType(payload['mediaType']! as String),
        fileName: payload['fileName']! as String,
        localPath: storedPath,
      );
      receiveStage = 'attachment_persistence';
      final attachmentId = payload['attachmentId']! as String;
      if (await attachments!.getById(attachmentId) == null) {
        await attachments!.createPending(
          id: attachmentId,
          conversationId: conversation.id,
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
      await _markIncomingReadIfVisible(conversation.id, packet.senderDeviceId);
      if (existingMessage == null) {
        await _notifyIncoming(
          id: payload['messageId']! as String,
          title: _peerName(file.peerId, packet.senderUserId),
          preview: payload['mediaType'] == 'video' ? 'ส่งวิดีโอ' : 'ส่งรูปภาพ',
          route: '/chat/${conversation.id}',
        );
      }
      _recordMediaStage(
        file.peerId,
        'ATTACHMENT_LINKED',
        fields: {
          'traceId': payload['transferId'],
          'messageId': payload['messageId'],
          'attachmentId': payload['attachmentId'],
          'payloadId': payloadId,
          'direction': 'RX',
          'mediaType': payload['mediaType'],
          'sizeBytes': payload['byteSize'],
          'durationMs': persistClock.elapsedMilliseconds,
        },
      );
      _recordMediaStage(
        file.peerId,
        'MESSAGE_READY_FOR_UI',
        fields: {
          'traceId': payload['transferId'],
          'messageId': payload['messageId'],
          'attachmentId': payload['attachmentId'],
          'payloadId': payloadId,
          'direction': 'RX',
        },
      );
      // ACK สำเร็จได้เมื่อไฟล์ตรวจผ่าน เก็บแล้ว และผูก attachment กับข้อความแล้วเท่านั้น
      await _sendMediaAck(file.peerId, packet, 'completed');
    } on Object catch (error) {
      _recordMediaStage(
        file.peerId,
        'media_receive_failed',
        severity: 'error',
        reason: error is MediaStorageException
            ? error.message
            : error.runtimeType.toString(),
        fields: {'checkpoint': receiveStage, 'payloadId': payloadId},
      );
      _fail('รับไฟล์ไม่สำเร็จ: $error');
      await _sendMediaAck(
        file.peerId,
        packet,
        'failed',
        errorCode: 'invalid_file',
      );
    } finally {
      _mediaMetadataByPayload.remove(payloadId);
      _mediaMetadataOwners.remove(payloadId);
      _mediaFilesByPayload.remove(payloadId);
    }
  }

  Future<void> _handleMediaAck(
    RelioPacket packet,
    String? nativePayloadId,
  ) async {
    final transferId = packet.payload['transferId']! as String;
    final attachment = await attachments?.getByTransferId(transferId);
    if (attachment == null) return;
    final status = packet.payload['status']! as String;
    final ackClock = _mediaAckClocks.remove(transferId);
    _recordMediaStage(
      null,
      'MEDIA_ACK_RECEIVED',
      fields: {
        'traceId': transferId,
        'messageId': attachment.messageId,
        'attachmentId': attachment.id,
        'payloadId': nativePayloadId,
        'payloadType': 'BYTES',
        'direction': 'RX',
        'status': status,
        if (ackClock != null) 'ackWaitMs': ackClock.elapsedMilliseconds,
      },
    );
    if (status == 'completed') {
      await attachments?.markCompleted(attachment.id);
      await messages.updateDeliveryStatus(
        attachment.messageId,
        DeliveryStatus.delivered,
      );
      acknowledgementCount += 1;
      final pipelineClock = _mediaPipelineClocks.remove(transferId);
      _recordMediaStage(
        null,
        'MESSAGE_DELIVERED',
        fields: {
          'traceId': transferId,
          'messageId': attachment.messageId,
          'attachmentId': attachment.id,
          if (pipelineClock != null)
            'totalPipelineMs': pipelineClock.elapsedMilliseconds,
        },
      );
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
    final conversation = await conversations.ensureConversation(
      id: conversationId,
      participantId: packet.senderDeviceId,
      displayName: _peerName(endpointId, packet.senderUserId),
      participantStatus: DeviceStatus.normal,
    );
    await messages.createIncomingLocation(
      conversationId: conversation.id,
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
    await _markIncomingReadIfVisible(conversation.id, packet.senderDeviceId);
    await _notifyIncoming(
      id: packet.payload['messageId']! as String,
      title: 'ได้รับตำแหน่งใหม่',
      route: '/chat/${conversation.id}',
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
    final nativePayloadId = await _sendApplicationBytes(
      ack,
      peerId: endpointId,
      replyTo: source,
    );
    _recordMediaStage(
      endpointId,
      'MEDIA_ACK_SENT',
      fields: {
        'traceId': payload['transferId'],
        'messageId': payload['messageId'],
        'attachmentId': payload['attachmentId'],
        'payloadId': nativePayloadId,
        'payloadType': 'BYTES',
        'status': status,
        'direction': 'TX',
      },
    );
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
        await setting.getBool('notification_preview', defaultValue: true);
    _owners.requireCurrent(_owners.capture());
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
      soundEnabled: await setting.getBool(
        'notification_sound',
        defaultValue: true,
      ),
      vibrationEnabled: await setting.getBool(
        'notification_vibration',
        defaultValue: true,
      ),
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
      fields: {'elapsedMs': _diagnosticClock.elapsedMilliseconds, ...fields},
    );
  }

  Future<void> _handleHello(String endpointId, RelioPacket packet) async {
    final traceId = _connectionTraces[endpointId];
    _log(
      'hello receive: endpoint ${DiagnosticsLogService.peerAlias(endpointId)}',
    );
    final savedPeer = await nearbyDevices.getDevice(packet.senderDeviceId);
    if (traceId != null && !_isCurrentConnectionSession(endpointId, traceId)) {
      return;
    }
    diagnostics?.record(
      'nearby',
      'hello_step_completed',
      peerIdentifier: endpointId,
      fields: {'checkpoint': 'trusted_peer_lookup'},
    );
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
    if (RelioPacket.validPrincipal(packet.senderPrincipal)) {
      final previousPrincipal = _remotePrincipals[endpointId];
      final epoch = packet.payload['principalGeneration'] as int? ?? 0;
      final revision = packet.payload['profileRevision'] as int? ?? 0;
      final previousEpoch = _remotePrincipalEpochs[endpointId];
      if (previousEpoch != null &&
          (epoch < previousEpoch ||
              (epoch == previousEpoch &&
                  _remotePrincipals[endpointId] != packet.senderPrincipal) ||
              (epoch == previousEpoch &&
                  revision < (_remoteProfileRevisions[endpointId] ?? 0)))) {
        return;
      }
      _remotePrincipalEpochs[endpointId] = epoch;
      _remoteProfileRevisions[endpointId] = revision;
      _remotePrincipals[endpointId] = packet.senderPrincipal!;
      if (previousPrincipal != null &&
          previousPrincipal != packet.senderPrincipal) {
        _remoteAvatarPaths.remove(packet.senderDeviceId);
        notifyListeners();
      }
      if (conversations is DriftConversationRepository) {
        await (conversations as DriftConversationRepository)
            .rememberRemotePrincipal(
              packet.senderDeviceId,
              packet.senderPrincipal!,
              packet.payload['displayName']! as String,
              packet.payload['profileRevision'] as int? ?? 0,
            );
      }
    }
    final reportedStatus = _statusFrom(packet.payload['status'] as String);
    final helloStatusAt = DateTime.tryParse(
      packet.payload['updatedAt'] as String? ?? '',
    );
    if (helloStatusAt != null) {
      _lastPeerStatusUpdatedAt[packet.senderDeviceId] = helloStatusAt;
    }
    _rememberPeerRescueState(packet, reportedStatus);
    final status = await _statusWithSosPrecedence(
      packet.senderDeviceId,
      reportedStatus,
    );
    if (traceId != null && !_isCurrentConnectionSession(endpointId, traceId)) {
      return;
    }
    peerStatuses[packet.senderDeviceId] = status;
    final displayName = packet.payload['displayName']! as String;
    final metadata = _peerMetadataRepositoryFields(packet);
    await nearbyDevices.upsert(
      deviceId: packet.senderDeviceId,
      displayName: displayName,
      status: status,
      batteryLevel: metadata['batteryLevel'] as int?,
      isCharging: metadata['isCharging'] as bool?,
      batteryUpdatedAt: metadata['batteryUpdatedAt'] as DateTime?,
      peerLatitude: metadata['peerLatitude'] as double?,
      peerLongitude: metadata['peerLongitude'] as double?,
      peerLocationAccuracy: metadata['peerLocationAccuracy'] as double?,
      peerLocationCapturedAt: metadata['peerLocationCapturedAt'] as DateTime?,
      peerDeviceModel: metadata['peerDeviceModel'] as String?,
    );
    diagnostics?.record(
      'nearby',
      'hello_step_completed',
      peerIdentifier: endpointId,
      fields: {'checkpoint': 'peer_repository_write'},
    );
    if (identityCrypto is MockPeerIdentityCrypto) {
      // Test transport only: production trust is pinned only after proof.
      await nearbyDevices.setTrusted(packet.senderDeviceId, true);
    }
    final conversationId = await _conversationIdForDevice(
      packet.senderDeviceId,
      packet.senderDeviceId,
    );
    final conversation = await conversations.ensureConversation(
      id: conversationId,
      participantId: packet.senderDeviceId,
      displayName: displayName,
      participantStatus: status,
    );
    await conversations.updateParticipantStatus(packet.senderDeviceId, status);
    if (traceId != null && !_isCurrentConnectionSession(endpointId, traceId)) {
      return;
    }
    diagnostics?.record(
      'nearby',
      'hello_step_completed',
      peerIdentifier: endpointId,
      fields: {'checkpoint': 'conversation_repository_update'},
    );
    _updatePeerIdentity(
      endpointId,
      packet.senderDeviceId,
      displayName: displayName,
      capabilities: _capabilitiesFrom(packet.payload['capabilities']),
    );
    _completedIdentityHandshakes.add(endpointId);
    _recordVerifiedEndpointBinding(endpointId, packet.senderDeviceId, 'hello');
    unawaited(relayEngine?.forwardPending());
    diagnostics?.record(
      'nearby',
      'hello_step_completed',
      peerIdentifier: endpointId,
      fields: {'checkpoint': 'live_identity_update'},
    );
    _identityHandshakeTimeouts.remove(endpointId)?.cancel();
    peerErrors.remove(endpointId);
    _recordIdentityStage(endpointId, 'identity_hello_received');
    if (identityCrypto is MockPeerIdentityCrypto) {
      _recordIdentityStage(endpointId, 'identity_handshake_completed');
    }
    _track(_flushPendingMessages(conversation.id));
    unawaited(_locationCoordinator?.onPeerHandshakeCompleted(endpointId));
    _track(_announceLocalAvatar(endpointId));
    _log(
      'peer established: endpoint ${DiagnosticsLogService.peerAlias(endpointId)} '
      '↔ ${DiagnosticsLogService.peerAlias(packet.senderDeviceId)}',
    );
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
    if (message.type == MessageType.location) {
      await sendLocationMessage(message);
      return;
    }
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
      final conversation = await conversations.ensureConversation(
        id: conversationId,
        participantId: packet.senderDeviceId,
        displayName: _peerName(endpointId, packet.senderUserId),
        participantStatus: DeviceStatus.normal,
      );
      await messages.createIncomingText(
        conversationId: conversation.id,
        senderId: packet.senderUserId,
        senderDeviceId: packet.senderDeviceId,
        messageId: messageId,
        text: packet.payload['text']! as String,
        createdAt: DateTime.parse(packet.payload['timestamp']! as String),
      );
      await _markIncomingReadIfVisible(conversation.id, packet.senderDeviceId);
      await _notifyIncoming(
        id: messageId,
        title: _peerName(endpointId, packet.senderUserId),
        preview: packet.payload['text']! as String,
        route: '/chat/${conversation.id}',
      );
      await _sendAck(endpointId, packet);
    } finally {
      _incomingTextMessagesInProgress.remove(messageId);
    }
  }

  Future<void> _handleDeviceStatus(RelioPacket packet) async {
    final reportedStatus = _statusFrom(packet.payload['status']! as String);
    final updatedAt = DateTime.tryParse(packet.payload['updatedAt']! as String);
    final previousUpdatedAt = _lastPeerStatusUpdatedAt[packet.senderDeviceId];
    if (updatedAt != null &&
        previousUpdatedAt != null &&
        updatedAt.isBefore(previousUpdatedAt)) {
      diagnostics?.record(
        'nearby_status',
        'device_status_stale_ignored',
        peerIdentifier: deviceToEndpointId[packet.senderDeviceId],
        fields: {'reportedStatus': reportedStatus.name},
      );
      return;
    }
    if (updatedAt != null) {
      _lastPeerStatusUpdatedAt[packet.senderDeviceId] = updatedAt;
    }
    _rememberPeerRescueState(packet, reportedStatus);
    final status = await _statusWithSosPrecedence(
      packet.senderDeviceId,
      reportedStatus,
    );
    peerStatuses[packet.senderDeviceId] = status;
    final displayName = packet.payload['displayName']! as String;
    await _persistPeerMetadata(packet, status: status);
    await conversations.updateParticipantStatus(packet.senderDeviceId, status);
    _updatePeerIdentity(
      deviceToEndpointId[packet.senderDeviceId],
      packet.senderDeviceId,
      displayName: displayName,
    );
    await _handleAvatarStatus(packet);
  }

  bool _supportsAvatarSync(String endpointId) =>
      RelioBuildInfo.isTest &&
      discoveredPeers
          .where((peer) => peer.endpointId == endpointId)
          .any((peer) => peer.capabilities.contains('avatar-v1'));

  String? avatarPathFor(String deviceId) => _remoteAvatarPaths[deviceId];

  Future<void> _announceLocalAvatar(String endpointId) async {
    if (!RelioBuildInfo.isTest ||
        profileAvatar == null ||
        !_completedIdentityHandshakes.contains(endpointId) ||
        !_supportsAvatarSync(endpointId)) {
      return;
    }
    final profile = await identity.profiles.current();
    final artifact = await profileAvatar!.shareArtifact();
    final revision =
        artifact?.revision ??
        (profile.avatarPath == null && profile.revision > 0
            ? 'removed-${profile.revision}'
            : null);
    if (revision == null) return;
    await _sendPacket(
      RelioPacket.deviceStatus(
        senderDeviceId: await identity.getDeviceId(),
        senderUserId: await _senderUserId(),
        displayName: await identity.getDisplayName(),
        status: await currentStatus(),
        avatarRevision: revision,
      ),
      description: 'nearby avatar revision',
      peerId: endpointId,
    );
  }

  Future<void> _restoreCachedPeerAvatars() async {
    if (!RelioBuildInfo.isTest || profileAvatar == null) return;
    final owner = _owners.capture();
    try {
      final peers = await nearbyDevices.listDevices();
      for (final peer in peers) {
        final remotePrincipal = conversations is DriftConversationRepository
            ? await (conversations as DriftConversationRepository)
                  .activeRemotePrincipal(peer.deviceId)
            : null;
        if (!RelioPacket.validPrincipal(remotePrincipal)) continue;
        final path = await profileAvatar!.remoteAvatarPath(
          deviceId: peer.deviceId,
          remotePrincipal: remotePrincipal!,
        );
        if (path != null && _owners.isCurrent(owner)) {
          _remoteAvatarPaths[peer.deviceId] = path;
        }
      }
      if (_owners.isCurrent(owner)) notifyListeners();
    } on Object {
      // A missing or stale cache must leave the deterministic default avatar.
    }
  }

  Future<void> _announceRemoteAvatar(
    String endpointId,
    String deviceId,
    String revision,
  ) async {
    if (profileAvatar == null ||
        !_completedIdentityHandshakes.contains(endpointId) ||
        endpointToDeviceId[endpointId] != deviceId ||
        !RelioPacket.validPrincipal(_remotePrincipals[endpointId])) {
      return;
    }
    final remotePrincipal = _remotePrincipals[endpointId]!;
    if (revision.startsWith('removed-')) {
      await profileAvatar!.removeRemoteAvatar(
        deviceId: deviceId,
        remotePrincipal: remotePrincipal,
      );
      _remoteAvatarPaths.remove(deviceId);
      notifyListeners();
      return;
    }
    final cached = await profileAvatar!.cachedRemoteRevision(
      deviceId: deviceId,
      remotePrincipal: remotePrincipal,
    );
    if (cached == revision) {
      final path = await profileAvatar!.remoteAvatarPath(
        deviceId: deviceId,
        remotePrincipal: remotePrincipal,
      );
      if (path != _remoteAvatarPaths[deviceId]) {
        _remoteAvatarPaths[deviceId] = path!;
        notifyListeners();
      }
      return;
    }
    if (!_supportsAvatarSync(endpointId)) return;
    final requestKey = '$deviceId:$revision';
    final lastRequest = _avatarRequestAt[requestKey];
    if (lastRequest != null &&
        DateTime.now().difference(lastRequest) < const Duration(seconds: 60)) {
      return;
    }
    _avatarRequestAt[requestKey] = DateTime.now();
    try {
      await _sendPacket(
        RelioPacket.deviceStatus(
          senderDeviceId: await identity.getDeviceId(),
          senderUserId: await _senderUserId(),
          displayName: await identity.getDisplayName(),
          status: await currentStatus(),
          avatarRevision: revision,
          avatarAction: 'request',
        ),
        description: 'nearby avatar request',
        peerId: endpointId,
      );
    } on Object {
      _avatarRequestAt.remove(requestKey);
    }
  }

  Future<void> _handleAvatarStatus(RelioPacket packet) async {
    if (!RelioBuildInfo.isTest) return;
    final endpointId = deviceToEndpointId[packet.senderDeviceId];
    if (endpointId == null ||
        !_completedIdentityHandshakes.contains(endpointId) ||
        !RelioPacket.validPrincipal(packet.senderPrincipal) ||
        _remotePrincipals[endpointId] != packet.senderPrincipal) {
      return;
    }
    final action = packet.payload['avatarAction'];
    if (action == 'request') {
      final requestedRevision = packet.payload['avatarRevision'];
      if (requestedRevision is String && _supportsAvatarSync(endpointId)) {
        _track(
          _sendAvatarFile(endpointId, packet.senderDeviceId, requestedRevision),
        );
      }
      return;
    }
    if (action == 'transfer') {
      final payloadId = packet.payload['avatarPayloadId'];
      if (payloadId is! String ||
          (_avatarMetadataByPayload.length >= 16 &&
              !_avatarMetadataByPayload.containsKey(payloadId))) {
        return;
      }
      _avatarMetadataByPayload[payloadId] = {
        'senderDeviceId': packet.senderDeviceId,
        'remotePrincipal': packet.senderPrincipal,
        'revision': packet.payload['avatarRevision'],
        'byteSize': packet.payload['avatarByteSize'],
      };
      await _tryCompleteIncomingAvatar(payloadId);
      return;
    }
    final revision = packet.payload['avatarRevision'];
    if (revision is String) {
      await _announceRemoteAvatar(endpointId, packet.senderDeviceId, revision);
    }
  }

  Future<void> _sendAvatarFile(
    String endpointId,
    String targetDeviceId,
    String requestedRevision,
  ) async {
    if (profileAvatar == null ||
        !_completedIdentityHandshakes.contains(endpointId) ||
        endpointToDeviceId[endpointId] != targetDeviceId ||
        !_avatarTransfersInProgress.add(targetDeviceId)) {
      return;
    }
    try {
      final waitUntil = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(waitUntil)) {
        if (!_completedIdentityHandshakes.contains(endpointId) ||
            endpointToDeviceId[endpointId] != targetDeviceId) {
          return;
        }
        final urgent = await currentStatus() != DeviceStatus.normal;
        if (!urgent && _mediaAckClocks.isEmpty) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (_mediaAckClocks.isNotEmpty ||
          await currentStatus() != DeviceStatus.normal) {
        return;
      }
      final artifact = await profileAvatar!.shareArtifact();
      if (artifact == null || artifact.revision != requestedRevision) return;
      final byteSize = await File(artifact.path).length();
      if (byteSize < 1 ||
          byteSize > ProfileAvatarRepository.maxSharedAvatarBytes) {
        return;
      }
      final transferId = const Uuid().v4();
      final payloadId = await transport.sendFile(
        artifact.path,
        peerId: endpointId,
      );
      await _sendPacket(
        RelioPacket.deviceStatus(
          senderDeviceId: await identity.getDeviceId(),
          senderUserId: await _senderUserId(),
          displayName: await identity.getDisplayName(),
          status: await currentStatus(),
          avatarRevision: artifact.revision,
          avatarAction: 'transfer',
          avatarTransferId: transferId,
          avatarPayloadId: payloadId,
          avatarByteSize: byteSize,
          avatarSha256: artifact.revision,
        ),
        description: 'nearby avatar metadata',
        peerId: endpointId,
      );
    } finally {
      _avatarTransfersInProgress.remove(targetDeviceId);
    }
  }

  Future<void> _tryCompleteIncomingAvatar(String payloadId) async {
    final metadata = _avatarMetadataByPayload[payloadId];
    final file = _mediaFilesByPayload[payloadId];
    if (metadata == null || file == null || profileAvatar == null) return;
    final deviceId = metadata['senderDeviceId'];
    final revision = metadata['revision'];
    final expectedBytes = metadata['byteSize'];
    final remotePrincipal = metadata['remotePrincipal'];
    if (deviceId is! String ||
        revision is! String ||
        expectedBytes is! int ||
        remotePrincipal is! String ||
        !RelioPacket.validPrincipal(remotePrincipal)) {
      _avatarMetadataByPayload.remove(payloadId);
      return;
    }
    if (!_completedIdentityHandshakes.contains(file.peerId) ||
        endpointToDeviceId[file.peerId] != deviceId ||
        _remotePrincipals[file.peerId] != remotePrincipal) {
      return;
    }
    try {
      final source = File(file.filePath);
      if (!await source.exists() || await source.length() != expectedBytes) {
        return;
      }
      final path = await profileAvatar!.storeRemoteAvatar(
        deviceId: deviceId,
        remotePrincipal: remotePrincipal,
        revision: revision,
        sourcePath: file.filePath,
      );
      if (path != null) {
        _remoteAvatarPaths[deviceId] = path;
        _avatarRequestAt.removeWhere(
          (entry, _) => entry.startsWith('$deviceId:'),
        );
        notifyListeners();
      }
    } on Object {
      // Invalid avatar content falls back to RELIO's deterministic icon.
    } finally {
      _avatarMetadataByPayload.remove(payloadId);
      _mediaFilesByPayload.remove(payloadId);
    }
  }

  // QA route probe เดินต่อทีละ peer ที่ยืนยันตัวตนแล้ว โดยแนบ path ป้องกันวน
  Future<void> _handleQaRelayRouteCheck(
    String endpointId,
    RelioPacket packet,
  ) async {
    if (!RelioBuildInfo.isTest ||
        !_completedIdentityHandshakes.contains(endpointId)) {
      return;
    }
    final checkId = packet.payload['qaRelayCheckId'];
    final destinationHash = packet.payload['qaRelayDestinationHash'];
    if (checkId is! String || destinationHash is! String) return;
    final connected = packet.payload['qaRelayConnected'];
    if (connected is bool) {
      final pending = _qaRelayRouteChecks[checkId];
      if (pending != null &&
          !pending.result.isCompleted &&
          pending.endpointId == endpointId &&
          _connectionTraces[endpointId] == pending.session &&
          pending.destinationHash == destinationHash) {
        pending.result.complete((
          connected: connected,
          principal: packet.payload['qaRelayPrincipal'] as String?,
        ));
      }
      return;
    }
    final rawPath = packet.payload['qaRelayPath'];
    final remainingHops = packet.payload['qaRelayMaxHops'];
    if (rawPath is! List || remainingHops is! int) return;
    final path = rawPath.cast<String>();
    if (path.last != packet.senderDeviceId) return;
    final session = _connectionTraces[endpointId];
    final localDeviceId = await identity.getDeviceId();
    final resolvePrincipal = packet.payload['qaRelayResolvePrincipal'] == true;
    final strictQa = relayEngine?.qaPlaintextTextAllowed != null;
    final canRelay =
        !strictQa ||
        (qaPlaintextTextEnabled &&
            await reachabilityRelayAllowed?.call() == true);
    var isConnected = false;
    String? principal;
    if (canRelay && !path.contains(localDeviceId)) {
      final matching = authenticatedConnectedPeers
          .where(
            (peer) =>
                peer.endpointId != endpointId &&
                peer.deviceId != null &&
                sha256.convert(utf8.encode(peer.deviceId!)).toString() ==
                    destinationHash &&
                peer.capabilities.contains('relay-v1') &&
                (!strictQa ||
                    peer.capabilities.contains(_qaTextRelayCapability)),
          )
          .toList();
      if (matching.length == 1) {
        final mapped = _remotePrincipals[matching.single.endpointId];
        if (resolvePrincipal && RelioPacket.validPrincipal(mapped)) {
          principal = mapped;
        }
        isConnected = !resolvePrincipal || principal != null;
      }

      if (!isConnected && remainingHops > 1) {
        final candidates =
            authenticatedConnectedPeers
                .where(
                  (peer) =>
                      peer.endpointId != endpointId &&
                      peer.deviceId != null &&
                      peer.deviceId != localDeviceId &&
                      !path.contains(peer.deviceId) &&
                      peer.capabilities.contains('relay-v1') &&
                      (!strictQa ||
                          peer.capabilities.contains(_qaTextRelayCapability)),
                )
                .toList(growable: false)
              ..sort((a, b) => a.deviceId!.compareTo(b.deviceId!));
        final seenDevices = <String>{};
        for (final candidate in candidates) {
          final candidateDeviceId = candidate.deviceId!;
          if (!seenDevices.add(candidateDeviceId)) continue;
          final reply = await _probeQaRelayEndpoint(
            endpointId: candidate.endpointId,
            destinationHash: destinationHash,
            path: [...path, localDeviceId],
            maxHops: remainingHops - 1,
            resolvePrincipal: resolvePrincipal,
          );
          isConnected = reply.connected;
          principal = reply.principal;
          if (isConnected) break;
        }
      }
    }
    diagnostics?.record(
      'relay',
      'route_probe_completed',
      peerIdentifier: endpointId,
      fields: {
        'reachable': isConnected,
        'remainingHops': remainingHops,
        'routeDepth': path.length,
      },
    );
    try {
      if (!_isCurrentConnectionSession(endpointId, session)) return;
      await _sendApplicationBytes(
        RelioPacket.deviceStatus(
          senderDeviceId: await identity.getDeviceId(),
          senderUserId: await _senderUserId(),
          displayName: await identity.getDisplayName(),
          status: await currentStatus(),
          qaRelayCheckId: checkId,
          qaRelayDestinationHash: destinationHash,
          qaRelayConnected: isConnected,
          qaRelayPrincipal: principal,
        ),
        peerId: endpointId,
      );
    } on Object {
      // QA route check fails closed at the requesting device.
    }
  }

  Future<void> _handleAck(String endpointId, RelioPacket packet) async {
    final acknowledgedPacketId = packet.payload['packetId']! as String;
    final messageId =
        packet.payload['messageId'] as String? ??
        _packetMessageIds[acknowledgedPacketId];
    if (messageId != null) {
      final message = await messages.getMessage(messageId);
      if (message == null || message.status == DeliveryStatus.delivered) return;
      await messages.updateDeliveryStatus(messageId, DeliveryStatus.delivered);
      if (RelioBuildInfo.isTest && message.type == MessageType.text) {
        diagnostics?.record(
          'relay',
          'direct_ack_received',
          fields: {
            'payloadAlias': DiagnosticsLogService.peerAlias(messageId),
            'destinationAlias': DiagnosticsLogService.peerAlias(
              packet.senderDeviceId,
            ),
          },
        );
      }
      acknowledgementCount += 1;
      _log('ACK message delivered');
      _log('รับ ACK ของข้อความ $messageId');
      return;
    }

    final expectedPeers = _pendingSosAcks[acknowledgedPacketId];
    final senderDeviceId = endpointToDeviceId[endpointId];
    if (expectedPeers == null ||
        senderDeviceId == null ||
        !expectedPeers.remove(senderDeviceId)) {
      return;
    }
    if (expectedPeers.isEmpty) {
      _pendingSosAcks.remove(acknowledgedPacketId);
    }
    acknowledgementCount += 1;
    final sosEventId = _sosEventIdsByPacketId[acknowledgedPacketId];
    final transportName = endpointId.startsWith('classic:')
        ? 'RFCOMM'
        : 'Nearby';
    _recordSosSend(
      'outbound_ack_received',
      eventId: sosEventId ?? acknowledgedPacketId,
      peer: NearbyPeer(
        id: endpointId,
        name: _peerName(endpointId, senderDeviceId),
        connected: peerStates[endpointId] == NearbyConnectionState.connected,
        deviceId: senderDeviceId,
      ),
      transportName: transportName,
    );
    _log(
      'SOS ACK received event=${sosEventId ?? 'unknown'} '
      'packet=$acknowledgedPacketId '
      'peer=$senderDeviceId transport=$transportName',
    );
    if (expectedPeers.isEmpty) {
      _sosEventIdsByPacketId.remove(acknowledgedPacketId);
    }
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
    await _sendApplicationBytes(packet, peerId: endpointId);
    lastSentPacket = _diagnosticPacket(packet);
    _log('ส่ง readReceipt แล้ว');
  }

  Future<void> _handleReadReceipt(RelioPacket packet) async {
    await messages.markMessageRead(packet.payload['messageId']! as String);
    _log('รับ readReceipt แล้ว');
  }

  Future<void> _handleSos(
    String endpointId,
    RelioPacket packet, {
    bool viaRelay = false,
  }) async {
    final deviceId = packet.senderDeviceId;
    final previous = _sosReceiveQueues[deviceId];
    final completed = Completer<void>();
    _sosReceiveQueues[deviceId] = completed.future;
    try {
      if (previous != null) await previous.catchError((Object _) {});
      await _applySosPacket(endpointId, packet, viaRelay: viaRelay);
    } finally {
      completed.complete();
      if (identical(_sosReceiveQueues[deviceId], completed.future)) {
        _sosReceiveQueues.remove(deviceId);
      }
    }
  }

  Future<void> _applySosPacket(
    String endpointId,
    RelioPacket packet, {
    bool viaRelay = false,
  }) async {
    if (sos == null) {
      _fail('รับ SOS ไม่ได้: SOS repository ไม่พร้อมใช้งาน');
      return;
    }
    final payload = packet.payload;
    if (payload['ownerDeviceId'] != packet.senderDeviceId) {
      protocolErrorCount++;
      _log('SOS rejected: owner identity mismatch');
      return;
    }
    final sosId = payload['sosId']! as String;
    final existingEvent = await sos!.getById(sosId);
    diagnostics?.record(
      'sos',
      'sos_receive_step_completed',
      peerIdentifier: endpointId,
      fields: {'checkpoint': 'duplicate_lookup'},
    );
    final stateRevision = payload['stateRevision'] as int?;
    final revisionKey = 'nearby_sos_revision_${packet.senderDeviceId}';
    final previouslyObserved =
        _receivedSosRevisions[packet.senderDeviceId] ?? 0;
    if (stateRevision != null && stateRevision <= previouslyObserved) {
      diagnostics?.record(
        'sos',
        'sos_stale_state_ignored',
        peerIdentifier: endpointId,
        fields: {
          'isActive': payload['isActive'],
          'stateRevision': stateRevision,
          'checkpoint': 'state_order',
        },
      );
      if (!viaRelay) await _sendAck(endpointId, packet);
      return;
    }
    final lastRevision = stateRevision == null || settings == null
        ? 0
        : await settings!.getInt(revisionKey, defaultValue: 0);
    if (stateRevision != null &&
        (stateRevision <= lastRevision ||
            stateRevision <= previouslyObserved)) {
      diagnostics?.record(
        'sos',
        'sos_stale_state_ignored',
        peerIdentifier: endpointId,
        fields: {
          'isActive': payload['isActive'],
          'stateRevision': stateRevision,
          'checkpoint': 'state_order',
        },
      );
      if (!viaRelay) await _sendAck(endpointId, packet);
      return;
    }
    final event = await sos!.createIncoming(
      id: sosId,
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
      requesterDisplayName: payload['displayName']! as String,
    );
    diagnostics?.record(
      'sos',
      'sos_receive_step_completed',
      peerIdentifier: endpointId,
      fields: {'checkpoint': 'event_repository_write'},
    );
    if (stateRevision != null &&
        settings != null &&
        stateRevision > lastRevision) {
      await settings!.setInt(revisionKey, stateRevision);
      diagnostics?.record(
        'sos',
        'sos_receive_step_completed',
        peerIdentifier: endpointId,
        fields: {'checkpoint': 'revision_persistence'},
      );
    }
    if (stateRevision != null) {
      _receivedSosRevisions[packet.senderDeviceId] = stateRevision;
    }
    final displayName = payload['displayName']! as String;
    final status = await _statusWithSosPrecedence(
      event.ownerDeviceId,
      DeviceStatus.normal,
    );
    diagnostics?.record(
      'sos',
      'sos_received_persisted',
      peerIdentifier: endpointId,
      fields: {
        'isActive': event.isActive,
        'resultingStatus': status.name,
        'hasLocation': event.latitude != null && event.longitude != null,
        'hasDistressInformation': event.message?.trim().isNotEmpty == true,
      },
    );
    if (event.isActive &&
        existingEvent == null &&
        _incomingSosNotificationClaims.add(event.id)) {
      await _notifyIncoming(
        id: event.id,
        title: displayName,
        route: Uri(
          path: '/rescue/request/${event.ownerDeviceId}',
          queryParameters: {'eventId': event.id},
        ).toString(),
        urgent: true,
      );
    }
    peerStatuses[event.ownerDeviceId] = status;
    await nearbyDevices.upsert(
      deviceId: event.ownerDeviceId,
      displayName: displayName,
      status: status,
    );
    diagnostics?.record(
      'sos',
      'sos_receive_step_completed',
      peerIdentifier: endpointId,
      fields: {'checkpoint': 'peer_repository_write'},
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
    diagnostics?.record(
      'sos',
      'sos_receive_step_completed',
      peerIdentifier: endpointId,
      fields: {'checkpoint': 'conversation_repository_write'},
    );
    if (!viaRelay) {
      _updatePeerIdentity(
        endpointId,
        event.ownerDeviceId,
        displayName: displayName,
      );
    }
    _log(
      event.isActive
          ? 'SOS RECEIVED จาก $displayName'
          : 'SOS cleared จาก $displayName',
    );
    if (!viaRelay) await _sendAck(endpointId, packet);
    diagnostics?.record(
      'sos',
      'sos_receive_step_completed',
      peerIdentifier: endpointId,
      fields: {'checkpoint': 'ack_send'},
    );
  }

  Future<void> _sendAck(String endpointId, RelioPacket packet) async {
    final ack = RelioPacket.ack(
      senderDeviceId: await identity.getDeviceId(),
      senderUserId: await _senderUserId(),
      acknowledgedPacketId: packet.packetId,
      messageId: packet.payload['messageId'] as String?,
    );
    await _sendApplicationBytes(ack, peerId: endpointId, replyTo: packet);
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
    if (conversations is DriftConversationRepository) {
      final repository = conversations as DriftConversationRepository;
      final remote = await repository.activeRemotePrincipal(deviceId);
      for (final row in existing) {
        if (await repository.remotePrincipalForConversation(row.id) == remote) {
          return row.id;
        }
      }
      return fallback;
    }
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
    String? fingerprint,
  }) {
    if (endpointId == null) return;
    if (_retiredConnectionEndpoints.contains(endpointId) &&
        !_connectionTraces.containsKey(endpointId)) {
      return;
    }
    final oldEndpoints = endpointToDeviceId.entries
        .where((entry) => entry.value == deviceId && entry.key != endpointId)
        .map((entry) => entry.key)
        .toList();
    for (final oldEndpoint in oldEndpoints) {
      endpointToDeviceId.remove(oldEndpoint);
      _completedIdentityHandshakes.remove(oldEndpoint);
      _invalidateEndpoint(oldEndpoint);
      if (peerStates[oldEndpoint] == NearbyConnectionState.connected) {
        _track(disconnect(oldEndpoint, reason: 'canonical_endpoint_replaced'));
      }
    }
    endpointToDeviceId[endpointId] = deviceId;
    deviceToEndpointId[deviceId] = endpointId;
    final index = discoveredPeers.indexWhere((peer) => peer.id == endpointId);
    if (index == -1) return;
    final peer = discoveredPeers[index];
    discoveredPeers[index] = peer.withIdentity(
      deviceId: deviceId,
      name: displayName,
      connected: peerStates[endpointId] == NearbyConnectionState.connected,
      capabilities: capabilities,
      fingerprint: fingerprint,
    );
    _log(
      'identity established endpoint=${DiagnosticsLogService.peerAlias(endpointId)} '
      'canonical=${DiagnosticsLogService.peerAlias(deviceId)} epoch=${peer.discoveryEpoch}',
    );
  }

  void _recordVerifiedEndpointBinding(
    String endpointId,
    String deviceId,
    String stage,
  ) {
    if (!RelioBuildInfo.isTest) return;
    diagnostics?.record(
      'identity',
      'nearby_endpoint_canonical_bound',
      connectionTraceId: _connectionTraces[endpointId],
      peerIdentifier: endpointId,
      fields: {
        'canonicalDeviceAlias': DiagnosticsLogService.peerAlias(deviceId),
        'identityStage': stage,
        'sessionId': _connectionTraces[endpointId],
        'discoveryEpoch': transport.discoveryEpoch,
      },
    );
  }

  List<String> _capabilitiesFrom(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];

  DeviceStatus _statusFrom(String value) => DeviceStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => DeviceStatus.normal,
  );

  Map<String, Object?> _peerMetadataRepositoryFields(RelioPacket packet) {
    final payload = packet.payload;
    final rawLatitude = payload['latitude'];
    final rawLongitude = payload['longitude'];
    return {
      if (payload['batteryLevel'] is int)
        'batteryLevel': payload['batteryLevel'],
      if (payload['isCharging'] is bool) 'isCharging': payload['isCharging'],
      if (payload['deviceModel'] is String)
        'peerDeviceModel': payload['deviceModel'],
      if (DateTime.tryParse(payload['batteryUpdatedAt'] as String? ?? '')
          case final DateTime updatedAt)
        'batteryUpdatedAt': updatedAt,
      if (rawLatitude is num && rawLongitude is num)
        ...() {
          final lat = rawLatitude.toDouble();
          final lng = rawLongitude.toDouble();
          if (NearbyMapCalculations.isValidPoint(lat, lng)) {
            final rawAcc = payload['locationAccuracy'];
            final acc = rawAcc is num && rawAcc >= 0 ? rawAcc.toDouble() : null;
            final capturedAt = DateTime.tryParse(
              payload['locationCapturedAt'] as String? ?? '',
            );
            if (capturedAt == null ||
                !NearbyLocationQuality.isEligibleForCurrentSharing(
                  LocationData(
                    latitude: lat,
                    longitude: lng,
                    accuracyMeters: acc,
                    capturedAt: capturedAt,
                    source: 'nearby',
                  ),
                  now: DateTime.now(),
                )) {
              return const <String, Object?>{};
            }
            final fields = <String, Object?>{
              'peerLatitude': lat,
              'peerLongitude': lng,
            };
            if (acc != null) {
              fields['peerLocationAccuracy'] = acc;
            }
            fields['peerLocationCapturedAt'] = capturedAt;
            return fields;
          }
          return const <String, Object?>{};
        }(),
    };
  }

  Future<void> _persistPeerMetadata(
    RelioPacket packet, {
    DeviceStatus? status,
  }) async {
    final metadata = _peerMetadataRepositoryFields(packet);
    if (metadata.isEmpty && status == null) return;
    final existing = await nearbyDevices.getDevice(packet.senderDeviceId);
    await nearbyDevices.upsert(
      deviceId: packet.senderDeviceId,
      displayName: packet.payload['displayName']! as String,
      status:
          status ??
          peerStatuses[packet.senderDeviceId] ??
          existing?.status ??
          DeviceStatus.normal,
      batteryLevel: metadata['batteryLevel'] as int?,
      isCharging: metadata['isCharging'] as bool?,
      batteryUpdatedAt: metadata['batteryUpdatedAt'] as DateTime?,
      peerLatitude: metadata['peerLatitude'] as double?,
      peerLongitude: metadata['peerLongitude'] as double?,
      peerLocationAccuracy: metadata['peerLocationAccuracy'] as double?,
      peerLocationCapturedAt: metadata['peerLocationCapturedAt'] as DateTime?,
      peerDeviceModel: metadata['peerDeviceModel'] as String?,
    );
  }

  Future<DeviceStatus> _statusWithSosPrecedence(
    String deviceId,
    DeviceStatus reportedStatus,
  ) async {
    if (await sos?.readActive(ownerDeviceId: deviceId) != null) {
      return DeviceStatus.sos;
    }
    final rescueActive = _peerRescueActive[deviceId];
    if (rescueActive == true ||
        (rescueActive == null && reportedStatus == DeviceStatus.rescue)) {
      return DeviceStatus.rescue;
    }
    // SOS is authoritative only while its persisted event is active. A stale
    // hello/status packet must not resurrect the peer after an accepted clear.
    if (reportedStatus == DeviceStatus.sos) return DeviceStatus.normal;
    return reportedStatus;
  }

  void _rememberPeerRescueState(
    RelioPacket packet,
    DeviceStatus reportedStatus,
  ) {
    final explicitState = packet.payload['rescueActive'];
    if (explicitState is bool) {
      _peerRescueActive[packet.senderDeviceId] = explicitState;
    } else if (reportedStatus == DeviceStatus.rescue) {
      _peerRescueActive[packet.senderDeviceId] = true;
    } else if (reportedStatus == DeviceStatus.normal) {
      _peerRescueActive[packet.senderDeviceId] = false;
    }
  }

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
    identity.profiles.removeListener(_onProfileChanged);
    super.dispose();
    unawaited(close());
  }

  Future<void> close() async {
    _qaRestrictionExpiry?.cancel();
    _qaRestrictedDeviceId = null;
    _qaRestrictionExpiresAt = null;
    _reachabilityPublishTimer?.cancel();
    _reachabilityExpiryTimer?.cancel();
    _qaRelayRetryTimer?.cancel();
    if (_closed) return;
    identity.profiles.removeListener(_onProfileChanged);
    _recordSessionStop(
      caller: 'NearbyService.close',
      reason: 'service_dispose',
    );
    _closed = true;
    await _locationCoordinator?.dispose();
    stopBatteryMetadataUpdates();
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
    for (final timer in _secondaryInitiatorFallbackTimers.values) {
      timer.cancel();
    }
    _secondaryInitiatorFallbackTimers.clear();
    _secondaryInitiatorFingerprints.clear();
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
    await Future.wait(_disconnectTasks.values.toList());
    await Future.wait(_textConversationTails.values.toList());
    await transport.dispose();
  }
}
