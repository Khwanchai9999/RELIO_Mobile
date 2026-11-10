// หน้าค้นหาและแสดงอุปกรณ์ Nearby จริง พร้อมตัวกรอง สถานะ SOS/Rescue และทางลัดการสื่อสาร
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../core/connectivity/runtime_connectivity.dart';
import '../../core/device/battery_info_service.dart';
import '../../core/nearby/nearby_reachability.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/location/nearby_map_calculations.dart';
import '../../core/location/nearby_location_quality.dart';
import '../../core/location/location_service.dart';
import '../../core/nearby/nearby_service.dart';
import '../../core/nearby/nearby_readiness.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/nearby/bluetooth_classic_transport.dart';
import '../../core/relio_dependencies.dart';
import '../../core/feature_flags/feature_flags.dart';
import '../../data/mock_data.dart';
import '../../data/models/prototype_models.dart';
import 'nearby_map_canvas.dart';
import 'nearby_location_consent_dialog.dart';
import 'nearby_peer_detail_sheet.dart';
import 'nearby_route_preview_card.dart';
import 'current_nearby_map_peers.dart';
import '../../shared/widgets/relio_widgets.dart';

// ชนิดตัวเลือกที่ระบุสถานะหรือโหมดซึ่งส่วนอื่นของโมดูลนำไปใช้: Nearby Filter
enum NearbyFilter { all, sos, rescue, normal }

bool isFreshNearbyBattery(
  RelioNearbyDevice device, {
  required bool connected,
  DateTime? now,
}) {
  final updatedAt = device.batteryUpdatedAt;
  final level = device.batteryLevel;
  if (!connected ||
      level == null ||
      level < 0 ||
      level > 100 ||
      updatedAt == null) {
    return false;
  }
  final age = NearbyLocationQuality.effectiveAge(
    updatedAt,
    now ?? DateTime.now(),
  );
  return age != null && age <= const BatteryPublishPolicy().maxDisplayAge;
}

Iterable<NearbyPeer> visibleNearbyPeers(NearbyService nearby) =>
    nearby.currentPeers;

// หน้ารวมการค้นหาและเชื่อมต่ออุปกรณ์ Nearby พร้อมแสดง peer จริงแยกจากข้อมูลตัวอย่าง
// การคุยส่วนตัวต้อง resolve endpoint จาก principal/conversation ที่ตรวจสอบแล้ว
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({
    this.initialTargetId,
    this.initialTargetLatitude,
    this.initialTargetLongitude,
    this.initialTargetAccuracy,
    this.initialTargetHistorical = false,
    this.initialTargetSharedLocation = false,
    this.initialTargetCapturedAt,
    super.key,
  });

  final String? initialTargetId;
  final double? initialTargetLatitude;
  final double? initialTargetLongitude;
  final double? initialTargetAccuracy;
  final bool initialTargetHistorical;
  final bool initialTargetSharedLocation;
  final DateTime? initialTargetCapturedAt;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Nearby Screen State)
class _NearbyScreenState extends State<NearbyScreen> {
  NearbyFilter _filter = NearbyFilter.all;
  bool _loaded = false;
  bool _panelExpanded = true;
  bool _listMode = false;
  bool _locating = false;
  bool _locationConsentPromptPending = false;
  int _locationFocusRequest = 0;
  LocationData? _myLocation;
  LocationData? _targetLocationOverride;
  String? _navigationTargetId;
  late RelioDependencies _dependencies;
  late NearbyService _nearby;
  List<RelioNearbyDevice> _savedDevices = const [];

  bool get _mapEnabled =>
      _dependencies.featureFlags.isEnabled(RelioFeatureFlag.nearbyMapUi);

  bool get _batteryEnabled =>
      _dependencies.featureFlags.isEnabled(RelioFeatureFlag.peerBatteryUi);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _dependencies = RelioDependencyScope.of(context);
    _listMode = !_dependencies.featureFlags.isEnabled(
      RelioFeatureFlag.nearbyMapUi,
    );
    _navigationTargetId = widget.initialTargetId;
    _targetLocationOverride = _locationFromRoute();
    if (widget.initialTargetId != null && !_listMode) _listMode = false;
    _nearby = _dependencies.nearbyService;
    _dependencies.featureFlags.addListener(_onFeatureFlagsChanged);
    _dependencies.internalExperience.addListener(_onDemoModeChanged);
    _nearby.addListener(_onNearbyChanged);
    _nearby.startBatteryMetadataUpdates();
    _dependencies.connectivityStatus.addListener(_onNearbyChanged);
    unawaited(_dependencies.startNearbySessionIfPermitted());
    _myLocation = _nearby.lastLiveLocation;
    unawaited(_loadSavedDevices());
    _maybePromptForLocationConsent();
  }

  @override
  void didUpdateWidget(covariant NearbyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTargetId != widget.initialTargetId ||
        oldWidget.initialTargetLatitude != widget.initialTargetLatitude ||
        oldWidget.initialTargetLongitude != widget.initialTargetLongitude ||
        oldWidget.initialTargetAccuracy != widget.initialTargetAccuracy ||
        oldWidget.initialTargetCapturedAt != widget.initialTargetCapturedAt ||
        oldWidget.initialTargetHistorical != widget.initialTargetHistorical ||
        oldWidget.initialTargetSharedLocation !=
            widget.initialTargetSharedLocation) {
      _navigationTargetId = widget.initialTargetId;
      _targetLocationOverride = _locationFromRoute();
      if (widget.initialTargetId != null && _mapEnabled) _listMode = false;
    }
  }

  LocationData? _locationFromRoute() {
    if (!NearbyMapCalculations.isValidPoint(
      widget.initialTargetLatitude,
      widget.initialTargetLongitude,
    )) {
      return null;
    }
    return LocationData(
      latitude: widget.initialTargetLatitude!,
      longitude: widget.initialTargetLongitude!,
      accuracyMeters: widget.initialTargetAccuracy,
      capturedAt:
          widget.initialTargetCapturedAt ??
          DateTime.fromMillisecondsSinceEpoch(0),
      source: widget.initialTargetSharedLocation
          ? 'chat_shared_location'
          : widget.initialTargetHistorical
          ? 'sos_history'
          : 'sos',
    );
  }

  @override
  void dispose() {
    _nearby.removeListener(_onNearbyChanged);
    _dependencies.featureFlags.removeListener(_onFeatureFlagsChanged);
    _dependencies.internalExperience.removeListener(_onDemoModeChanged);
    _nearby.stopBatteryMetadataUpdates();
    _dependencies.connectivityStatus.removeListener(_onNearbyChanged);
    super.dispose();
  }

  void _onNearbyChanged() {
    if (!mounted) return;
    setState(() {
      _myLocation = _nearby.lastLiveLocation ?? _myLocation;
    });
    _maybePromptForLocationConsent();
    unawaited(_loadSavedDevices());
  }

  void _maybePromptForLocationConsent() {
    if (!_nearby.locationSettingsLoaded ||
        _nearby.liveLocationSharingConsent != null ||
        _locationConsentPromptPending) {
      return;
    }
    _locationConsentPromptPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _locationConsentPromptPending = false;
        return;
      }
      unawaited(_showLocationConsent(firstUse: true));
    });
  }

  Future<void> _showLocationConsent({required bool firstUse}) async {
    final approved = await showNearbyLiveLocationConsentDialog(
      context,
      firstUse: firstUse,
    );
    _locationConsentPromptPending = false;
    if (approved == null) return;

    var permissionGranted = true;
    if (approved) {
      try {
        permissionGranted = await _dependencies.permissionService
            .requestLiveLocationPermission();
      } on Object {
        permissionGranted = false;
      }
    }
    await _nearby.setLiveLocationConsent(approved);
    if (approved) {
      await _nearby.locationCoordinator?.onPermissionOrReadinessChanged();
    }
    if (approved && !permissionGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ยังไม่ได้รับอนุญาต Location • ตรวจสอบสิทธิ์ได้ในตั้งค่า Android',
          ),
        ),
      );
    }
  }

  void _onFeatureFlagsChanged() {
    if (!mounted) return;
    if (!_dependencies.featureFlags.isEnabled(RelioFeatureFlag.nearbyMapUi)) {
      _listMode = true;
      _navigationTargetId = null;
    } else if (!_dependencies.featureFlags.isEnabled(
      RelioFeatureFlag.routePreview,
    )) {
      _navigationTargetId = null;
    }
    setState(() {});
  }

  void _onDemoModeChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadSavedDevices() async {
    final devices = await _dependencies.repositories.nearbyDevices
        .listDevices();
    if (!mounted) return;
    setState(() => _savedDevices = devices);
  }

  Future<void> _locateCurrentPosition() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final result = await _dependencies.locationService.getFreshLocation();
      final location = result.location;
      if (!mounted) return;
      if (location == null ||
          !NearbyLocationQuality.isEligibleForCurrentSharing(
            location,
            now: DateTime.now(),
          )) {
        final failure = result.failure;
        final mayNeedSettings =
            failure == LocationFailure.approximatePermission ||
            failure == LocationFailure.permissionDeniedForever;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_nearbyLocationFailureText(failure)),
            action: mayNeedSettings
                ? SnackBarAction(
                    label: 'ตั้งค่า',
                    onPressed: () => unawaited(
                      _dependencies.locationService.openAppSettings(),
                    ),
                  )
                : null,
          ),
        );
        return;
      }
      setState(() {
        _myLocation = location;
        _locationFocusRequest++;
      });
      if (NearbyLocationQuality.confidence(location.accuracyMeters) ==
          LocationConfidence.low) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ตำแหน่งเป็นค่าโดยประมาณ: ${NearbyLocationQuality.accuracyLabel(location.accuracyMeters)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String _nearbyLocationFailureText(LocationFailure? failure) =>
      switch (failure) {
        LocationFailure.permissionDenied => 'กรุณาอนุญาต Location ขณะใช้แอป',
        LocationFailure.permissionDeniedForever =>
          'สิทธิ์ Location ถูกปิดไว้ เปิด Precise Location ในการตั้งค่า',
        LocationFailure.approximatePermission =>
          'อนุญาตเฉพาะตำแหน่งคร่าว ๆ กรุณาเลือก Precise Location',
        LocationFailure.serviceDisabled => 'กรุณาเปิด Location/GPS ของเครื่อง',
        LocationFailure.timeout => 'ยังหา GPS สดไม่พบ ลองอีกครั้งกลางแจ้ง',
        LocationFailure.staleFix => 'GPS ส่งตำแหน่งเก่าหรือเวลาไม่ถูกต้อง',
        LocationFailure.invalidFix => 'ข้อมูลพิกัดไม่ถูกต้อง',
        LocationFailure.unavailable ||
        null => 'ยังรับตำแหน่งปัจจุบันไม่ได้ กรุณาตรวจสอบ GPS',
      };

  void _showPeerDetails(String deviceId) {
    final device = _mapPeers.where((peer) => peer.id == deviceId).firstOrNull;
    if (device == null) return;
    unawaited(
      showNearbyPeerDetailSheet(
        context: context,
        device: device,
        nearby: _nearby,
        myLocation: _myLocation,
        showBattery: _dependencies.featureFlags.isEnabled(
          RelioFeatureFlag.peerBatteryUi,
        ),
        showRoutePreview: _dependencies.featureFlags.isEnabled(
          RelioFeatureFlag.routePreview,
        ),
        onChat: () {
          final endpointId = _nearby.deviceToEndpointId[device.id];
          if (endpointId == null ||
              _nearby.peerStates[endpointId] !=
                  NearbyConnectionState.connected) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('peer ยังไม่ได้เชื่อมต่อ Nearby')),
            );
            return;
          }
          unawaited(_openPeerChat(device.id, device.name, device.status));
        },
        onNavigate: () {
          if (!NearbyMapCalculations.isValidPoint(
            device.locationLatitude,
            device.locationLongitude,
          )) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('peer ยังไม่ได้แชร์ตำแหน่ง')),
            );
            return;
          }
          setState(() {
            _navigationTargetId = device.id;
            _listMode = false;
          });
        },
      ),
    );
  }

  List<RelioDevice> get _mapPeers {
    final currentIds = currentNearbyMapPeerIds(
      savedDevices: _savedDevices,
      authenticatedPeers: _nearby.authenticatedConnectedPeers,
      now: DateTime.now(),
    );
    return _savedDevices
        .where(
          (saved) =>
              currentIds.contains(saved.deviceId) &&
              !RelioMockData.isDemoId(saved.deviceId) &&
              _matches(_nearby.peerStatuses[saved.deviceId] ?? saved.status),
        )
        .map((saved) {
          final status = _nearby.peerStatuses[saved.deviceId] ?? saved.status;
          return RelioDevice(
            id: saved.deviceId,
            name: saved.displayName,
            status: status,
            signalQuality: 0,
            isConnected: _nearby.isDeviceConnected(saved.deviceId),
            isDemo: false,
            presence: _nearby.isDeviceConnected(saved.deviceId)
                ? PeerPresence.connected
                : PeerPresence.stale,
            lastSeenAt: saved.lastSeenAt,
            batteryLevel:
                isFreshNearbyBattery(
                  saved,
                  connected: _nearby.isDeviceConnected(saved.deviceId),
                )
                ? saved.batteryLevel
                : null,
            isCharging:
                isFreshNearbyBattery(
                  saved,
                  connected: _nearby.isDeviceConnected(saved.deviceId),
                )
                ? saved.isCharging
                : null,
            peerDeviceModel: saved.peerDeviceModel,
            locationLatitude: saved.peerLatitude,
            locationLongitude: saved.peerLongitude,
            locationAccuracyMeters: saved.peerLocationAccuracy,
            locationCapturedAt: saved.peerLocationCapturedAt,
          );
        })
        .toList(growable: false);
  }

  Future<void> _startSearching() async {
    final started = await _dependencies.startNearbySessionIfPermitted(
      force: true,
    );
    if (!mounted) return;
    if (!started) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_nearby.statusLabel)));
    }
  }

  Future<void> _requestPermissions() async {
    final result = await _dependencies.permissionService
        .requestNearbyPermissions();
    if (!result.allGranted) {
      await _dependencies.permissionService.openAppSettings();
    }
    await _startSearching();
  }

  Future<void> _resolveBlocker() async {
    final blockers = _nearby.readiness?.blockers ?? const <NearbyBlocker>[];
    if (blockers.contains(NearbyBlocker.permissionMissing)) {
      await _requestPermissions();
      return;
    }
    final action = blockers.contains(NearbyBlocker.bluetoothOff)
        ? 'bluetooth'
        : blockers.contains(NearbyBlocker.locationRequiredButOff)
        ? 'location'
        : blockers.contains(NearbyBlocker.playServicesUnavailable)
        ? 'playServices'
        : 'app';
    await _dependencies.permissionService.openNearbySettings(action);
  }

  Future<void> _openPeerChat(
    String deviceId,
    String displayName,
    DeviceStatus status, {
    bool viaRelay = false,
  }) async {
    try {
      // device ID ไม่ใช่ conversation ID; ให้ Repository เลือกคู่ principal ปัจจุบันก่อน
      final repositories = _dependencies.repositories;
      final conversation = viaRelay
          ? await _nearby.openRemoteTextConversation(deviceId)
          : await repositories.ownerContext.run(
              () => repositories.conversations.ensureConversation(
                id: deviceId,
                participantId: deviceId,
                displayName: displayName,
                participantStatus: status,
              ),
            );
      if (!mounted) return;
      if (conversation == null) {
        _showSnack('ยังยืนยันผู้รับผ่านรีเลย์ QA ไม่ได้ กรุณาลองอีกครั้ง');
        return;
      }
      context.push('/chat/${conversation.id}');
    } on Object {
      if (mounted) _showSnack('เปิดแชทไม่สำเร็จ กรุณาลองอีกครั้ง');
    }
  }

  Future<void> _openRealPeer(NearbyPeer peer) async {
    final state = _nearby.peerStates[peer.endpointId];
    if (state == NearbyConnectionState.connected && peer.deviceId != null) {
      await _openPeerChat(
        peer.deviceId!,
        peer.name,
        _nearby.peerStatuses[peer.deviceId] ?? DeviceStatus.normal,
      );
      return;
    }
    if (state == NearbyConnectionState.connected) {
      final timedOut = _nearby.peerErrors[peer.endpointId] == 'hello_timeout';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            timedOut
                ? 'เชื่อมต่อแล้ว แต่ไม่ได้รับการยืนยัน RELIO จากอุปกรณ์นี้'
                : 'กำลังยืนยันตัวตน RELIO กับอุปกรณ์นี้',
          ),
        ),
      );
      return;
    }
    if (state != NearbyConnectionState.connecting) {
      await _nearby.connectPeer(peer);
    }
  }

  Future<void> _updateSavedPeer(RelioNearbyDevice device, String action) async {
    final repository = _dependencies.repositories.nearbyDevices;
    switch (action) {
      case 'trust':
        await repository.setTrusted(device.deviceId, true);
      case 'untrust':
        await repository.setTrusted(device.deviceId, false);
      case 'remove-trust':
        await _confirmRemoveTrustedPeer(device);
        return;
      case 'block':
        await repository.setBlocked(device.deviceId, true);
        final endpointId = _nearby.deviceToEndpointId[device.deviceId];
        if (endpointId != null) await _nearby.disconnect(endpointId);
      case 'unblock':
        await repository.setBlocked(device.deviceId, false);
    }
    await _loadSavedDevices();
  }

  Future<void> _confirmRemoveTrustedPeer(RelioNearbyDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบอุปกรณ์ที่เชื่อถือหรือไม่?'),
        content: const Text(
          'ครั้งต่อไปที่เชื่อมต่อกับอุปกรณ์นี้ จะต้องยืนยันรหัสใหม่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ลบอุปกรณ์ที่เชื่อถือ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _nearby.removeTrustedPeer(device.deviceId);
    await _loadSavedDevices();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('ลบอุปกรณ์ที่เชื่อถือแล้ว')));
  }

  List<NearbyPeer> get _livePeers {
    final seen = <String>{};
    final peers = visibleNearbyPeers(_nearby).where((peer) {
      final key = peer.endpointId.startsWith('classic:')
          ? peer.endpointId
          : peer.deviceId ?? peer.endpointId;
      return seen.add(key);
    }).toList();
    peers.sort((a, b) {
      final aConnected =
          _nearby.peerStates[a.endpointId] == NearbyConnectionState.connected;
      final bConnected =
          _nearby.peerStates[b.endpointId] == NearbyConnectionState.connected;
      if (aConnected != bConnected) return aConnected ? -1 : 1;
      final aStatus = _nearby.peerStatuses[a.deviceId];
      final bStatus = _nearby.peerStatuses[b.deviceId];
      final aPriority = aStatus == DeviceStatus.sos
          ? 0
          : aStatus == DeviceStatus.rescue
          ? 1
          : 2;
      final bPriority = bStatus == DeviceStatus.sos
          ? 0
          : bStatus == DeviceStatus.rescue
          ? 1
          : 2;
      return aPriority.compareTo(bPriority);
    });
    return peers;
  }

  List<RelioDevice> get _stalePeers {
    final liveIds = _livePeers.map((peer) => peer.deviceId).whereType<String>();
    final now = DateTime.now();
    return _savedDevices
        .where(
          (device) =>
              !RelioMockData.isDemoId(device.deviceId) &&
              !liveIds.contains(device.deviceId),
        )
        .map((device) {
          final age = now.difference(device.lastSeenAt);
          return RelioDevice(
            id: device.deviceId,
            name: device.displayName,
            status: device.status,
            signalQuality: 0,
            isConnected: false,
            isDemo: false,
            presence: age > const Duration(minutes: 2)
                ? PeerPresence.stale
                : PeerPresence.disconnected,
            lastSeenAt: device.lastSeenAt,
            batteryLevel: null,
            isCharging: null,
            peerDeviceModel: device.peerDeviceModel,
            locationLatitude: device.peerLatitude,
            locationLongitude: device.peerLongitude,
            locationAccuracyMeters: device.peerLocationAccuracy,
            locationCapturedAt: device.peerLocationCapturedAt,
            avatarPath: _nearby.avatarPathFor(device.deviceId),
          );
        })
        .toList(growable: false);
  }

  bool _matches(DeviceStatus status) => switch (_filter) {
    NearbyFilter.all => true,
    NearbyFilter.sos => status == DeviceStatus.sos,
    NearbyFilter.rescue => status == DeviceStatus.rescue,
    NearbyFilter.normal => status == DeviceStatus.normal,
  };

  RelioDevice _toLiveDevice(NearbyPeer peer) {
    final state = _nearby.peerStates[peer.endpointId];
    final verified =
        peer.deviceId != null &&
        _nearby.isEndpointVerifiedConnected(peer.endpointId);
    final status = _nearby.peerStatuses[peer.deviceId] ?? DeviceStatus.normal;
    final saved = _savedDevice(peer.deviceId);
    final freshBattery =
        saved != null &&
        isFreshNearbyBattery(
          saved,
          connected: state == NearbyConnectionState.connected,
        );
    return RelioDevice(
      id: peer.deviceId ?? 'pending:${peer.endpointId}',
      name: peer.name,
      status: status,
      signalQuality: 0,
      isConnected: verified,
      isDemo: false,
      presence: _nearby.peerErrors.containsKey(peer.endpointId)
          ? PeerPresence.failed
          : switch (state) {
              NearbyConnectionState.connecting => PeerPresence.connecting,
              NearbyConnectionState.connected =>
                verified ? PeerPresence.connected : PeerPresence.connecting,
              NearbyConnectionState.incomingRequest => PeerPresence.connecting,
              NearbyConnectionState.disconnected ||
              null => PeerPresence.discovered,
              NearbyConnectionState.failed => PeerPresence.failed,
            },
      batteryLevel: freshBattery ? saved.batteryLevel : null,
      isCharging: freshBattery ? saved.isCharging : null,
      peerDeviceModel: saved?.peerDeviceModel,
      locationLatitude: saved?.peerLatitude,
      locationLongitude: saved?.peerLongitude,
      locationAccuracyMeters: saved?.peerLocationAccuracy,
      locationCapturedAt: saved?.peerLocationCapturedAt,
      avatarPath: peer.deviceId == null
          ? null
          : _nearby.avatarPathFor(peer.deviceId!),
    );
  }

  RelioNearbyDevice? _savedDevice(String? deviceId) => deviceId == null
      ? null
      : _savedDevices
            .where((device) => device.deviceId == deviceId)
            .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final status = _dependencies.connectivityStatus.status;
    final readiness = _nearby.readiness ?? status.runtime.nearbyReadiness;
    final livePeers = _livePeers;
    final reachableCount = _nearby.reachablePeerCount;
    final remotePeers = _nearby.remoteReachablePeers;
    final remoteIds = remotePeers.map((peer) => peer.deviceId).toSet();
    final knownDevices = [
      ...livePeers.map(_toLiveDevice),
      ..._stalePeers,
    ].where((device) => !remoteIds.contains(device.id)).toList();
    final realDevices = knownDevices
        .where((device) => _matches(device.status))
        .toList();
    final demoEnabled = _dependencies.internalExperience.demoEnabled;
    final effectiveDemoDevices = demoEnabled
        ? RelioMockData.devices
        : const <RelioDevice>[];
    final demoDevices = effectiveDemoDevices
        .where((device) => _matches(device.status))
        .toList(growable: false);
    final realSosCount = [
      ...livePeers.map(_toLiveDevice),
      ..._stalePeers,
    ].where((device) => device.status == DeviceStatus.sos).length;
    final urgentCount =
        realSosCount +
        effectiveDemoDevices
            .where((device) => device.status == DeviceStatus.sos)
            .length;
    final mapEnabled = _dependencies.featureFlags.isEnabled(
      RelioFeatureFlag.nearbyMapUi,
    );
    final batteryEnabled = _dependencies.featureFlags.isEnabled(
      RelioFeatureFlag.peerBatteryUi,
    );

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (mapEnabled)
            NearbyMapCanvas(
              peers: _mapPeers,
              myLocation: _myLocation,
              navigationTargetId: _navigationTargetId,
              targetLocationOverride: _targetLocationOverride,
              targetLocationHistorical: widget.initialTargetHistorical,
              targetLocationShared: widget.initialTargetSharedLocation,
              onPeerSelected: _showPeerDetails,
              showBattery: batteryEnabled,
              locationFocusRequest: _locationFocusRequest,
            ),
          if (mapEnabled && _targetLocationOverride != null)
            _selectedLocationCard()
          else if (mapEnabled && _navigationTargetId != null)
            _routePreviewCard(),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _nearbyPanel(
                  status: status,
                  readiness: readiness,
                  peerCount: reachableCount,
                  urgentCount: urgentCount,
                  knownDevices: knownDevices,
                  remoteCount: remotePeers.length,
                  demoDevices: effectiveDemoDevices,
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            key: ValueKey(_listMode),
            initialChildSize: _listMode ? 0.56 : 0.13,
            minChildSize: 0.12,
            maxChildSize: 0.78,
            snap: true,
            snapSizes: const [0.13, 0.56, 0.78],
            builder: (context, scrollController) => Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 8,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    key: const ValueKey('nearby-sheet-handle'),
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  if (!_listMode)
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _listMode = true),
                        child: Center(
                          child: Text(
                            'อุปกรณ์ที่เข้าถึงได้ • $reachableCount เครื่อง  ดูรายการ',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: _nearbyList(
                        scrollController: scrollController,
                        realDevices: realDevices,
                        livePeers: livePeers,
                        remotePeers: _matches(DeviceStatus.normal)
                            ? remotePeers
                            : const [],
                        reachableCount: reachableCount,
                        demoDevices: demoDevices,
                        readiness: readiness,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (mapEnabled)
            Positioned(
              right: 16,
              bottom: 160,
              child: FloatingActionButton.small(
                heroTag: 'nearby-locate',
                onPressed: _locating ? null : _locateCurrentPosition,
                tooltip: 'ไปยังตำแหน่งของฉัน',
                child: _locating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded),
              ),
            ),
        ],
      ),
    );
  }

  Widget _routePreviewCard() {
    final target = _mapPeers
        .where((peer) => peer.id == _navigationTargetId)
        .firstOrNull;
    if (target == null) return const SizedBox.shrink();
    return NearbyRoutePreviewCard(
      peer: target,
      myLocation: _myLocation,
      onClose: () => setState(() => _navigationTargetId = null),
    );
  }

  Widget _selectedLocationCard() {
    final location = _targetLocationOverride!;
    final capturedAt = widget.initialTargetCapturedAt;
    final updated = capturedAt == null
        ? 'ไม่ทราบเวลาอัปเดต'
        : 'บันทึกเมื่อ ${capturedAt.year}-${capturedAt.month.toString().padLeft(2, '0')}-${capturedAt.day.toString().padLeft(2, '0')} ${capturedAt.hour.toString().padLeft(2, '0')}:${capturedAt.minute.toString().padLeft(2, '0')}';
    return Positioned(
      left: 12,
      right: 12,
      bottom: 104,
      child: Card(
        child: ListTile(
          leading: Icon(
            widget.initialTargetSharedLocation
                ? Icons.location_on_outlined
                : Icons.location_history_rounded,
            color: widget.initialTargetSharedLocation
                ? RelioColors.primary
                : RelioColors.rescue,
          ),
          title: Text(
            widget.initialTargetSharedLocation
                ? 'ตำแหน่งที่แชร์'
                : widget.initialTargetHistorical
                ? 'ตำแหน่ง SOS ที่บันทึกไว้'
                : 'ตำแหน่งจากคำขอ SOS',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${location.latitude.toStringAsFixed(widget.initialTargetSharedLocation ? 6 : 5)}, ${location.longitude.toStringAsFixed(widget.initialTargetSharedLocation ? 6 : 5)}'
            '${location.accuracyMeters == null ? '' : ' • ±${location.accuracyMeters!.round()} ม.'}\n'
            '$updated • ไม่ใช่ตำแหน่งสด',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            tooltip: widget.initialTargetSharedLocation
                ? 'ปิดตำแหน่งที่แชร์'
                : 'ปิดตำแหน่ง SOS',
            onPressed: () => setState(() {
              _targetLocationOverride = null;
              _navigationTargetId = null;
            }),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ),
    );
  }

  Widget _nearbyPanel({
    required InternetStatus status,
    required NearbyReadiness readiness,
    required int peerCount,
    required int urgentCount,
    required List<RelioDevice> knownDevices,
    required int remoteCount,
    required List<RelioDevice> demoDevices,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 5,
      color: colors.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _panelExpanded = !_panelExpanded),
                    child: Text(
                      _panelExpanded
                          ? 'อุปกรณ์ใกล้เคียง'
                          : 'อุปกรณ์ใกล้เคียง • $peerCount เครื่อง • SOS $urgentCount',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'ตรวจสอบ Internet',
                  onPressed: _dependencies.connectivityStatus.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: _panelExpanded ? 'ย่อแผงควบคุม' : 'ขยายแผงควบคุม',
                  onPressed: () =>
                      setState(() => _panelExpanded = !_panelExpanded),
                  icon: Icon(
                    _panelExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (_panelExpanded) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_internetLabel(status.reachability)} • Wi-Fi ${_radioLabel(status.runtime.wifiEnabled)} • Bluetooth ${_radioLabel(status.runtime.bluetoothEnabled)} • $peerCount เครื่อง',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (!readiness.ready)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Nearby ยังไม่พร้อม • ${readiness.summary}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                      TextButton(
                        onPressed:
                            readiness.blockers.contains(
                              NearbyBlocker.transportPermissionMissing,
                            )
                            ? null
                            : _resolveBlocker,
                        child: const Text('ตรวจสอบ'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('รายการ'),
                    selected: _listMode,
                    onSelected: (_) => setState(() => _listMode = true),
                  ),
                  if (_mapEnabled)
                    ChoiceChip(
                      label: const Text('แผนที่'),
                      selected: !_listMode,
                      onSelected: (_) => setState(() => _listMode = false),
                    ),
                  OutlinedButton.icon(
                    onPressed: _nearby.isDiscovering ? null : _startSearching,
                    icon: const Icon(Icons.radar_rounded, size: 18),
                    label: const Text('ค้นหาอุปกรณ์'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: NearbyFilter.values
                      .where((filter) => filter != NearbyFilter.normal)
                      .map(
                        (filter) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              _filterLabel(
                                filter,
                                knownDevices,
                                demoDevices,
                                remoteCount,
                              ),
                            ),
                            selected: _filter == filter,
                            selectedColor: _filterColor(filter),
                            labelStyle: TextStyle(
                              color: _filter == filter ? Colors.white : null,
                              fontWeight: FontWeight.w600,
                            ),
                            onSelected: (_) => setState(() {
                              _filter = filter;
                              _listMode = true;
                            }),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _nearbyList({
    required ScrollController scrollController,
    required List<RelioDevice> realDevices,
    required List<NearbyPeer> livePeers,
    required List<NearbyReachablePeer> remotePeers,
    required int reachableCount,
    required List<RelioDevice> demoDevices,
    required NearbyReadiness readiness,
  }) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Text(
          'อุปกรณ์ที่เข้าถึงได้ • $reachableCount เครื่อง',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (realDevices.isEmpty && remotePeers.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.radar_outlined),
              title: Text('ยังไม่พบอุปกรณ์จริง'),
              subtitle: Text(
                'เปิด RELIO และ Nearby บนอุปกรณ์ที่ต้องการเชื่อมต่อ โดยไม่จำเป็นต้องมี Internet',
              ),
            ),
          )
        else
          ...realDevices.map((device) {
            final peer = livePeers.cast<NearbyPeer?>().firstWhere(
              (item) =>
                  item?.deviceId == device.id ||
                  (device.id.startsWith('pending:') &&
                      item?.endpointId == device.id.substring(8)),
              orElse: () => null,
            );
            final saved = _savedDevice(device.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RelioDeviceCard(
                          device: device,
                          showBattery: _batteryEnabled,
                          peerIdentifier: peer == null
                              ? null
                              : bluetoothClassicAddressSuffix(peer.endpointId),
                          onTap: peer == null
                              ? (saved == null
                                    ? null
                                    : () => _showPeerDetails(saved.deviceId))
                              : () => _openRealPeer(peer),
                        ),
                      ],
                    ),
                  ),
                  if (saved != null)
                    PopupMenuButton<String>(
                      tooltip: 'ตั้งค่าอุปกรณ์ที่บันทึกไว้',
                      onSelected: (action) {
                        if (action == 'details') {
                          _showPeerDetails(saved.deviceId);
                        } else {
                          unawaited(_updateSavedPeer(saved, action));
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'details',
                          child: Text('ดูรายละเอียดและเส้นทาง'),
                        ),
                        PopupMenuItem(
                          value: saved.isTrusted ? 'remove-trust' : 'trust',
                          child: Text(
                            saved.isTrusted
                                ? 'ลบอุปกรณ์ที่เชื่อถือ'
                                : 'เชื่อถืออุปกรณ์นี้',
                          ),
                        ),
                        PopupMenuItem(
                          value: saved.isBlocked ? 'unblock' : 'block',
                          child: Text(
                            saved.isBlocked
                                ? 'ยกเลิกการบล็อก'
                                : 'บล็อกอุปกรณ์นี้',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          }),
        for (final peer in remotePeers)
          Card(
            key: ValueKey('nearby-remote-${peer.deviceId}'),
            child: ListTile(
              leading: const Icon(Icons.alt_route),
              title: Text(peer.name),
              subtitle: Text('เข้าถึงผ่านรีเลย์ • ${peer.hops} ทอด'),
              trailing: _nearby.canOpenRemoteTextChat
                  ? const Icon(Icons.chat_bubble_outline)
                  : null,
              onTap: _nearby.canOpenRemoteTextChat
                  ? () => _openPeerChat(
                      peer.deviceId,
                      peer.name,
                      DeviceStatus.normal,
                      viaRelay: true,
                    )
                  : null,
            ),
          ),
        if (demoDevices.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'ข้อมูลตัวอย่าง',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'ข้อมูล DEMO แยกจากอุปกรณ์จริงและไม่แสดงเป็น marker',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ...demoDevices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RelioDeviceCard(
                device: device,
                showBattery: _batteryEnabled,
                onTap: () => context.push('/chat/${device.id}'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _filterLabel(
    NearbyFilter filter,
    List<RelioDevice> real,
    List<RelioDevice> demo,
    int remoteCount,
  ) {
    final total = real.length + demo.length + remoteCount;
    return switch (filter) {
      NearbyFilter.all => 'ทั้งหมด ($total)',
      NearbyFilter.sos =>
        'SOS (${real.where((d) => d.status == DeviceStatus.sos).length + demo.where((d) => d.status == DeviceStatus.sos).length})',
      NearbyFilter.rescue =>
        'Rescue (${real.where((d) => d.status == DeviceStatus.rescue).length + demo.where((d) => d.status == DeviceStatus.rescue).length})',
      NearbyFilter.normal =>
        'ปกติ (${real.where((d) => d.status == DeviceStatus.normal).length + demo.where((d) => d.status == DeviceStatus.normal).length})',
    };
  }

  Color _filterColor(NearbyFilter filter) => switch (filter) {
    NearbyFilter.sos => RelioColors.sos,
    NearbyFilter.rescue => RelioColors.rescue,
    _ => RelioColors.primary,
  };
}

String _internetLabel(InternetReachability state) => switch (state) {
  InternetReachability.checking => 'กำลังตรวจสอบ',
  InternetReachability.online => 'ออนไลน์',
  InternetReachability.offline => 'ออฟไลน์',
  InternetReachability.limited => 'จำกัด',
  InternetReachability.unknown => 'ไม่ทราบ',
};

String _radioLabel(bool? enabled) => switch (enabled) {
  true => 'เปิด',
  false => 'ปิด',
  null => 'ไม่ทราบ',
};
