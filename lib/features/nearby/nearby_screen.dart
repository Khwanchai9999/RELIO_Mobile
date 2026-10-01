import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/connectivity/runtime_connectivity.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/nearby/nearby_service.dart';
import '../../core/nearby/nearby_readiness.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/relio_dependencies.dart';
import '../../data/mock_data.dart';
import '../../data/models/prototype_models.dart';
import '../../shared/widgets/relio_widgets.dart';

enum NearbyFilter { all, sos, rescue, normal }

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  NearbyFilter _filter = NearbyFilter.all;
  bool _loaded = false;
  late RelioDependencies _dependencies;
  late NearbyService _nearby;
  List<RelioNearbyDevice> _savedDevices = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _dependencies = RelioDependencyScope.of(context);
    _nearby = _dependencies.nearbyService;
    _nearby.addListener(_onNearbyChanged);
    _dependencies.connectivityStatus.addListener(_onNearbyChanged);
    unawaited(_dependencies.startNearbySessionIfPermitted());
    unawaited(_loadSavedDevices());
  }

  @override
  void dispose() {
    _nearby.removeListener(_onNearbyChanged);
    _dependencies.connectivityStatus.removeListener(_onNearbyChanged);
    super.dispose();
  }

  void _onNearbyChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_loadSavedDevices());
  }

  Future<void> _loadSavedDevices() async {
    final devices = await _dependencies.repositories.nearbyDevices
        .listDevices();
    if (!mounted) return;
    setState(() => _savedDevices = devices);
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

  List<NearbyPeer> get _livePeers {
    final seen = <String>{};
    final peers = _nearby.discoveredPeers.where((peer) {
      final key = peer.deviceId ?? peer.endpointId;
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
              NearbyConnectionState.disconnected ||
              null => PeerPresence.discovered,
              NearbyConnectionState.failed => PeerPresence.failed,
            },
    );
  }

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

    return Scaffold(
      appBar: RelioAppBar(
        title: 'อุปกรณ์ใกล้เคียง',
        subtitle: 'ค้นหาและเชื่อมต่อโทรศัพท์จริงแบบออฟไลน์',
        actions: [
          IconButton(
            onPressed: _dependencies.connectivityStatus.refresh,
            tooltip: 'ตรวจสอบ Internet',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RelioSpacing.lg,
          4,
          RelioSpacing.lg,
          24,
        ),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(RelioSpacing.md),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text('Internet • ${_internetLabel(status.reachability)}'),
                  Text('Wi-Fi • ${_radioLabel(status.runtime.wifiEnabled)}'),
                  Text(
                    'Bluetooth • ${_radioLabel(status.runtime.bluetoothEnabled)}',
                  ),
                  if (readiness.policy.locationRequired)
                    Text(
                      'Location • ${_radioLabel(status.runtime.locationEnabled)}',
                    ),
                  Text('Nearby • ${_nearby.statusLabel}'),
                  if (readiness.wifiDegraded)
                    const Text(
                      'Wi-Fi ไม่พร้อม: ใช้ Bluetooth โดยความเร็วอาจลดลง',
                    ),
                  Text('เชื่อมต่อแล้ว • ${_nearby.connectedPeerCount} เครื่อง'),
                ],
              ),
            ),
          ),
          if (!readiness.ready)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Nearby ยังไม่พร้อม'),
                subtitle: Text(readiness.summary),
                trailing:
                    readiness.blockers.contains(
                      NearbyBlocker.transportPermissionMissing,
                    )
                    ? null
                    : TextButton(
                        onPressed: _resolveBlocker,
                        child: const Text('ตรวจสอบ'),
                      ),
              ),
            ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: NearbyFilter.values
                  .map(
                    (filter) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          _filterLabel(filter, realDevices, demoDevices),
                        ),
                        selected: _filter == filter,
                        selectedColor: _filterColor(filter),
                        labelStyle: TextStyle(
                          color: _filter == filter ? Colors.white : null,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _nearby.isDiscovering ? null : _startSearching,
                  icon: const Icon(Icons.radar_rounded),
                  label: const Text('ค้นหาอุปกรณ์จริง'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'อุปกรณ์ที่พบจริง',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (realDevices.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.radar_outlined),
                title: Text('ยังไม่พบอุปกรณ์จริง'),
                subtitle: Text(
                  'เปิด RELIO และ Nearby บนอุปกรณ์ทั้งสองเครื่อง โดยไม่จำเป็นต้องมี Internet',
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
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RelioDeviceCard(
                  device: device,
                  onTap: peer == null ? null : () => _openRealPeer(peer),
                ),
              );
            }),
          const SizedBox(height: 20),
          Text(
            'ข้อมูลตัวอย่าง',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'ข้อมูล DEMO ใช้ประกอบการนำเสนอ ไม่ใช่อุปกรณ์ที่ค้นพบจริง',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ...demoDevices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RelioDeviceCard(
                device: device,
                onTap: () => context.push('/chat/${device.id}'),
              ),
            ),
          ),
        ],
      ),
    );
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
