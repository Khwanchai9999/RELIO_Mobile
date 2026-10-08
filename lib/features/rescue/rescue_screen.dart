import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/relio_dependencies.dart';
import '../../data/models/prototype_models.dart';
import '../../shared/widgets/relio_widgets.dart';

class RescueScreen extends StatefulWidget {
  const RescueScreen({super.key});

  @override
  State<RescueScreen> createState() => _RescueScreenState();
}

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
      setState(() => _active = true);
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
                text: 'ตำแหน่งของคุณจะถูกแชร์กับผู้ที่ส่ง SOS ในระยะ',
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

class _ActiveRescue extends StatelessWidget {
  const _ActiveRescue({required this.onDeactivate});

  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final nearby = RelioDependencyScope.of(context).nearbyService;
    return AnimatedBuilder(
      animation: nearby,
      builder: (context, _) {
        final cases = nearby.discoveredPeers
            .where(
              (peer) =>
                  peer.deviceId != null &&
                  nearby.peerStatuses[peer.deviceId] == DeviceStatus.sos,
            )
            .toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            RelioSpacing.lg,
            16,
            RelioSpacing.lg,
            24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: RelioColors.rescue.withValues(alpha: 0.08),
                    child: const ListTile(
                      leading: Icon(
                        Icons.shield_rounded,
                        color: RelioColors.rescue,
                      ),
                      title: Text(
                        'RESCUE ACTIVE',
                        style: TextStyle(
                          color: RelioColors.rescue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text('กำลังแสดงสถานะหน่วยกู้ภัย'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SOS จากอุปกรณ์จริง ${cases.length} เครื่อง',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  if (cases.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.radar_outlined),
                        title: Text('ยังไม่ได้รับ SOS จาก peer จริง'),
                        subtitle: Text(
                          'รายการจะปรากฏเมื่อได้รับ SOS packet ผ่าน Nearby',
                        ),
                      ),
                    ),
                  ...cases.map((peer) {
                    final deviceId = peer.deviceId!;
                    final connected = nearby.isDeviceConnected(deviceId);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        color: RelioColors.sos.withValues(alpha: 0.08),
                        child: ListTile(
                          leading: const Icon(
                            Icons.warning_amber_rounded,
                            color: RelioColors.sos,
                          ),
                          title: Text(peer.name),
                          subtitle: Text(
                            'REAL • SOS • ${connected ? 'เชื่อมต่อแล้ว' : 'ขาดการเชื่อมต่อ'}',
                          ),
                          trailing: const Icon(Icons.chat_bubble_outline),
                          onTap: () => context.push('/chat/$deviceId'),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onDeactivate,
                      child: const Text('ปิดโหมดกู้ภัย'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

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
