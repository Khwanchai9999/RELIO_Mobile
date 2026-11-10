// หน้าประวัติ SOS แบบ local-only พร้อมการซ่อนรายการที่ไม่ไปยกเลิกเหตุการณ์ปฏิบัติการ
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/location/nearby_map_calculations.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย SOSHistory Screen
class SOSHistoryScreen extends StatefulWidget {
  const SOSHistoryScreen({super.key});

  @override
  State<SOSHistoryScreen> createState() => _SOSHistoryScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (SOSHistory Screen State)
class _SOSHistoryScreenState extends State<SOSHistoryScreen> {
  RelioDependencies? _dependencies;
  Future<List<RelioSosHistoryEntry>>? _history;
  StreamSubscription<Object?>? _ownerSubscription;
  int _ownerGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (identical(_dependencies, dependencies)) return;
    _dependencies = dependencies;
    final owners = dependencies.repositories.ownerContext;
    _ownerGeneration = owners.capture().generation;
    _history = dependencies.repositories.sos.listHistory();
    _ownerSubscription?.cancel();
    _ownerSubscription = owners.changes.listen((_) {
      if (!mounted || !identical(_dependencies, dependencies)) return;
      setState(() {
        _ownerGeneration = owners.capture().generation;
        _history = dependencies.repositories.sos.listHistory();
      });
    });
  }

  @override
  void dispose() {
    _ownerSubscription?.cancel();
    super.dispose();
  }

  void _reload() {
    final dependencies = _dependencies;
    if (dependencies == null) return;
    setState(() => _history = dependencies.repositories.sos.listHistory());
  }

  // ยืนยันก่อนซ่อนประวัติของผู้ใช้ โดยไม่ใช้การลบประวัติเพื่อยกเลิก SOS ที่กำลังทำงาน
  Future<void> _deleteAll() async {
    final confirmed = await _confirmDelete(
      context,
      title: 'ลบประวัติ SOS ทั้งหมดหรือไม่?',
      message:
          'รายการที่ลบจะหายจากประวัติในบัญชีนี้ แต่ไม่ปิด SOS ที่กำลังทำงาน',
    );
    if (confirmed != true || !mounted) return;
    await _dependencies!.repositories.sos.hideAllHistory();
    if (!mounted) return;
    _reload();
  }

  Future<void> _deleteOne(RelioSosHistoryEntry entry) async {
    final confirmed = await _confirmDelete(
      context,
      title: 'ลบประวัติ SOS นี้หรือไม่?',
      message: 'การลบประวัติจะไม่ปิดคำขอ SOS ที่กำลังทำงาน',
    );
    if (confirmed != true || !mounted) return;
    await _dependencies!.repositories.sos.hideHistory(entry.event.id);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = RelioDependencyScope.of(context);
    return Scaffold(
      appBar: RelioAppBar(
        title: 'ประวัติ SOS',
        onBack: () => context.pop(),
        actions: [
          IconButton(
            tooltip: 'ลบประวัติทั้งหมด',
            onPressed: _deleteAll,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<RelioSosHistoryEntry>>(
        key: ValueKey(_ownerGeneration),
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? const <RelioSosHistoryEntry>[];
          if (entries.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _history;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 100),
                  Icon(
                    Icons.history_rounded,
                    size: 44,
                    color: RelioColors.muted,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'ยังไม่มีประวัติ SOS',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'คำขอที่ได้รับผ่าน Nearby จะถูกเก็บไว้ดูได้เมื่อออฟไลน์',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _history;
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final event = entry.event;
                final connected = dependencies.nearbyService.isDeviceConnected(
                  event.ownerDeviceId,
                );
                final hasLocation = NearbyMapCalculations.isValidPoint(
                  event.latitude,
                  event.longitude,
                );
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    onTap: () => context.push('/sos/history/${event.id}'),
                    leading: CircleAvatar(
                      backgroundColor: RelioColors.sos.withValues(alpha: .1),
                      child: const Icon(
                        Icons.sos_rounded,
                        color: RelioColors.sosStrong,
                      ),
                    ),
                    title: Text(
                      entry.requesterDisplayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '${_formatTime(event.createdAt)}\n'
                        '${event.isActive ? 'สถานะล่าสุดที่รับ: SOS กำลังทำงาน' : 'สถานะล่าสุดที่รับ: สิ้นสุดแล้ว'}\n'
                        '${hasLocation ? 'มีตำแหน่งที่บันทึกล่าสุด' : 'ไม่มีตำแหน่งที่บันทึกไว้'}'
                        '${connected ? ' • เชื่อมต่อ Nearby' : ''}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'ลบประวัติรายการนี้',
                      onPressed: () => _deleteOne(entry),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย SOSHistory Detail Screen
class SOSHistoryDetailScreen extends StatefulWidget {
  const SOSHistoryDetailScreen({required this.eventId, super.key});

  final String eventId;

  @override
  State<SOSHistoryDetailScreen> createState() => _SOSHistoryDetailScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (SOSHistory Detail Screen State)
class _SOSHistoryDetailScreenState extends State<SOSHistoryDetailScreen> {
  Future<RelioSosHistoryEntry?>? _entry;
  RelioDependencies? _dependencies;
  StreamSubscription<Object?>? _ownerSubscription;
  int _ownerGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (identical(_dependencies, dependencies)) return;
    _dependencies = dependencies;
    final owners = dependencies.repositories.ownerContext;
    _ownerGeneration = owners.capture().generation;
    _entry = dependencies.repositories.sos.readHistory(widget.eventId);
    _ownerSubscription?.cancel();
    _ownerSubscription = owners.changes.listen((_) {
      if (!mounted || !identical(_dependencies, dependencies)) return;
      setState(() {
        _ownerGeneration = owners.capture().generation;
        _entry = dependencies.repositories.sos.readHistory(widget.eventId);
      });
    });
  }

  @override
  void dispose() {
    _ownerSubscription?.cancel();
    super.dispose();
  }

  Future<void> _delete() async {
    final confirmed = await _confirmDelete(
      context,
      title: 'ลบประวัติ SOS นี้หรือไม่?',
      message: 'การลบประวัติจะไม่ปิดคำขอ SOS ที่กำลังทำงาน',
    );
    if (confirmed != true || !mounted) return;
    await _dependencies!.repositories.sos.hideHistory(widget.eventId);
    if (mounted) context.go('/sos/history');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: RelioAppBar(
      title: 'รายละเอียดประวัติ SOS',
      onBack: () => context.pop(),
      actions: [
        IconButton(
          tooltip: 'ลบประวัติรายการนี้',
          onPressed: _delete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    ),
    body: FutureBuilder<RelioSosHistoryEntry?>(
      key: ValueKey(_ownerGeneration),
      future: _entry,
      builder: (context, snapshot) {
        final entry = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (entry == null) {
          return const Center(child: Text('ไม่พบประวัติ SOS นี้ในเครื่อง'));
        }
        final event = entry.event;
        final connected = _dependencies!.nearbyService.isDeviceConnected(
          event.ownerDeviceId,
        );
        final hasLocation = NearbyMapCalculations.isValidPoint(
          event.latitude,
          event.longitude,
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              color: RelioColors.rescue.withValues(alpha: .07),
              child: ListTile(
                leading: const Icon(
                  Icons.sos_rounded,
                  color: RelioColors.sosStrong,
                ),
                title: Text(
                  event.isActive
                      ? 'สถานะล่าสุดที่รับ: SOS กำลังทำงาน'
                      : 'สถานะล่าสุดที่รับ: สิ้นสุดแล้ว',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  connected
                      ? 'เชื่อมต่อ Nearby อยู่'
                      : 'สถานะนี้เป็นข้อมูลล่าสุดที่บันทึกไว้; การเชื่อมต่อปัจจุบันไม่ยืนยัน',
                ),
              ),
            ),
            const SizedBox(height: 12),
            _HistoryCard(
              title: 'ผู้ขอความช่วยเหลือ',
              icon: Icons.person_outline_rounded,
              child: Column(
                children: [
                  _HistoryLine(
                    label: 'ผู้ขอ',
                    value: entry.requesterDisplayName,
                  ),
                  _HistoryLine(
                    label: 'ข้อความ',
                    value: event.message?.trim().isNotEmpty == true
                        ? event.message!.trim()
                        : 'ไม่ได้ระบุข้อความ',
                  ),
                  _HistoryLine(
                    label: 'เวลาเริ่ม SOS',
                    value: _formatTime(event.createdAt),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _HistoryCard(
              title: 'ตำแหน่งที่บันทึกล่าสุด',
              icon: Icons.location_on_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    hasLocation
                        ? '${event.latitude!.toStringAsFixed(5)}, ${event.longitude!.toStringAsFixed(5)}'
                        : 'ไม่มีพิกัดที่บันทึกไว้',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (hasLocation && event.locationAccuracy != null)
                    Text(
                      'ความแม่นยำประมาณ ±${event.locationAccuracy!.round()} ม.',
                    ),
                  if (event.locationCapturedAt != null)
                    Text(
                      'อัปเดตเมื่อ ${_formatTime(event.locationCapturedAt!)}',
                    ),
                  const SizedBox(height: 5),
                  Text(
                    'ตำแหน่งนี้เป็นข้อมูลที่บันทึกจากคำขอ SOS และอาจไม่ใช่ตำแหน่งปัจจุบัน',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: !hasLocation
                  ? null
                  : () => context.go(
                      Uri(
                        path: '/nearby',
                        queryParameters: {
                          'target': event.ownerDeviceId,
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
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => context.push('/chat/${event.ownerDeviceId}'),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('เปิดแชท'),
            ),
          ],
        );
      },
    ),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (History Card)
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: RelioColors.rescue),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (History Line)
class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 108, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

Future<bool?> _confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('ลบประวัติ'),
      ),
    ],
  ),
);

String _formatTime(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}  ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
