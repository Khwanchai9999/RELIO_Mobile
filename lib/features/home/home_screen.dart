// หน้าแรกที่สรุปตัวตน สถานะการเชื่อมต่อ และทางลัดการใช้งานฉุกเฉินจากข้อมูลจริงของแอป
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/connectivity/runtime_connectivity.dart';
import '../../core/relio_dependencies.dart';
import '../../core/nearby/nearby_readiness.dart';
import '../../core/sync/sync_engine.dart';
import '../../shared/widgets/relio_widgets.dart';

// หน้า Home รวมทางลัด สถานะ และการนำทาง โดยอ่านข้อมูลผ่าน application dependencies
// สถานะการเชื่อมต่อและการซิงก์ยังคงแสดงแยกจากกัน
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Home Screen State)
class _HomeScreenState extends State<HomeScreen> {
  RelioDependencies? _dependencies;
  Future<String>? _displayName;
  Future<String?>? _avatarPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (_dependencies == dependencies) return;
    _dependencies?.repositories.profiles.removeListener(_profileChanged);
    _dependencies = dependencies;
    dependencies.repositories.profiles.addListener(_profileChanged);
    _readProfile();
  }

  void _readProfile() {
    final dependencies = _dependencies!;
    _displayName = dependencies.identity.getDisplayName();
    _avatarPath = dependencies.profileAvatarRepository.getAvatarPath();
  }

  void _profileChanged() {
    if (!mounted) return;
    setState(_readProfile);
  }

  @override
  void dispose() {
    _dependencies?.repositories.profiles.removeListener(_profileChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final stackEmergencyCards = width < 420 || textScale >= 1.3;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth >= 720 ? 28 : 16,
              10,
              constraints.maxWidth >= 720 ? 28 : 16,
              24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HomeHeader(
                      onRefresh: () =>
                          _dependencies!.connectivityStatus.refresh(),
                      onSettings: () => context.go('/settings'),
                    ),
                    const SizedBox(height: 16),
                    _GreetingCard(
                      displayName: _displayName!,
                      avatarPath: _avatarPath!,
                      onTap: () => context.go('/profile'),
                      onFlashlight: () => context.push('/screen-flashlight'),
                      readinessListenable: _dependencies!.nearbyService,
                      readReadiness: () =>
                          _dependencies!.nearbyService.readiness,
                    ),
                    const SizedBox(height: 12),
                    _EmergencyCards(stack: stackEmergencyCards),
                    const SizedBox(height: 14),
                    const _LiveConnectivityPanel(
                      key: ValueKey('home-connectivity-panel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Home Header)
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onRefresh, required this.onSettings});

  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final logoWidth = constraints.maxWidth < 129
                  ? constraints.maxWidth
                  : 129.0;
              return SizedBox(
                width: logoWidth,
                height: 48,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image.asset(
                    dark
                        ? 'assets/branding/relio_wordmark_dark_final.png'
                        : 'assets/branding/relio_wordmark.png',
                    width: logoWidth,
                    height: 48,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    semanticLabel: 'RELIO',
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        _HeaderAction(
          tooltip: 'ตรวจสอบสถานะเครือข่ายจริง',
          icon: Icons.refresh_rounded,
          onPressed: onRefresh,
        ),
        const SizedBox(width: 6),
        _HeaderAction(
          tooltip: 'ตั้งค่า',
          icon: Icons.settings_outlined,
          onPressed: onSettings,
        ),
      ],
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Header Action)
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? RelioColors.darkRaised : RelioColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: dark ? RelioColors.darkBorder : RelioColors.homeSoftBorder,
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: Theme.of(context).colorScheme.onSurface,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Greeting Card)
class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.displayName,
    required this.avatarPath,
    required this.onTap,
    required this.onFlashlight,
    required this.readinessListenable,
    required this.readReadiness,
  });

  final Future<String> displayName;
  final Future<String?> avatarPath;
  final VoidCallback onTap;
  final VoidCallback onFlashlight;
  final Listenable readinessListenable;
  final NearbyReadiness? Function() readReadiness;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [RelioColors.darkRaised, RelioColors.darkGreetingEnd]
              : [RelioColors.lightSurface, RelioColors.lightGreetingEnd],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark ? RelioColors.darkBorder : RelioColors.homeSoftBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: (dark ? Colors.black : RelioColors.primary).withValues(
              alpha: dark ? 0.16 : 0.08,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('home-profile-card'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                FutureBuilder<String>(
                  key: ObjectKey(displayName),
                  future: displayName,
                  builder: (context, nameSnapshot) => FutureBuilder<String?>(
                    key: ObjectKey(avatarPath),
                    future: avatarPath,
                    builder: (context, avatarSnapshot) => _AvatarFrame(
                      child: RelioPrincipalAvatar(
                        name: nameSnapshot.data ?? '',
                        imagePath: avatarSnapshot.data,
                        size: 58,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FutureBuilder<String>(
                    future: displayName,
                    builder: (context, snapshot) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'สวัสดี 👋',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final name = snapshot.data ?? 'ผู้ใช้ RELIO';
                            final baseStyle = Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800);
                            final scaler = MediaQuery.textScalerOf(context);
                            var fontSize = (baseStyle?.fontSize ?? 24)
                                .clamp(18.0, 22.0)
                                .toDouble();
                            for (; fontSize > 18; fontSize -= 1) {
                              final painter = TextPainter(
                                text: TextSpan(
                                  text: name,
                                  style: baseStyle?.copyWith(
                                    fontSize: fontSize,
                                  ),
                                ),
                                maxLines: 1,
                                textDirection: Directionality.of(context),
                                textScaler: scaler,
                              )..layout(maxWidth: constraints.maxWidth);
                              if (!painter.didExceedMaxLines) break;
                            }
                            return Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              strutStyle: const StrutStyle(
                                fontSize: 22,
                                height: 1,
                                forceStrutHeight: true,
                              ),
                              style: baseStyle?.copyWith(fontSize: fontSize),
                            );
                          },
                        ),
                        const SizedBox(height: 3),
                        AnimatedBuilder(
                          animation: readinessListenable,
                          builder: (context, _) =>
                              _ReadyChip(readiness: readReadiness()),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(height: 4),
                    IconButton(
                      tooltip: 'ไฟฉายหน้าจอ',
                      onPressed: onFlashlight,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.08),
                        foregroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      icon: const Icon(Icons.flashlight_on, size: 21),
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

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Avatar Frame)
class _AvatarFrame extends StatelessWidget {
  const _AvatarFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 68,
    height: 68,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        colors: [RelioColors.primary, RelioColors.avatarBlue],
      ),
      boxShadow: [
        BoxShadow(
          color: RelioColors.primary.withValues(alpha: 0.2),
          blurRadius: 12,
        ),
      ],
    ),
    child: ClipOval(child: child),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Ready Chip)
class _ReadyChip extends StatelessWidget {
  const _ReadyChip({required this.readiness});

  final NearbyReadiness? readiness;

  @override
  Widget build(BuildContext context) {
    final stateUnknown =
        readiness == null ||
        readiness!.policy.sdkInt == null ||
        (readiness!.playServicesStatus == 'unknown' &&
            readiness!.blockers.isEmpty);
    final ready = stateUnknown ? null : readiness!.ready;
    final label = ready == null
        ? 'กำลังตรวจสอบ'
        : ready
        ? 'ระบบพร้อมใช้งาน'
        : 'ต้องตรวจสอบบางอย่าง';
    final color = ready == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : ready
        ? RelioColors.success
        : RelioColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ready == null)
            SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(
              ready ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: color,
              size: 15,
            ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Live Connectivity Panel)
class _LiveConnectivityPanel extends StatefulWidget {
  const _LiveConnectivityPanel({super.key});

  @override
  State<_LiveConnectivityPanel> createState() => _LiveConnectivityPanelState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Live Connectivity Panel State)
class _LiveConnectivityPanelState extends State<_LiveConnectivityPanel> {
  RelioDependencies? _dependencies;
  late Stream<SyncEngineSnapshot> _syncStates;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (_dependencies == dependencies) return;
    _dependencies = dependencies;
    _syncStates = dependencies.syncEngine.watchState();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies!;
    final merged = Listenable.merge([
      dependencies.connectivityStatus,
      dependencies.nearbyService,
    ]);
    return AnimatedBuilder(
      animation: merged,
      builder: (context, _) => StreamBuilder<SyncEngineSnapshot>(
        stream: _syncStates,
        initialData: dependencies.syncEngine.snapshot,
        builder: (context, snapshot) {
          final internet = dependencies.connectivityStatus.status;
          final runtime = internet.runtime;
          final nearby = dependencies.nearbyService;
          final cloud = snapshot.data?.cloudState ?? CloudState.notConfigured;
          final offline = internet.reachability == InternetReachability.offline;
          final connected = nearby.connectedPeerCount;
          final compact =
              MediaQuery.sizeOf(context).width < 580 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.3;
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? RelioColors.darkBorder
                    : RelioColors.homeSoftBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (Theme.of(context).brightness == Brightness.dark
                              ? Colors.black
                              : RelioColors.avatarBlue)
                          .withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : RelioSpacing.md,
                vertical: compact ? 8 : RelioSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _StatusOrb(
                        icon: offline
                            ? Icons.wifi_off_rounded
                            : Icons.wifi_rounded,
                        color: offline
                            ? RelioColors.offline
                            : RelioColors.success,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _internetLabel(internet.reachability),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              offline
                                  ? connected > 0
                                        ? 'สถานะเน็ตและอุปกรณ์ใกล้เคียง'
                                        : 'สถานะเน็ตและอุปกรณ์ใกล้เคียง'
                                  : 'สถานะเน็ตและอุปกรณ์ใกล้เคียง',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ConnectedCount(count: nearby.reachablePeerCount),
                    ],
                  ),
                  SizedBox(height: compact ? 6 : 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 580 ? 4 : 2;
                      final gap = 8.0;
                      final tileWidth =
                          (constraints.maxWidth - (columns - 1) * gap) /
                          columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          _ConnectivityTile(
                            width: tileWidth,
                            compact: compact,
                            icon: Icons.wifi_rounded,
                            label: 'Wi-Fi',
                            value: _radioLabel(runtime.wifiEnabled),
                            color: RelioColors.connectivityBlue,
                          ),
                          _ConnectivityTile(
                            width: tileWidth,
                            compact: compact,
                            icon: Icons.bluetooth_rounded,
                            label: 'Bluetooth',
                            value: _radioLabel(runtime.bluetoothEnabled),
                            color: RelioColors.primary,
                          ),
                          _ConnectivityTile(
                            width: tileWidth,
                            compact: compact,
                            icon: Icons.radar_rounded,
                            label: 'อุปกรณ์ใกล้เคียง',
                            value: nearby.statusLabel,
                            color: RelioColors.connectivityCyan,
                            onTap: () => context.go('/nearby'),
                          ),
                          _ConnectivityTile(
                            width: tileWidth,
                            compact: compact,
                            icon: Icons.cloud_sync_rounded,
                            label: 'ซิงก์ข้อมูล',
                            value: _cloudLabel(cloud),
                            color: RelioColors.quickGreen,
                            onTap: () => context.go('/sync'),
                          ),
                        ],
                      );
                    },
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

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Status Orb)
class _StatusOrb extends StatelessWidget {
  const _StatusOrb({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 62,
    height: 62,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: 0.13),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Icon(icon, color: color, size: 31),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Connected Count)
class _ConnectedCount extends StatelessWidget {
  const _ConnectedCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final boxWidth = 92.0 + (textScale > 1 ? (textScale - 1) * 16 : 0);
    return Container(
      width: boxWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: RelioColors.connectivityCyan.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: RelioColors.connectivityCyan,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'อุปกรณ์\nใกล้เคียง',
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Connectivity Tile)
class _ConnectivityTile extends StatelessWidget {
  const _ConnectivityTile({
    required this.width,
    required this.compact,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final double width;
  final bool compact;
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 44 : 54),
        width: width,
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: compact ? 4 : 8),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? RelioColors.darkRaised
              : color.withValues(alpha: 0.065),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _internetLabel(InternetReachability state) => switch (state) {
  InternetReachability.checking => 'กำลังตรวจสอบ Internet',
  InternetReachability.online => 'ออนไลน์',
  InternetReachability.offline => 'ออฟไลน์',
  InternetReachability.limited => 'เชื่อมต่อจำกัด',
  InternetReachability.unknown => 'ไม่ทราบสถานะ Internet',
};

String _radioLabel(bool? enabled) => switch (enabled) {
  true => 'พร้อมใช้งาน',
  false => 'ปิดอยู่',
  null => 'ไม่ทราบ',
};

String _cloudLabel(CloudState state) => switch (state) {
  CloudState.ready => 'พร้อมซิงก์',
  CloudState.offline => 'รออินเทอร์เน็ต',
  CloudState.notConfigured => 'ใช้เฉพาะในเครื่อง',
  CloudState.signedOut => 'Guest / ในเครื่อง',
  CloudState.error => 'ยังซิงก์ไม่ได้',
};

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Emergency Cards)
class _EmergencyCards extends StatelessWidget {
  const _EmergencyCards({required this.stack});

  final bool stack;

  @override
  Widget build(BuildContext context) {
    final sos = _EmergencyCard(
      key: const ValueKey('home-sos-card'),
      compact: stack,
      title: 'SOS',
      detail: 'ขอความช่วยเหลือ',
      support: 'แจ้งเหตุไปยังอุปกรณ์ใกล้เคียง',
      icon: Icons.sos_rounded,
      colors: const [RelioColors.sosStart, RelioColors.sosEnd],
      onTap: () => context.go('/sos'),
    );
    final rescue = _EmergencyCard(
      key: const ValueKey('home-rescue-card'),
      compact: stack,
      title: 'Rescue',
      detail: 'โหมดหน่วยกู้ภัย',
      support: 'ค้นหาและช่วยเหลือในพื้นที่',
      icon: Icons.health_and_safety_rounded,
      colors: const [RelioColors.rescueStart, RelioColors.rescueEnd],
      onTap: () => context.go('/rescue'),
    );
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [sos, const SizedBox(height: 12), rescue],
      );
    }
    return Row(
      children: [
        Expanded(child: sos),
        const SizedBox(width: 12),
        Expanded(child: rescue),
      ],
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Emergency Card)
class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({
    super.key,
    required this.compact,
    required this.title,
    required this.detail,
    required this.support,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final bool compact;
  final String detail;
  final String support;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.64)),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: EdgeInsets.all(compact ? 8 : 15),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 34),
                  child: compact
                      ? Row(
                          children: [
                            _EmergencyIcon(icon: icon, compact: true),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _EmergencyCopy(
                                title: title,
                                detail: detail,
                                support: support,
                                compact: true,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _EmergencyIcon(icon: icon),
                            const SizedBox(height: 9),
                            _EmergencyCopy(
                              title: title,
                              detail: detail,
                              support: support,
                            ),
                          ],
                        ),
                ),
                const Positioned(
                  top: 2,
                  right: 0,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 25,
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

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Emergency Icon)
class _EmergencyIcon extends StatelessWidget {
  const _EmergencyIcon({required this.icon, this.compact = false});

  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    width: compact ? 46 : 54,
    height: compact ? 46 : 54,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.2),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
    ),
    child: Icon(icon, color: Colors.white, size: compact ? 27 : 31),
  );
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Emergency Copy)
class _EmergencyCopy extends StatelessWidget {
  const _EmergencyCopy({
    required this.title,
    required this.detail,
    required this.support,
    this.compact = false,
  });

  final String title;
  final String detail;
  final String support;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        detail,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      SizedBox(height: compact ? 6 : 8),
      Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              title == 'SOS' ? Icons.call_rounded : Icons.groups_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                support,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
