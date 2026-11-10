// หน้าส่ง SOS หน้าสถานะเหตุที่กำลังทำงาน และหน้ารับเหตุ SOS โดยแสดงสถานะอย่างชัดเจน
import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' show Point, min;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/theme/relio_colors.dart';
import '../../core/location/nearby_map_calculations.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/relio_dependencies.dart';
import '../../core/domain/relio_entities.dart';
import '../../core/emergency/emergency_runtime_service.dart';
import '../../data/models/prototype_models.dart';
import '../../shared/widgets/relio_widgets.dart';
import 'sos_location_freshness.dart';

// หน้าจอนี้เริ่มและแสดงสถานะ SOS โดยอาศัย Repository เป็นแหล่งข้อมูลหลัก
// การบันทึกเหตุฉุกเฉินในเครื่องแยกจากผล ACK ที่ได้รับจาก Nearby
class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});

  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (SOSScreen State)
class _SOSScreenState extends State<SOSScreen> {
  final _message = TextEditingController();
  bool _submitting = false;
  String? _activationError;
  RelioDependencies? _dependencies;
  Future<RelioSosEvent?>? _activeSosFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (identical(_dependencies, dependencies)) return;
    _dependencies = dependencies;
    _activeSosFuture = _readActiveSos(dependencies);
  }

  Future<RelioSosEvent?> _readActiveSos(RelioDependencies dependencies) async {
    final deviceId = await dependencies.identity.getDeviceId();
    return dependencies.repositories.sos.readActive(ownerDeviceId: deviceId);
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  // ล็อกการกดซ้ำระหว่างสร้างเหตุการณ์ เพื่อไม่ให้เกิด SOS ซ้อนจากการแตะหลายครั้ง
  Future<void> _openSOS() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _activationError = null;
    });
    try {
      final dependencies = _dependencies!;
      final ownerDeviceId = await dependencies.identity.getDeviceId();
      final alreadyActive = await dependencies.repositories.sos.readActive(
        ownerDeviceId: ownerDeviceId,
      );
      if (!mounted) return;
      if (alreadyActive != null) {
        final messenger = ScaffoldMessenger.of(context);
        unawaited(_startRuntimeInBackground(dependencies, messenger));
        context.go('/sos/active');
        return;
      }
      final event = await dependencies.repositories.sos.createAndActivate(
        ownerDeviceId: ownerDeviceId,
        ownerUserId: dependencies.authService.identity?.userId ?? '',
        message: _message.text.trim(),
      );
      // เริ่มขอตำแหน่งเสริมไว้คู่ขนานกับการส่งเหตุ SOS หลัก
      unawaited(_attachLocationWhenAvailable(dependencies, event.id));

      var nearbySendFailed = false;
      try {
        await dependencies.nearbyService.sendSos(event);
      } on Object {
        // สถานะ Active อ้างอิงการบันทึกในเครื่อง ไม่ใช่ผลรับ ACK จาก peer
        nearbySendFailed = true;
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go('/sos/active');
      unawaited(_startRuntimeInBackground(dependencies, messenger));
      if (nearbySendFailed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('เปิด SOS ในเครื่องแล้ว แต่ส่งไป Nearby ไม่สำเร็จ'),
            ),
          );
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _activationError = 'เปิดโหมด SOS ไม่สำเร็จ กรุณาลองอีกครั้ง',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _attachLocationWhenAvailable(
    RelioDependencies dependencies,
    String eventId,
  ) async {
    try {
      final result = await dependencies.locationService.getCurrentOrLastKnown(
        timeout: const Duration(seconds: 5),
      );
      final location = result.location;
      if (location == null) return;
      final updated = await dependencies.repositories.sos.updateActiveLocation(
        eventId: eventId,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyMeters: location.accuracyMeters,
        capturedAt: location.capturedAt,
      );
      if (updated != null) await dependencies.nearbyService.sendSos(updated);
    } on Object {
      // ตำแหน่งเป็นข้อมูลเสริม และไม่เปลี่ยนผลการเปิด SOS ในเครื่อง
    }
  }

  Future<void> _startRuntimeInBackground(
    RelioDependencies dependencies,
    ScaffoldMessengerState messenger,
  ) async {
    final started = await dependencies.startEmergencyRuntime(EmergencyMode.sos);
    if (!started) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'เปิด SOS ในเครื่องแล้ว แต่เริ่ม foreground service ไม่สำเร็จ',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RelioAppBar(
        title: 'SOS ใกล้คุณ',
        onBack: () => context.go('/home'),
      ),
      body: LayoutBuilder(
        builder: (context, viewport) {
          final compact = viewport.maxHeight < 680;
          final gap = compact ? 9.0 : 13.0;
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final narrowWidthFactor = viewport.maxWidth < 340 ? 1.35 : 1.0;
          final layoutScale = scale * narrowWidthFactor;
          final bodyHeight = (viewport.maxHeight - 16) * layoutScale;
          final minimumHeight = 500 * layoutScale;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(12, compact ? 6 : 10, 12, 10),
            child: SizedBox(
              height: bodyHeight > minimumHeight ? bodyHeight : minimumHeight,
              child: Column(
                children: [
                  FutureBuilder<RelioSosEvent?>(
                    future: _activeSosFuture,
                    builder: (context, snapshot) {
                      if (snapshot.data == null) {
                        return const SizedBox.shrink();
                      }
                      return Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => context.push('/sos/active'),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('จัดการ SOS ที่เปิดอยู่'),
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        compact ? 12 : 16,
                        16,
                        14,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFFFF0F0), Color(0xFFFFF8F8)],
                        ),
                        border: Border.all(
                          color: const Color(0xFFFFB9C0),
                          width: 1.4,
                        ),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: compact ? 39 : 46,
                            color: RelioColors.sos,
                          ),
                          SizedBox(height: compact ? 2 : 4),
                          FutureBuilder<RelioSosEvent?>(
                            future: _activeSosFuture,
                            builder: (context, snapshot) {
                              final isActive = snapshot.data != null;
                              return Column(
                                children: [
                                  Text(
                                    isActive
                                        ? 'เปิด SOS แล้ว'
                                        : 'สถานะ: ยังไม่ได้ส่ง SOS',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: RelioColors.sosStrong,
                                      fontSize:
                                          (compact ? 22 : 25) /
                                          scale.clamp(1, 1.25),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    isActive
                                        ? 'SOS ทำงานในเครื่องนี้'
                                        : 'กดปุ่มด้านล่างเมื่อต้องการขอความช่วยเหลือ',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          SizedBox(height: gap),
                          Row(
                            children: [
                              const Icon(
                                Icons.chat_bubble_rounded,
                                color: RelioColors.sos,
                                size: 24,
                              ),
                              const SizedBox(width: 9),
                              const Expanded(
                                child: Text(
                                  'ข้อความขอความช่วยเหลือ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Text(
                                '(ไม่บังคับ)',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          TextField(
                            controller: _message,
                            minLines: 2,
                            maxLines: 3,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              hintText:
                                  'เช่น บาดเจ็บ หลงทาง หรือต้องการความช่วยเหลือ...',
                              contentPadding: const EdgeInsets.all(13),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFFFCDD2),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFFFCDD2),
                                ),
                              ),
                            ),
                          ),
                          if (_activationError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _activationError!,
                              style: const TextStyle(
                                color: RelioColors.sosStrong,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          SizedBox(height: gap),
                          SizedBox(
                            width: double.infinity,
                            child: Material(
                              borderRadius: BorderRadius.circular(23),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: _submitting ? null : _openSOS,
                                child: Ink(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFEF111C),
                                        Color(0xFFBD0010),
                                      ],
                                    ),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: compact ? 12 : 15,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 56,
                                        height: 56,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: .17,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: _submitting
                                            ? const Padding(
                                                padding: EdgeInsets.all(17),
                                                child:
                                                    CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2.5,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.campaign_rounded,
                                                color: Colors.white,
                                                size: 38,
                                              ),
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _submitting
                                                  ? 'กำลังเตรียม SOS…'
                                                  : 'ส่งสัญญาณ SOS',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: compact ? 21 : 24,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const Text(
                                              'ขอความช่วยเหลือจากอุปกรณ์ใกล้เคียง',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: gap),
                  Row(
                    children: [
                      Expanded(
                        child: _SOSActionCard(
                          icon: Icons.chat_bubble_rounded,
                          title: 'คำขอ SOS',
                          color: RelioColors.sos,
                          onTap: () => context.push('/sos/received'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SOSActionCard(
                          icon: Icons.health_and_safety_rounded,
                          title: 'โหมดกู้ภัย',
                          color: RelioColors.info,
                          onTap: () => context.push('/rescue'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (SOSAction Card)
class _SOSActionCard extends StatelessWidget {
  const _SOSActionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: .07),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 7),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

// แสดงเหตุการณ์ SOS ที่กำลังทำงานและเปิดทางให้ผู้ใช้จัดการวงจรเหตุการณ์
class SOSActiveScreen extends StatefulWidget {
  const SOSActiveScreen({super.key});

  @override
  State<SOSActiveScreen> createState() => _SOSActiveScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (SOSActive Screen State)
class _SOSActiveScreenState extends State<SOSActiveScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Future<RelioSosEvent?>? _activeFuture;
  RelioDependencies? _dependencies;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2700),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (!identical(_dependencies, dependencies)) {
      _dependencies = dependencies;
      _activeFuture = _readActive(dependencies);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  Future<RelioSosEvent?> _readActive(RelioDependencies dependencies) async {
    final deviceId = await dependencies.identity.getDeviceId();
    return dependencies.repositories.sos.readActive(ownerDeviceId: deviceId);
  }

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
    }
    final rescueEnabled = await dependencies.repositories.settings.getBool(
      'rescue_mode',
      defaultValue: false,
    );
    if (rescueEnabled) {
      unawaited(dependencies.startEmergencyRuntime(EmergencyMode.rescue));
    } else {
      unawaited(dependencies.stopEmergencyRuntime());
    }
    if (!mounted) return;
    context.go('/sos');
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = RelioDependencyScope.of(context);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFFF3F3),
      appBar: RelioAppBar(title: 'SOS ACTIVE', onBack: _stop),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 620;
          final diameter = min(
            constraints.maxWidth - 36,
            compact ? 170.0 : 208.0,
          );
          final gap = compact ? 6.0 : 9.0;
          return FutureBuilder<RelioSosEvent?>(
            future: _activeFuture,
            builder: (context, snapshot) {
              final event = snapshot.data;
              final validLocation = NearbyMapCalculations.isValidPoint(
                event?.latitude,
                event?.longitude,
              );
              final location = validLocation
                  ? LocationData(
                      latitude: event!.latitude!,
                      longitude: event.longitude!,
                      accuracyMeters: event.locationAccuracy,
                      capturedAt: event.locationCapturedAt ?? event.createdAt,
                      source: 'sos',
                    )
                  : null;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(14, compact ? 4 : 8, 14, 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 16,
                  ),
                  child: IntrinsicHeight(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 650),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'กำลังขอความช่วยเหลือ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: RelioColors.sosStrong,
                                fontSize: compact ? 20 : 23,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: gap),
                            SizedBox(
                              width: diameter,
                              height: diameter,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (!reducedMotion)
                                    AnimatedBuilder(
                                      animation: _pulse,
                                      builder: (context, _) => CustomPaint(
                                        size: Size.square(diameter),
                                        painter: _SosPulsePainter(_pulse.value),
                                      ),
                                    )
                                  else
                                    CustomPaint(
                                      size: Size.square(diameter),
                                      painter: const _SosPulsePainter(0.35),
                                    ),
                                  Container(
                                    width: diameter * .64,
                                    height: diameter * .64,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF20E1B),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.campaign_rounded,
                                            color: Colors.white,
                                            size: 39,
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'SOS',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 31,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: gap),
                            SizedBox(
                              width: min(constraints.maxWidth, 330),
                              child: OutlinedButton.icon(
                                onPressed: _stop,
                                icon: const Icon(Icons.stop_circle_outlined),
                                label: const Text('ปิดโหมด SOS'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: RelioColors.sosStrong,
                                  side: const BorderSide(
                                    color: RelioColors.sosStrong,
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: gap),
                            AnimatedBuilder(
                              animation: dependencies.nearbyService,
                              builder: (context, _) {
                                final count = dependencies
                                    .nearbyService
                                    .connectedPeerCount;
                                return _ActiveInfoCard(
                                  icon: Icons.cell_tower_rounded,
                                  title: 'เปิด SOS แล้ว',
                                  subtitle: count == 0
                                      ? 'ยังไม่มีอุปกรณ์เชื่อมต่อ'
                                      : 'เชื่อมต่ออุปกรณ์ใกล้เคียง $count เครื่อง',
                                );
                              },
                            ),
                            SizedBox(height: gap),
                            _ActiveInfoCard(
                              icon: Icons.location_on_rounded,
                              title: 'ตำแหน่งล่าสุด',
                              subtitle: validLocation
                                  ? '${event!.latitude!.toStringAsFixed(5)}, ${event.longitude!.toStringAsFixed(5)}\n${event.locationAccuracy == null ? '' : '±${event.locationAccuracy!.round()} ม.  •  '}${sosLocationFreshnessLabel(event, DateTime.now())}'
                                  : 'ยังไม่มีพิกัดที่บันทึกไว้',
                              maxSubtitleLines: 3,
                              onTap: () => _showMapPreview(location),
                            ),
                            SizedBox(height: gap),
                            _ActiveInfoCard(
                              icon: Icons.message_outlined,
                              title: 'ข้อความฉุกเฉิน',
                              subtitle:
                                  event?.message?.trim().isNotEmpty == true
                                  ? event!.message!.trim()
                                  : 'ไม่ได้ระบุข้อความ',
                              onTap: event?.message?.trim().isNotEmpty == true
                                  ? () => _showFullMessage(
                                      context,
                                      event!.message!.trim(),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showMapPreview(LocationData? location) async {
    if (location == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: const Text('ตำแหน่งล่าสุด'),
                leading: IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(child: _SOSMapPreview(location: location)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showFullMessage(BuildContext context, String message) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ข้อความฉุกเฉิน'),
          content: SingleChildScrollView(child: SelectableText(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Active Info Card)
class _ActiveInfoCard extends StatelessWidget {
  const _ActiveInfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.maxSubtitleLines = 2,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final int maxSubtitleLines;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .88),
    borderRadius: BorderRadius.circular(19),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFFFCDD2)),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          children: [
            Icon(icon, color: RelioColors.sos, size: 25),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: maxSubtitleLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                color: RelioColors.secondaryText,
              ),
          ],
        ),
      ),
    ),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Sos Pulse Painter)
class _SosPulsePainter extends CustomPainter {
  const _SosPulsePainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide * .48;
    for (var ring = 0; ring < 3; ring++) {
      final phase = (progress + ring / 3) % 1;
      final radius = maxRadius * (.48 + phase * .5);
      final opacity = (1 - phase) * .22;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 - phase * 4
        ..color = RelioColors.sos.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SosPulsePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// องค์ประกอบหลักของโมดูลนี้ รับผิดชอบข้อมูลหรือส่วนติดต่อที่ระบุโดย SOSReceived Screen
class SOSReceivedScreen extends StatefulWidget {
  const SOSReceivedScreen({super.key});

  @override
  State<SOSReceivedScreen> createState() => _SOSReceivedScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (SOSReceived Screen State)
class _SOSReceivedScreenState extends State<SOSReceivedScreen> {
  RelioDependencies? _dependencies;
  List<_ReceivedSosRequest> _requests = const [];
  bool _loading = true;
  int _refreshGeneration = 0;
  Timer? _refreshTimer;
  final Stopwatch _screenClock = Stopwatch()..start();

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
    final dependencies = _dependencies;
    if (dependencies == null) return;
    _refreshGeneration++;
    dependencies.diagnostics.record(
      'sos',
      'sos_detail_state_changed',
      fields: {
        'screen': 'received',
        'elapsedSinceOpenMs': _screenClock.elapsedMilliseconds,
      },
    );
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) unawaited(_refreshRequests());
    });
  }

  Future<void> _refreshRequests() async {
    final dependencies = _dependencies;
    if (dependencies == null) return;
    final generation = ++_refreshGeneration;
    final nearby = dependencies.nearbyService;
    final peers = nearby.discoveredPeers
        .where(
          (peer) =>
              peer.deviceId != null &&
              nearby.peerStatuses[peer.deviceId] == DeviceStatus.sos,
        )
        .toList(growable: false);
    final refreshClock = Stopwatch()..start();
    try {
      final requests = await _loadRequests(dependencies, peers);
      if (!mounted ||
          !identical(_dependencies, dependencies) ||
          generation != _refreshGeneration) {
        return;
      }
      dependencies.diagnostics.record(
        'sos',
        'sos_detail_refresh_completed',
        fields: {
          'screen': 'received',
          'durationMs': refreshClock.elapsedMilliseconds,
          'requestCount': requests.length,
        },
      );
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } on Object catch (error) {
      dependencies.diagnostics.record(
        'sos',
        'sos_detail_refresh_failed',
        severity: 'warning',
        reason: error.runtimeType.toString(),
        fields: {'screen': 'received'},
      );
      if (mounted &&
          identical(_dependencies, dependencies) &&
          generation == _refreshGeneration) {
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

  Future<List<_ReceivedSosRequest>> _loadRequests(
    RelioDependencies dependencies,
    List<NearbyPeer> peers,
  ) async {
    final repository = dependencies.repositories.sos;
    final requests = await Future.wait(
      peers.map((peer) async {
        final deviceId = peer.deviceId!;
        final event = await repository.readActive(ownerDeviceId: deviceId);
        return _ReceivedSosRequest(peer: peer, event: event);
      }),
    );
    requests.sort((left, right) {
      final leftAt = left.event?.createdAt;
      final rightAt = right.event?.createdAt;
      if (leftAt == null && rightAt == null) {
        return left.peer.deviceId!.compareTo(right.peer.deviceId!);
      }
      if (leftAt == null) return 1;
      if (rightAt == null) return -1;
      final byTime = rightAt.compareTo(leftAt);
      return byTime == 0
          ? left.peer.deviceId!.compareTo(right.peer.deviceId!)
          : byTime;
    });
    return requests;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RelioAppBar(
        title: 'รายละเอียดคำขอ SOS',
        onBack: () => context.pop(),
        actions: [
          IconButton(
            tooltip: 'ประวัติ SOS',
            onPressed: () => context.push('/sos/history'),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          _RescueStatusBanner(hasRequests: _requests.isNotEmpty),
          const SizedBox(height: 14),
          if (_loading && _requests.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_requests.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Column(
                  children: [
                    Icon(
                      Icons.radar_rounded,
                      size: 40,
                      color: RelioColors.rescue,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'ยังไม่มีคำขอ SOS ที่กำลังทำงาน',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'คำขอจากอุปกรณ์ใกล้เคียงจะแสดงเมื่อได้รับสถานะจริงผ่าน Nearby',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'ผู้ขอความช่วยเหลือ',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: RelioColors.brandNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < _requests.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ReceivedSosCard(
                  request: _requests[index],
                  order: index + 1,
                  connected: _dependencies!.nearbyService.isDeviceConnected(
                    _requests[index].peer.deviceId!,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Received Sos Request)
class _ReceivedSosRequest {
  const _ReceivedSosRequest({required this.peer, required this.event});

  final NearbyPeer peer;
  final RelioSosEvent? event;
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Rescue Status Banner)
class _RescueStatusBanner extends StatelessWidget {
  const _RescueStatusBanner({required this.hasRequests});

  final bool hasRequests;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: RelioColors.rescue.withValues(alpha: 0.08),
      border: Border.all(color: RelioColors.rescue.withValues(alpha: 0.55)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: RelioColors.rescue.withValues(alpha: 0.22),
            ),
          ),
          child: const Icon(
            Icons.health_and_safety_rounded,
            color: RelioColors.sos,
            size: 31,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasRequests ? 'คำขอ SOS ที่รับมา' : 'โหมดกู้ภัยพร้อมใช้งาน',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: RelioColors.sosStrong,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              const Text('แสดงสถานะล่าสุดที่ได้รับผ่าน Nearby'),
            ],
          ),
        ),
      ],
    ),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Received Sos Card)
class _ReceivedSosCard extends StatelessWidget {
  const _ReceivedSosCard({
    required this.request,
    required this.order,
    required this.connected,
  });

  final _ReceivedSosRequest request;
  final int order;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final peer = request.peer;
    final event = request.event;
    final deviceId = peer.deviceId!;
    final hasLocation = NearbyMapCalculations.isValidPoint(
      event?.latitude,
      event?.longitude,
    );
    final avatarPath = RelioDependencyScope.of(
      context,
    ).nearbyService.avatarPathFor(deviceId);
    final border = RelioColors.rescue.withValues(alpha: 0.48);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: border, width: 1.4),
        borderRadius: BorderRadius.circular(21),
        boxShadow: [
          BoxShadow(
            color: RelioColors.rescue.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: RelioColors.rescue.withValues(alpha: 0.12),
                  foregroundImage: avatarPath == null
                      ? null
                      : FileImage(File(avatarPath)),
                  child: avatarPath == null
                      ? const Icon(
                          Icons.person_outline_rounded,
                          color: RelioColors.rescue,
                          size: 29,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              peer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: RelioColors.brandNavy,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: RelioColors.sos.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              connected ? 'SOS' : 'SOS ล่าสุด',
                              style: const TextStyle(
                                color: RelioColors.sosStrong,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        connected
                            ? 'เชื่อมต่อ Nearby • แสดงสถานะล่าสุดที่รับได้'
                            : 'ไม่ได้เชื่อมต่อ • สถานะ SOS ล่าสุดที่ได้รับ อาจยังไม่ได้รับการยกเลิก',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: connected
                              ? RelioColors.rescueStrong
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: RelioColors.rescue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'ลำดับ $order',
                  style: const TextStyle(
                    color: RelioColors.rescueStrong,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const Divider(height: 18),
            _SosDetailLine(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'ข้อความ',
              value: event?.message?.trim().isNotEmpty == true
                  ? event!.message!.trim()
                  : 'ไม่ได้ระบุข้อความ',
            ),
            const SizedBox(height: 9),
            _SosDetailLine(
              icon: Icons.schedule_rounded,
              label: 'เริ่ม SOS',
              value: event == null
                  ? 'ยังไม่มีรายละเอียดเหตุ SOS ในเครื่อง'
                  : '${event.createdAt.year}-${event.createdAt.month.toString().padLeft(2, '0')}-${event.createdAt.day.toString().padLeft(2, '0')}  ${event.createdAt.hour.toString().padLeft(2, '0')}:${event.createdAt.minute.toString().padLeft(2, '0')}',
            ),
            const SizedBox(height: 9),
            RelioLocationCard(
              title: 'ตำแหน่งจากคำขอ SOS',
              latitude: event?.latitude,
              longitude: event?.longitude,
              updatedAt: event?.locationCapturedAt,
              freshnessLabel: event == null
                  ? 'ไม่มีข้อมูลพิกัดที่บันทึกไว้'
                  : sosLocationFreshnessLabel(event, DateTime.now()),
              accuracyMeters: event?.locationAccuracy,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: !hasLocation
                      ? null
                      : () {
                          final parameters = <String, String>{
                            'target': deviceId,
                            'lat': event!.latitude!.toString(),
                            'lon': event.longitude!.toString(),
                            if (event.locationCapturedAt != null)
                              'capturedAt': event
                                  .locationCapturedAt!
                                  .millisecondsSinceEpoch
                                  .toString(),
                            if (event.locationAccuracy != null)
                              'accuracy': event.locationAccuracy!.toString(),
                            'historical': '1',
                          };
                          context.go(
                            Uri(
                              path: '/nearby',
                              queryParameters: parameters,
                            ).toString(),
                          );
                        },
                  icon: const Icon(Icons.near_me_outlined),
                  label: Text(hasLocation ? 'นำทางไปยังตำแหน่ง' : 'ไม่มีพิกัด'),
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/chat/$deviceId'),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('เปิดแชท'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Sos Detail Line)
class _SosDetailLine extends StatelessWidget {
  const _SosDetailLine({
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
      Icon(icon, color: RelioColors.rescue, size: 20),
      const SizedBox(width: 8),
      SizedBox(
        width: 86,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      Expanded(child: Text(value)),
    ],
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (SOSMap Preview)
class _SOSMapPreview extends StatefulWidget {
  const _SOSMapPreview({required this.location});

  final LocationData? location;

  @override
  State<_SOSMapPreview> createState() => _SOSMapPreviewState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (SOSMap Preview State)
class _SOSMapPreviewState extends State<_SOSMapPreview> {
  static const _styleUrl = String.fromEnvironment(
    'RELIO_MAP_STYLE_URL',
    defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
  );

  MapLibreMapController? _controller;
  Timer? _watchdog;
  bool _styleLoaded = false;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    if (widget.location != null && (Platform.isAndroid || Platform.isIOS)) {
      _watchdog = Timer(const Duration(seconds: 18), () {
        if (mounted && !_styleLoaded) setState(() => _unavailable = true);
      });
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
  }

  Future<void> _onStyleLoaded() async {
    final location = widget.location;
    final controller = _controller;
    if (location == null || controller == null) return;
    _watchdog?.cancel();
    try {
      await controller.addCircle(
        CircleOptions(
          geometry: LatLng(location.latitude, location.longitude),
          circleRadius: 9,
          circleColor: '#06B6D4',
          circleStrokeWidth: 3,
          circleStrokeColor: '#FFFFFF',
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() => _unavailable = true);
      return;
    }
    if (mounted) setState(() => _styleLoaded = true);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final colors = Theme.of(context).colorScheme;
    if (location == null || !(Platform.isAndroid || Platform.isIOS)) {
      return _mapFallback(
        context,
        location == null
            ? 'แผนที่จะแสดงเมื่อมีพิกัดจริง'
            : 'ดูแผนที่ตำแหน่งจริงได้บนอุปกรณ์มือถือ',
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        MapLibreMap(
          styleString: _styleUrl,
          initialCameraPosition: CameraPosition(
            target: LatLng(location.latitude, location.longitude),
            zoom: 14,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          compassEnabled: false,
          logoEnabled: false,
          attributionButtonPosition: AttributionButtonPosition.bottomLeft,
          attributionButtonMargins: const Point(8, 22),
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
        ),
        if (!_styleLoaded || _unavailable)
          ColoredBox(
            color: colors.surface.withValues(alpha: 0.94),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _unavailable
                          ? Icons.map_outlined
                          : Icons.location_searching,
                      color: RelioColors.primary,
                      size: 30,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _unavailable
                          ? 'แผนที่ออนไลน์ยังไม่พร้อม • พิกัดจริงยังแสดงด้านล่าง'
                          : 'กำลังโหลดแผนที่จากตำแหน่งจริง…',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const Positioned(
          right: 8,
          bottom: 5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xEEFFFFFF),
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 9, color: Colors.black87),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mapFallback(BuildContext context, String label) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    padding: const EdgeInsets.all(8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.map_outlined, color: RelioColors.primary, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
