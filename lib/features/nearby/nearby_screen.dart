import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../core/connectivity/runtime_connectivity.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/location/nearby_map_calculations.dart';
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
import 'nearby_peer_detail_sheet.dart';
import 'nearby_route_preview_card.dart';
import '../../shared/widgets/relio_widgets.dart';

enum NearbyFilter { all, sos, rescue, normal }

bool isFreshNearbyBattery(
  RelioNearbyDevice device, {
  required bool connected,
  DateTime? now,
}) {
  final updatedAt = device.batteryUpdatedAt;
  if (!connected || device.batteryLevel == null || updatedAt == null) {
    return false;
  }
  final age = (now ?? DateTime.now()).difference(updatedAt);
  return !age.isNegative && age <= const Duration(minutes: 2);
}

Iterable<NearbyPeer> visibleNearbyPeers(NearbyService nearby) =>
    nearby.discoveredPeers.where(
      (peer) =>
          nearby.isEndpointCurrent(peer.endpointId) ||
          nearby.peerStates[peer.endpointId] == NearbyConnectionState.connected,
    );

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  NearbyFilter _filter = NearbyFilter.all;
  bool _loaded = false;
  bool _panelExpanded = true;
  bool _listMode = false;
  bool _sharingLocation = false;
  LocationData? _myLocation;
  String? _navigationTargetId;
  late RelioDependencies _dependencies;
  late NearbyService _nearby;
  List<RelioNearbyDevice> _savedDevices = const [];
  List<BondedBluetoothDevice> _bondedDevices = const [];

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
    _nearby = _dependencies.nearbyService;
    _dependencies.featureFlags.addListener(_onFeatureFlagsChanged);
    _nearby.addListener(_onNearbyChanged);
    _nearby.startBatteryMetadataUpdates();
    _dependencies.connectivityStatus.addListener(_onNearbyChanged);
    unawaited(_dependencies.startNearbySessionIfPermitted());
    unawaited(_loadSavedDevices());
  }

  @override
  void dispose() {
    _nearby.removeListener(_onNearbyChanged);
    _dependencies.featureFlags.removeListener(_onFeatureFlagsChanged);
    _nearby.stopBatteryMetadataUpdates();
    _dependencies.connectivityStatus.removeListener(_onNearbyChanged);
    super.dispose();
  }

  void _onNearbyChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_loadSavedDevices());
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

  Future<void> _loadSavedDevices() async {
    final devices = await _dependencies.repositories.nearbyDevices
        .listDevices();
    if (!mounted) return;
    setState(() => _savedDevices = devices);
  }

  Future<void> _shareCurrentLocation() async {
    if (_sharingLocation) return;
    setState(() => _sharingLocation = true);
    try {
      final result = await _dependencies.locationService
          .getCurrentOrLastKnown();
      if (!mounted) return;
      final location = result.location;
      if (location == null) {
        final detail = switch (result.failure) {
          LocationFailure.permissionDenied => 'ต้องอนุญาตตำแหน่งก่อน',
          LocationFailure.permissionDeniedForever =>
            'เปิดสิทธิ์ตำแหน่งจากการตั้งค่า Android',
          LocationFailure.serviceDisabled => 'เปิด Location/GPS ก่อน',
          _ => 'ยังอ่านตำแหน่งไม่ได้ ลองอีกครั้งภายหลัง',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(detail)));
        return;
      }
      setState(() => _myLocation = location);
      await _nearby.publishMapLocation(location);
      if (!mounted) return;
      final count = _nearby.connectedPeers
          .where((peer) => _nearby.deviceIdForEndpoint(peer.endpointId) != null)
          .length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'แสดงตำแหน่งของคุณบนเครื่องนี้แล้ว ยังไม่มี peer ที่ยืนยันและเชื่อมต่อ'
                : 'แชร์ตำแหน่งล่าสุดให้ peer ที่ยืนยันแล้ว $count เครื่อง',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharingLocation = false);
    }
  }

  void _showPeerDetails(String deviceId) {
    final device = _mapPeers.where((peer) => peer.id == deviceId).firstOrNull;
    if (device == null) return;
    unawaited(
      showNearbyPeerDetailSheet(
        context: context,
        device: device,
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
          context.push('/chat/${device.id}');
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

  List<RelioDevice> get _mapPeers => _savedDevices
      .where(
        (saved) =>
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

  Future<void> _loadBondedDevices() async {
    final devices = await _nearby.bondedBluetoothDevices();
    if (!mounted) return;
    setState(() => _bondedDevices = devices);
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

  Future<void> _openRealPeer(NearbyPeer peer) async {
    final state = _nearby.peerStates[peer.endpointId];
    if (state == NearbyConnectionState.connected && peer.deviceId != null) {
      if (mounted) context.push('/chat/${peer.deviceId}');
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
      await _nearby.connect(peer.endpointId);
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
      isConnected:
          state == NearbyConnectionState.connected && peer.deviceId != null,
      isDemo: false,
      presence: _nearby.peerErrors.containsKey(peer.endpointId)
          ? PeerPresence.failed
          : switch (state) {
              NearbyConnectionState.connecting => PeerPresence.connecting,
              NearbyConnectionState.connected =>
                peer.deviceId == null
                    ? PeerPresence.connecting
                    : PeerPresence.connected,
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
    final realDevices = [
      ...livePeers
          .map(_toLiveDevice)
          .where((device) => _matches(device.status)),
      ..._stalePeers.where((device) => _matches(device.status)),
    ];
    final demoDevices = RelioMockData.devices
        .where((device) => _matches(device.status))
        .toList(growable: false);
    final urgentCount = _savedDevices
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
              onPeerSelected: _showPeerDetails,
              showBattery: batteryEnabled,
            ),
          if (mapEnabled && _navigationTargetId != null) _routePreviewCard(),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _nearbyPanel(
                  status: status,
                  readiness: readiness,
                  peerCount: realDevices.length,
                  urgentCount: urgentCount,
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
                            'อุปกรณ์ที่พบจริง • ${realDevices.length} เครื่อง  ดูรายการ',
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
                heroTag: 'nearby-share-location',
                onPressed: _sharingLocation ? null : _shareCurrentLocation,
                tooltip: 'แชร์ตำแหน่งล่าสุดกับ peer ที่เชื่อมต่อ',
                child: _sharingLocation
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

  Widget _nearbyPanel({
    required InternetStatus status,
    required NearbyReadiness readiness,
    required int peerCount,
    required int urgentCount,
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
                                _livePeers
                                    .map(_toLiveDevice)
                                    .toList(growable: false),
                                RelioMockData.devices,
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
    required List<RelioDevice> demoDevices,
    required NearbyReadiness readiness,
  }) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Text(
          'อุปกรณ์ที่พบจริง • ${realDevices.length} เครื่อง',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (realDevices.isEmpty)
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
            final noLocation = !NearbyMapCalculations.isValidPoint(
              device.locationLatitude,
              device.locationLongitude,
            );
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
                        Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 4),
                          child: Text(
                            noLocation
                                ? 'ยังไม่มีตำแหน่ง • peer ยังอยู่ในรายการ'
                                : NearbyMapCalculations.freshnessLabel(
                                    device.locationCapturedAt,
                                    DateTime.now(),
                                  ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (saved?.isTrusted == true)
                          const Padding(
                            padding: EdgeInsets.only(left: 12, bottom: 4),
                            child: Text('อุปกรณ์ที่เชื่อถือแล้ว'),
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
        const SizedBox(height: 8),
        Text('ข้อมูลตัวอย่าง', style: Theme.of(context).textTheme.titleMedium),
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
        ExpansionTile(
          leading: const Icon(Icons.build_circle_outlined),
          title: const Text('เครื่องมือ QA / Diagnostics'),
          subtitle: const Text('ใช้เฉพาะการทดสอบ Bluetooth Classic'),
          children: [
            if (_nearby.compatibilityFallbackAvailable &&
                !_nearby.compatibilityModeActive)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await _nearby.activateCompatibilityMode(
                            serverRole: true,
                          );
                          if (mounted) {
                            _showSnack('RFCOMM listener พร้อมรับการเชื่อมต่อ');
                          }
                        },
                        child: const Text('Listener'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          await _nearby.activateCompatibilityMode(
                            serverRole: false,
                            bondedOnly: true,
                          );
                          await _loadBondedDevices();
                          if (mounted) _showSnack('โหลดอุปกรณ์ที่จับคู่แล้ว');
                        },
                        child: const Text('อุปกรณ์ที่จับคู่'),
                      ),
                    ),
                  ],
                ),
              ),
            if (_nearby.compatibilityModeActive)
              const ListTile(
                leading: Icon(Icons.bluetooth_connected),
                title: Text('Bluetooth Classic QA ทำงานอยู่'),
                subtitle: Text('ใช้หน้า Diagnostics เพื่อเปลี่ยนโหมด'),
              ),
            ..._bondedDevices.map(
              (device) => ListTile(
                leading: const Icon(Icons.bluetooth_connected),
                title: Text(device.name),
                subtitle: Text(
                  'Paired • ${bluetoothClassicAddressSuffix(device.endpointId)}',
                ),
                onTap: () => _openRealPeer(
                  NearbyPeer(id: device.endpointId, name: device.name),
                ),
              ),
            ),
          ],
        ),
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
  ) {
    final total = real.length + demo.length;
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
