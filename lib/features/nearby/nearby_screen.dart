import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/relio_dependencies.dart';
import '../../core/nearby/nearby_service.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/permissions/permission_service.dart';
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
  bool _scanning = false;
  bool _loaded = false;
  List<RelioDevice> _devices = RelioMockData.devices;
  late final NearbyService _nearby;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _nearby = RelioDependencyScope.of(context).nearbyService;
    _nearby.addListener(_onNearbyChanged);
    RelioDependencyScope.of(
      context,
    ).repositories.nearbyDevices.listDevices().then((devices) {
      if (!mounted || devices.isEmpty) return;
      setState(() {
        _devices = devices
            .map(
              (device) => RelioDevice(
                id: device.deviceId,
                name: device.displayName,
                status: device.status,
                distanceMetersApprox: device.approxDistance,
                signalQuality: device.signalQuality ?? 0,
              ),
            )
            .toList(growable: false);
      });
    });
  }

  @override
  void dispose() {
    _nearby.removeListener(_onNearbyChanged);
    super.dispose();
  }

  void _onNearbyChanged() {
    if (!mounted || _nearby.discoveredPeers.isEmpty) return;
    final next = [..._devices];
    for (final peer in _nearby.discoveredPeers) {
      final deviceId = peer.deviceId ?? peer.endpointId;
      final index = next.indexWhere((device) => device.id == deviceId);
      final live = RelioDevice(
        id: deviceId,
        name: peer.name,
        status: _nearby.peerStatuses[deviceId] ?? DeviceStatus.normal,
        signalQuality: 0,
        isConnected:
            _nearby.peerStates[peer.endpointId] ==
            NearbyConnectionState.connected,
      );
      if (index == -1) {
        next.add(live);
      } else {
        next[index] = live;
      }
    }
    setState(() => _devices = next);
  }

  List<RelioDevice> get filtered {
    if (_filter == NearbyFilter.all) return _devices;
    if (_filter == NearbyFilter.normal) {
      return _devices
          .where(
            (device) =>
                device.status == DeviceStatus.normal ||
                device.status == DeviceStatus.offline,
          )
          .toList();
    }
    return _devices
        .where((device) => device.status.name == _filter.name)
        .toList();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final nearby = RelioDependencyScope.of(context).nearbyService;
    await nearby.startDiscovery();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await nearby.stopDiscovery();
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RelioAppBar(
        title: 'อุปกรณ์ใกล้เคียง',
        subtitle: 'อุปกรณ์จากฐานข้อมูลและ Nearby',
        actions: [
          IconButton(
            onPressed: _scan,
            tooltip: 'สแกน',
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
          RelioSpacing.lg,
          4,
          RelioSpacing.lg,
          12,
        ),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: NearbyFilter.values
                    .map(
                      (filter) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_filterLabel(filter)),
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
            const SizedBox(height: 8),
            FutureBuilder<NearbyPermissionSnapshot>(
              future: RelioDependencyScope.of(
                context,
              ).permissionService.readNearbyPermissions(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.allGranted) {
                  return const SizedBox.shrink();
                }
                return Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('ต้องอนุญาตอุปกรณ์ใกล้เคียง'),
                    subtitle: const Text(
                      'เปิดสิทธิ์ Bluetooth / Wi-Fi เพื่อค้นหา peer',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        await RelioDependencyScope.of(
                          context,
                        ).permissionService.requestNearbyPermissions();
                        if (mounted) setState(() {});
                      },
                      child: const Text('อนุญาต'),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _scanning
                  ? const _ScanningState()
                  : filtered.isEmpty
                  ? RelioEmptyState(
                      icon: Icons.radar_outlined,
                      title: 'ยังไม่พบอุปกรณ์ใกล้เคียง',
                      subtitle: 'ตรวจสอบว่า Bluetooth และ Wi-Fi เปิดอยู่',
                      action: FilledButton(
                        onPressed: _scan,
                        child: const Text('ค้นหาอีกครั้ง'),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => RelioDeviceCard(
                            device: filtered[index],
                            onTap: () =>
                                context.push('/chat/${filtered[index].id}'),
                          ),
                        );
                      },
                    ),
            ),
            if (!_scanning && filtered.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('สแกนหาอุปกรณ์ใกล้เคียง'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _filterLabel(NearbyFilter filter) => switch (filter) {
    NearbyFilter.all => 'ทั้งหมด (${_devices.length})',
    NearbyFilter.sos =>
      'SOS (${_devices.where((device) => device.status == DeviceStatus.sos).length})',
    NearbyFilter.rescue =>
      'Rescue (${_devices.where((device) => device.status == DeviceStatus.rescue).length})',
    NearbyFilter.normal =>
      'ปกติ (${_devices.where((device) => device.status == DeviceStatus.normal || device.status == DeviceStatus.offline).length})',
  };

  Color _filterColor(NearbyFilter filter) => switch (filter) {
    NearbyFilter.sos => RelioColors.sos,
    NearbyFilter.rescue => RelioColors.rescue,
    _ => RelioColors.primary,
  };
}

class _ScanningState extends StatelessWidget {
  const _ScanningState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 120,
            height: 120,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text(
            'กำลังค้นหาอุปกรณ์ใกล้เคียง...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          Text('โปรดรอสักครู่', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
