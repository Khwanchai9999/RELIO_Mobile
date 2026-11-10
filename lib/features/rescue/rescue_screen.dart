// หน้าสถานะ Rescue และคำขอช่วยเหลือ โดยรักษาลำดับความสำคัญที่ต่ำกว่า SOS
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/relio_dependencies.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/emergency/emergency_runtime_service.dart';
import '../../core/location/nearby_map_calculations.dart';
import '../../shared/widgets/relio_widgets.dart';
import '../sos/sos_location_freshness.dart';

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Rescue Screen
class RescueScreen extends StatefulWidget {
  const RescueScreen({super.key});

  @override
  State<RescueScreen> createState() => _RescueScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Rescue Screen State)
class _RescueScreenState extends State<RescueScreen> {
  bool _active = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final settings = RelioDependencyScope.of(context).repositories.settings;
    settings.getBool('rescue_mode', defaultValue: false).then((value) {
      if (mounted) setState(() => _active = value);
    });
  }

  Future<void> _toggle() async {
    if (_active) {
      setState(() => _active = false);
      final dependencies = RelioDependencyScope.of(context);
      await dependencies.repositories.settings.setBool('rescue_mode', false);
      await dependencies.nearbyService.propagateCurrentStatus();
      final deviceId = await dependencies.identity.getDeviceId();
      final sos = await dependencies.repositories.sos.readActive(
        ownerDeviceId: deviceId,
      );
      if (sos != null) {
        unawaited(dependencies.startEmergencyRuntime(EmergencyMode.sos));
      } else {
        unawaited(dependencies.stopEmergencyRuntime());
      }
      return;
    }
    // ให้ผู้ใช้ยืนยันก่อนเผยสถานะ Rescue ให้ peer ใกล้เคียงเห็น
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เปิดโหมดหน่วยกู้ภัย?'),
        content: const Text(
          'ผู้ใช้ใกล้เคียงจะเห็นสถานะ Rescue ของคุณ และสามารถติดต่อขอความช่วยเหลือได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RelioColors.rescue),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('เปิดโหมดกู้ภัย'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final dependencies = RelioDependencyScope.of(context);
      await dependencies.repositories.settings.setBool('rescue_mode', true);
      await dependencies.nearbyService.propagateCurrentStatus();
      final deviceId = await dependencies.identity.getDeviceId();
      final sos = await dependencies.repositories.sos.readActive(
        ownerDeviceId: deviceId,
      );
      if (!mounted) return;
      setState(() => _active = true);
      final messenger = ScaffoldMessenger.of(context);
      unawaited(
        dependencies
            .startEmergencyRuntime(
              sos == null ? EmergencyMode.rescue : EmergencyMode.sos,
            )
            .then((runtimeStarted) {
              if (!runtimeStarted) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'เปิด Rescue แล้ว แต่เริ่ม foreground service ไม่สำเร็จ',
                    ),
                  ),
                );
              }
            }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RelioAppBar(
        title: 'โหมดหน่วยกู้ภัย',
        onBack: () => context.go('/home'),
      ),
      body: _active
          ? _ActiveRescue(onDeactivate: _toggle)
          : _InactiveRescue(onActivate: _toggle),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Inactive Rescue)
class _InactiveRescue extends StatelessWidget {
  const _InactiveRescue({required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        RelioSpacing.lg,
        30,
        RelioSpacing.lg,
        24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: RelioColors.rescue.withValues(alpha: 0.1),
                  border: Border.all(
                    color: RelioColors.rescue.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: RelioColors.rescue,
                  size: 54,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'โหมดหน่วยกู้ภัย',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'เมื่อเปิด ผู้ใช้ RELIO ใกล้เคียงจะเห็นคุณเป็นหน่วยกู้ภัย และสามารถขอความช่วยเหลือได้',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              const _RescueInfo(
                icon: Icons.radar_rounded,
                text: 'อุปกรณ์ใกล้เคียงจะเห็นสถานะ Rescue ของคุณ',
              ),
              const _RescueInfo(
                icon: Icons.location_on_outlined,
                text: 'คุณเลือกแชร์ตำแหน่งได้เมื่อจำเป็น',
              ),
              const _RescueInfo(
                icon: Icons.warning_amber_rounded,
                text: 'คุณจะได้รับแจ้งเตือนเมื่อมีสัญญาณ SOS ใกล้เคียง',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: RelioColors.rescue,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: onActivate,
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('เปิดโหมดหน่วยกู้ภัย'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Active Rescue)
class _ActiveRescue extends StatefulWidget {
  const _ActiveRescue({required this.onDeactivate});

  final VoidCallback onDeactivate;

  @override
  State<_ActiveRescue> createState() => _ActiveRescueState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Active Rescue State)
class _ActiveRescueState extends State<_ActiveRescue> {
  RelioDependencies? _dependencies;
  List<_RescueRequest> _requests = const [];
  bool _loading = true;
  String? _selectedEventId;
  Timer? _refreshTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (identical(_dependencies, dependencies)) return;
    _dependencies?.nearbyService.removeListener(_onNearbyChanged);
    _dependencies = dependencies;
    dependencies.nearbyService.addListener(_onNearbyChanged);
    unawaited(_refreshRequests());
  }

  void _onNearbyChanged() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) unawaited(_refreshRequests());
    });
  }

  Future<void> _refreshRequests() async {
    final dependencies = _dependencies;
    if (dependencies == null) return;
    try {
      final requests = await _loadRequests(dependencies);
      if (!mounted || !identical(_dependencies, dependencies)) return;
      setState(() {
        _requests = requests;
        _loading = false;
        if (!requests.any((item) => item.event.id == _selectedEventId)) {
          _selectedEventId = requests.firstOrNull?.event.id;
        }
      });
    } on Object catch (error) {
      dependencies.diagnostics.record(
        'sos',
        'rescue_request_refresh_failed',
        severity: 'warning',
        reason: error.runtimeType.toString(),
      );
      if (mounted && identical(_dependencies, dependencies)) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _dependencies?.nearbyService.removeListener(_onNearbyChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _requests.indexWhere(
      (item) => item.event.id == _selectedEventId,
    );
    final selected = selectedIndex < 0 ? null : _requests[selectedIndex];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        RelioSpacing.lg,
        12,
        RelioSpacing.lg,
        24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: RelioColors.rescue.withValues(alpha: 0.08),
                child: ListTile(
                  leading: const Icon(
                    Icons.shield_rounded,
                    color: RelioColors.rescue,
                  ),
                  title: const Text(
                    'RESCUE ACTIVE',
                    style: TextStyle(
                      color: RelioColors.rescue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: const Text('พร้อมรับคำขอ SOS จาก Nearby'),
                  trailing: Chip(label: Text('${_requests.length} คำขอ')),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: widget.onDeactivate,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('ปิดโหมดกู้ภัย'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: RelioColors.rescue,
                  side: const BorderSide(color: RelioColors.rescue),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'ผู้ขอความช่วยเหลือ',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: RelioColors.brandNavy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/sos/history'),
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('ประวัติ'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loading && _requests.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_requests.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Icon(
                          Icons.health_and_safety_outlined,
                          size: 40,
                          color: RelioColors.rescue,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'ยังไม่มีคำขอ SOS',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'เมื่อได้รับคำขอจากอุปกรณ์ใกล้เคียง รายการจะแสดงที่นี่',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                if (_requests.length > 1)
                  DropdownButtonFormField<String>(
                    key: ValueKey(_selectedEventId),
                    initialValue: _selectedEventId,
                    decoration: const InputDecoration(
                      labelText: 'เลือกคำขอ SOS',
                      prefixIcon: Icon(Icons.swap_vert_rounded),
                    ),
                    items: [
                      for (var index = 0; index < _requests.length; index++)
                        DropdownMenuItem(
                          value: _requests[index].event.id,
                          child: Text(
                            'ลำดับ ${index + 1} • ${_requests[index].name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) setState(() => _selectedEventId = id);
                    },
                  ),
                if (_requests.length > 1) const SizedBox(height: 10),
                if (selected != null)
                  _ActiveRescueRequestCard(
                    request: selected,
                    order: selectedIndex + 1,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<List<_RescueRequest>> _loadRequests(
    RelioDependencies dependencies,
  ) async {
    final selfId = await dependencies.identity.getDeviceId();
    final events = await dependencies.repositories.sos.listActive();
    final latestByDevice = <String, RelioSosEvent>{};
    for (final event in events) {
      if (event.ownerDeviceId == selfId) continue;
      final current = latestByDevice[event.ownerDeviceId];
      if (current == null || event.createdAt.isAfter(current.createdAt)) {
        latestByDevice[event.ownerDeviceId] = event;
      }
    }
    final devices = await dependencies.repositories.nearbyDevices.listDevices();
    final peers = dependencies.nearbyService.discoveredPeers;
    final requests = latestByDevice.values.map((event) {
      final peer = peers
          .where((item) => item.deviceId == event.ownerDeviceId)
          .firstOrNull;
      final device = devices
          .where((item) => item.deviceId == event.ownerDeviceId)
          .firstOrNull;
      return _RescueRequest(
        event: event,
        name: peer?.name ?? device?.displayName ?? 'อุปกรณ์ RELIO',
        connected: dependencies.nearbyService.isDeviceConnected(
          event.ownerDeviceId,
        ),
      );
    }).toList();
    requests.sort((a, b) {
      final byTime = b.event.createdAt.compareTo(a.event.createdAt);
      return byTime == 0
          ? a.event.ownerDeviceId.compareTo(b.event.ownerDeviceId)
          : byTime;
    });
    return requests;
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Rescue Request)
class _RescueRequest {
  const _RescueRequest({
    required this.event,
    required this.name,
    required this.connected,
  });
  final RelioSosEvent event;
  final String name;
  final bool connected;
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Active Rescue Request Card)
class _ActiveRescueRequestCard extends StatelessWidget {
  const _ActiveRescueRequestCard({required this.request, required this.order});

  final _RescueRequest request;
  final int order;

  @override
  Widget build(BuildContext context) {
    final event = request.event;
    final deviceId = event.ownerDeviceId;
    final hasLocation = NearbyMapCalculations.isValidPoint(
      event.latitude,
      event.longitude,
    );
    final avatarPath = RelioDependencyScope.of(
      context,
    ).nearbyService.avatarPathFor(deviceId);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: RelioColors.rescue.withValues(alpha: .42)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: RelioColors.rescue.withValues(alpha: .12),
                  foregroundImage: avatarPath == null
                      ? null
                      : FileImage(File(avatarPath)),
                  child: avatarPath == null
                      ? const Icon(
                          Icons.person_outline_rounded,
                          color: RelioColors.rescue,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    request.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: RelioColors.brandNavy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Chip(
                  label: Text(request.connected ? 'SOS' : 'SOS ล่าสุด'),
                  labelStyle: const TextStyle(
                    color: RelioColors.sosStrong,
                    fontWeight: FontWeight.w800,
                  ),
                  side: BorderSide.none,
                  backgroundColor: RelioColors.sos.withValues(alpha: .1),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              request.connected
                  ? 'เชื่อมต่อ Nearby • สถานะล่าสุดที่รับได้'
                  : 'สถานะ SOS ล่าสุดที่บันทึกไว้ อาจเปลี่ยนหลังขาดการเชื่อมต่อ',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: request.connected
                    ? RelioColors.rescueStrong
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.priority_high_rounded, size: 18),
                label: Text('ลำดับ $order'),
                visualDensity: VisualDensity.compact,
                backgroundColor: RelioColors.rescue.withValues(alpha: .1),
              ),
            ),
            const Divider(height: 18),
            _RescueInfoLine(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'ข้อความ',
              value: event.message?.trim().isNotEmpty == true
                  ? event.message!.trim()
                  : 'ไม่ได้ระบุข้อความ',
            ),
            const SizedBox(height: 8),
            _RescueInfoLine(
              icon: Icons.schedule_rounded,
              label: 'เริ่ม SOS',
              value: _formatRescueTime(event.createdAt),
            ),
            const SizedBox(height: 8),
            RelioLocationCard(
              title: 'ตำแหน่งจากคำขอ SOS',
              latitude: event.latitude,
              longitude: event.longitude,
              updatedAt: event.locationCapturedAt,
              accuracyMeters: event.locationAccuracy,
              freshnessLabel: sosLocationFreshnessLabel(event, DateTime.now()),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: !hasLocation
                  ? null
                  : () => context.go(
                      Uri(
                        path: '/nearby',
                        queryParameters: {
                          'target': deviceId,
                          'lat': event.latitude!.toString(),
                          'lon': event.longitude!.toString(),
                          'historical': '1',
                          if (event.locationCapturedAt != null)
                            'capturedAt': event
                                .locationCapturedAt!
                                .millisecondsSinceEpoch
                                .toString(),
                          if (event.locationAccuracy != null)
                            'accuracy': event.locationAccuracy!.toString(),
                        },
                      ).toString(),
                    ),
              icon: const Icon(Icons.near_me_outlined),
              label: const Text('นำทางไปยังตำแหน่ง'),
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: () => context.push('/chat/$deviceId'),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('เปิดแชท'),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RelioColors.rescue.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.health_and_safety_outlined,
                    color: RelioColors.rescue,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ข้อมูลฉุกเฉินที่เปิดเผย',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 4),
                        Text('ยังไม่มีข้อมูลฉุกเฉินที่ได้รับอนุญาตให้เปิดเผย'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Rescue Info Line)
class _RescueInfoLine extends StatelessWidget {
  const _RescueInfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: RelioColors.rescue, size: 19),
      const SizedBox(width: 8),
      SizedBox(
        width: 84,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      Expanded(child: Text(value)),
    ],
  );
}

String _formatRescueTime(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}  ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Rescue Info)
class _RescueInfo extends StatelessWidget {
  const _RescueInfo({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: RelioColors.rescue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: RelioColors.rescue, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(text),
            ),
          ),
        ],
      ),
    );
  }
}
