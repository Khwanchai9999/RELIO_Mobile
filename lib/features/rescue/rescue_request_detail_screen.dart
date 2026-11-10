// หน้ารายละเอียดคำขอ Rescue ที่แสดงข้อมูลสถานะและการตอบสนองของคำขอหนึ่งรายการ
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/location/nearby_map_calculations.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย Rescue Request Detail Screen
class RescueRequestDetailScreen extends StatefulWidget {
  const RescueRequestDetailScreen({
    required this.deviceId,
    this.eventId,
    this.order = 1,
    super.key,
  });

  final String deviceId;
  final String? eventId;
  final int order;

  @override
  State<RescueRequestDetailScreen> createState() =>
      _RescueRequestDetailScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Rescue Request Detail Screen State)
class _RescueRequestDetailScreenState extends State<RescueRequestDetailScreen> {
  Future<RelioSosEvent?>? _eventFuture;
  RelioDependencies? _dependencies;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (!identical(_dependencies, dependencies)) {
      _dependencies = dependencies;
      _eventFuture = _readEvent(dependencies);
    }
  }

  // ตรวจว่า event เป็นของ device ที่เปิดดู เพื่อไม่แสดงคำขอ SOS ของเครื่องอื่นจาก ID ที่ไม่ตรงกัน
  Future<RelioSosEvent?> _readEvent(RelioDependencies dependencies) async {
    final id = widget.eventId;
    if (id == null) {
      return dependencies.repositories.sos.readActive(
        ownerDeviceId: widget.deviceId,
      );
    }
    final event = await dependencies.repositories.sos.getById(id);
    return event?.ownerDeviceId == widget.deviceId ? event : null;
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = RelioDependencyScope.of(context);
    final peer = dependencies.nearbyService.discoveredPeers
        .cast<NearbyPeer?>()
        .firstWhere(
          (item) => item?.deviceId == widget.deviceId,
          orElse: () => null,
        );
    final connected = dependencies.nearbyService.isDeviceConnected(
      widget.deviceId,
    );
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: RelioAppBar(
        title: 'รายละเอียดคำขอ SOS',
        onBack: () => context.go('/rescue'),
        actions: [
          IconButton(
            tooltip: 'ประวัติ SOS',
            onPressed: () => context.push('/sos/history'),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: FutureBuilder<RelioSosEvent?>(
        future: _eventFuture,
        builder: (context, snapshot) {
          final event = snapshot.data;
          final eventPending =
              widget.eventId != null &&
              snapshot.connectionState != ConnectionState.done;
          final exactEventUnavailable =
              widget.eventId != null &&
              (snapshot.hasError ||
                  (snapshot.connectionState == ConnectionState.done &&
                      event == null));
          final locationAvailable = NearbyMapCalculations.isValidPoint(
            event?.latitude,
            event?.longitude,
          );
          final name = peer?.name ?? 'อุปกรณ์ RELIO';
          final avatarPath = RelioDependencyScope.of(
            context,
          ).nearbyService.avatarPathFor(widget.deviceId);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      RelioColors.rescue.withValues(alpha: .16),
                      colors.surface,
                    ],
                  ),
                  border: Border.all(
                    color: RelioColors.rescue.withValues(alpha: .45),
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0x1AFF0000),
                      child: Icon(Icons.sos_rounded, color: RelioColors.sos),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eventPending
                                ? 'กำลังโหลดคำขอ SOS'
                                : exactEventUnavailable
                                ? 'ไม่พบคำขอ SOS นี้ในเครื่อง'
                                : event?.isActive == false
                                ? 'คำขอ SOS สิ้นสุดแล้ว'
                                : 'กำลังขอความช่วยเหลือ',
                            style: TextStyle(
                              color: RelioColors.sosStrong,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            eventPending
                                ? 'กำลังตรวจสอบข้อมูลเหตุ'
                                : exactEventUnavailable
                                ? 'ข้อมูลเหตุไม่พร้อมใช้งาน'
                                : connected
                                ? 'เชื่อมต่อ Nearby อยู่'
                                : 'ยืนยันสถานะล่าสุดไม่ได้',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'ลำดับ ${widget.order}',
                      style: TextStyle(
                        color: RelioColors.rescue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (!eventPending && !exactEventUnavailable)
                _DetailCard(
                  title: 'ผู้ขอความช่วยเหลือ',
                  icon: Icons.people_alt_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: RelioColors.rescue.withValues(
                              alpha: .12,
                            ),
                            foregroundImage: avatarPath == null
                                ? null
                                : FileImage(File(avatarPath)),
                            child: avatarPath == null
                                ? const Icon(
                                    Icons.person_outline,
                                    color: RelioColors.rescue,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const Chip(
                            label: Text('SOS'),
                            labelStyle: TextStyle(
                              color: RelioColors.sosStrong,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _InfoRow(
                        label: 'ข้อความ',
                        value: event?.message?.trim().isNotEmpty == true
                            ? event!.message!.trim()
                            : 'ไม่ได้ระบุข้อความ',
                      ),
                      _InfoRow(
                        label: 'เวลาเริ่ม',
                        value: event == null
                            ? 'ไม่มีข้อมูลเหตุในเครื่อง'
                            : _formatTime(event.createdAt),
                      ),
                    ],
                  ),
                ),
              if (!eventPending && !exactEventUnavailable)
                const SizedBox(height: 12),
              if (!eventPending && !exactEventUnavailable)
                _DetailCard(
                  title: 'ตำแหน่งจากคำขอ SOS',
                  icon: Icons.location_on_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(
                        label: 'พิกัดล่าสุดที่รับ',
                        value: locationAvailable
                            ? '${event!.latitude!.toStringAsFixed(5)}, ${event.longitude!.toStringAsFixed(5)}'
                            : 'ไม่มีพิกัดที่แชร์',
                      ),
                      if (locationAvailable && event!.locationAccuracy != null)
                        _InfoRow(
                          label: 'ความแม่นยำ',
                          value:
                              'ประมาณ ±${event.locationAccuracy!.round()} ม.',
                        ),
                      if (event?.locationCapturedAt != null)
                        _InfoRow(
                          label: 'อัปเดตตำแหน่ง',
                          value: _formatTime(event!.locationCapturedAt!),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        event?.locationCapturedAt == null
                            ? 'ตำแหน่งที่บันทึกไว้ อาจไม่ใช่ตำแหน่งปัจจุบัน'
                            : 'ตำแหน่งนี้เป็นข้อมูลล่าสุดที่รับเมื่อ ${_formatTime(event!.locationCapturedAt!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              if (eventPending)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (exactEventUnavailable)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'เหตุอาจสิ้นสุดหรือไม่มีข้อมูลที่ตรงกับอุปกรณ์นี้',
                  ),
                ),
              if (!eventPending && !exactEventUnavailable)
                const SizedBox(height: 18),
              if (!eventPending && !exactEventUnavailable)
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: !locationAvailable
                          ? null
                          : () => context.go(
                              Uri(
                                path: '/nearby',
                                queryParameters: {
                                  'target': widget.deviceId,
                                  'lat': event!.latitude!.toString(),
                                  'lon': event.longitude!.toString(),
                                  'historical': '1',
                                  if (event.locationCapturedAt != null)
                                    'capturedAt': event
                                        .locationCapturedAt!
                                        .millisecondsSinceEpoch
                                        .toString(),
                                  if (event.locationAccuracy != null)
                                    'accuracy': event.locationAccuracy!
                                        .toString(),
                                },
                              ).toString(),
                            ),
                      icon: const Icon(Icons.near_me_outlined),
                      label: Text(
                        locationAvailable ? 'นำทางไปยังตำแหน่ง' : 'ไม่มีพิกัด',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => context.push('/chat/${widget.deviceId}'),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('เปิดแชท'),
                    ),
                  ],
                ),
              if (!connected)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'สถานะอาจเปลี่ยนไปแล้วขณะอุปกรณ์ไม่ได้เชื่อมต่อ',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _formatTime(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}  ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Detail Card)
class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(color: RelioColors.rescue.withValues(alpha: .32)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: RelioColors.rescue),
              const SizedBox(width: 9),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: RelioColors.brandNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Info Row)
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 98,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
