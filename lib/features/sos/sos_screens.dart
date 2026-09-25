import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/relio_dependencies.dart';
import '../../core/domain/relio_entities.dart';
import '../../shared/widgets/relio_widgets.dart';

class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> {
  final _message = TextEditingController(
    text: 'ต้องการความช่วยเหลือ บาดเจ็บที่ขา',
  );

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _openSOS() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('คุณต้องการเปิดโหมด SOS หรือไม่?'),
        content: const Text(
          'อุปกรณ์ RELIO ใกล้เคียงจะเห็นสถานะ SOS ของคุณและตำแหน่งล่าสุด',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RelioColors.sos),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('เปิด SOS'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final dependencies = RelioDependencyScope.of(context);
      final location = await dependencies.locationService.getCurrentOrLastKnown(
        timeout: const Duration(seconds: 5),
      );
      await dependencies.repositories.sos.createAndActivate(
        ownerDeviceId: await dependencies.identity.getDeviceId(),
        ownerUserId: 'minnie',
        message: _message.text.trim(),
        latitude: location.location?.latitude,
        longitude: location.location?.longitude,
        locationAccuracy: location.location?.accuracyMeters,
        locationCapturedAt: location.location?.capturedAt,
      );
      await dependencies.nearbyService.propagateCurrentStatus();
      if (mounted) context.go('/sos/active');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RelioAppBar(title: 'โหมด SOS', onBack: () => context.go('/home')),
      body: SingleChildScrollView(
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
                  color: RelioColors.sos.withValues(alpha: 0.08),
                  child: const ListTile(
                    leading: Icon(
                      Icons.warning_amber_rounded,
                      color: RelioColors.sos,
                    ),
                    title: Text(
                      'ใช้เฉพาะกรณีฉุกเฉินเท่านั้น',
                      style: TextStyle(
                        color: RelioColors.sosStrong,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'สัญญาณ SOS จะถูกส่งไปยังอุปกรณ์ RELIO ทั้งหมดในระยะสัญญาณ',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<RelioSosEvent?>(
                  future: RelioDependencyScope.of(
                    context,
                  ).repositories.sos.readActive(),
                  builder: (context, snapshot) {
                    final event = snapshot.data;
                    return RelioLocationCard(
                      latitude: event?.latitude,
                      longitude: event?.longitude,
                      updatedAt: event?.updatedAt,
                      accuracyMeters: event?.locationAccuracy,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'ข้อความฉุกเฉิน (ไม่บังคับ)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _message,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'บอกข้อมูลที่จำเป็นให้ผู้ช่วยเหลือทราบ',
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.radar_rounded,
                      color: RelioColors.primary,
                    ),
                    title: const Text('จะส่งถึง'),
                    subtitle: const Text(
                      'อุปกรณ์ RELIO ทั้งหมด 5 เครื่องที่อยู่ในระยะ รวมถึงทีมกู้ภัย A',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: RelioColors.sos,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _openSOS,
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('เปิดโหมด SOS'),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/sos/received'),
                    child: const Text('ดูตัวอย่าง SOS ใกล้คุณ'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SOSActiveScreen extends StatefulWidget {
  const SOSActiveScreen({super.key});

  @override
  State<SOSActiveScreen> createState() => _SOSActiveScreenState();
}

class _SOSActiveScreenState extends State<SOSActiveScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ต้องการปิดโหมด SOS หรือไม่?'),
        content: const Text('การแจ้งเตือนจะหยุดลงและสถานะของคุณจะกลับเป็นปกติ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('กลับ'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RelioColors.sos),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ปิด SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final dependencies = RelioDependencyScope.of(context);
    final deviceId = await dependencies.identity.getDeviceId();
    final active = await dependencies.repositories.sos.readActive(
      ownerDeviceId: deviceId,
    );
    if (active != null) {
      await dependencies.repositories.sos.deactivate(active.id);
      final cleared = await dependencies.repositories.sos.getById(active.id);
      if (cleared != null) {
        await dependencies.nearbyService.sendSos(cleared);
      }
      await dependencies.nearbyService.propagateCurrentStatus();
    }
    if (!mounted) return;
    context.go('/sos');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: RelioAppBar(
        title: 'SOS ACTIVE',
        onBack: _stop,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              label: const Text('ACTIVE'),
              backgroundColor: RelioColors.sos.withValues(alpha: 0.12),
              labelStyle: const TextStyle(
                color: RelioColors.sos,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
              children: [
                Text(
                  'กำลังขอความช่วยเหลือ',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: RelioColors.sosStrong,
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) => Container(
                    width: 210 + (_pulse.value * 12),
                    height: 210 + (_pulse.value * 12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: RelioColors.sos.withValues(alpha: 0.10),
                      border: Border.all(
                        color: RelioColors.sos.withValues(alpha: 0.3),
                        width: 16,
                      ),
                    ),
                    child: child,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(25),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: RelioColors.sos,
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.campaign_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                          SizedBox(height: 5),
                          Text(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 30,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  child: const ListTile(
                    leading: Icon(
                      Icons.check_circle_rounded,
                      color: RelioColors.success,
                    ),
                    title: Text('ส่งถึงอุปกรณ์ใกล้เคียงแล้ว'),
                    subtitle: Text('5 เครื่อง • รวมถึงทีมกู้ภัย A'),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<RelioSosEvent?>(
                  future: RelioDependencyScope.of(
                    context,
                  ).repositories.sos.readActive(),
                  builder: (context, snapshot) {
                    final event = snapshot.data;
                    return RelioLocationCard(
                      latitude: event?.latitude,
                      longitude: event?.longitude,
                      updatedAt: event?.updatedAt,
                      accuracyMeters: event?.locationAccuracy,
                    );
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.message_outlined,
                      color: RelioColors.sos,
                    ),
                    title: const Text('ข้อความฉุกเฉิน'),
                    subtitle: const Text('ต้องการความช่วยเหลือ บาดเจ็บที่ขา'),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: RelioColors.sos,
                      side: const BorderSide(color: RelioColors.sos),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _stop,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('ปิดโหมด SOS'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SOSReceivedScreen extends StatelessWidget {
  const SOSReceivedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RelioAppBar(title: 'SOS ใกล้คุณ', onBack: () => context.pop()),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(RelioSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Card(
                  color: RelioColors.sos.withValues(alpha: 0.08),
                  child: const Padding(
                    padding: EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_rounded,
                          color: RelioColors.sos,
                          size: 36,
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'สมชาย ต้องการความช่วยเหลือ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text('อยู่ใกล้คุณ • ≈ 120 ม.'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const RelioLocationCard(title: 'ตำแหน่งของผู้ส่ง SOS'),
                const SizedBox(height: 14),
                const Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.message_outlined,
                      color: RelioColors.sos,
                    ),
                    title: Text('ข้อความฉุกเฉิน'),
                    subtitle: Text('บาดเจ็บที่ขา ต้องการความช่วยเหลือ'),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => context.push('/chat/somchai'),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('เปิดแชท'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('แผนที่เป็น prototype ใน v0.1'),
                              ),
                            ),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('ดูตำแหน่ง'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
