import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/connectivity/runtime_connectivity.dart';
import '../../core/nearby/nearby_transport.dart';
import '../../core/relio_dependencies.dart';
import '../../core/sync/sync_engine.dart';
import '../../data/mock_data.dart';
import '../../data/models/prototype_models.dart';
import '../../shared/widgets/relio_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

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
                    ),
                    const SizedBox(height: 12),
                    const _LiveConnectivityPanel(),
                    const SizedBox(height: 14),
                    _EmergencyCards(stack: stackEmergencyCards),
                    const SizedBox(height: 22),
                    _NearbyPreview(onNavigate: (route) => context.go(route)),
                    const SizedBox(height: 22),
                    _QuickActions(onNavigate: (route) => context.go(route)),
                    const SizedBox(height: 22),
                    _RecentMessages(onNavigate: (route) => context.go(route)),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: 'RELIO',
                child: RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.6,
                      height: 0.98,
                    ),
                    children: [
                      TextSpan(
                        text: 'REL',
                        style: TextStyle(
                          color: dark
                              ? RelioColors.brandWhite
                              : RelioColors.brandNavy,
                        ),
                      ),
                      const TextSpan(
                        text: 'I',
                        style: TextStyle(color: RelioColors.primary),
                      ),
                      const TextSpan(
                        text: 'O',
                        style: TextStyle(color: RelioColors.sos),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'สื่อสารได้ แม้ไม่มีสัญญาณ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: dark
                      ? RelioColors.darkTagline
                      : RelioColors.lightTagline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.displayName,
    required this.avatarPath,
    required this.onTap,
  });

  final Future<String> displayName;
  final Future<String?> avatarPath;
  final VoidCallback onTap;

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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                FutureBuilder<String?>(
                  future: avatarPath,
                  builder: (context, snapshot) {
                    final path = snapshot.data;
                    if (path == null) {
                      return FutureBuilder<String>(
                        future: displayName,
                        builder: (context, nameSnapshot) => _AvatarFrame(
                          child: RelioUserAvatar(
                            name: nameSnapshot.data ?? 'ผู้ใช้ RELIO',
                            size: 68,
                          ),
                        ),
                      );
                    }
                    return _AvatarFrame(
                      child: ClipOval(
                        child: Image.file(
                          File(path),
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.person_rounded,
                            size: 42,
                            color: RelioColors.primary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 14),
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
                        Text(
                          snapshot.data ?? 'ผู้ใช้ RELIO',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        const _ReadyChip(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarFrame extends StatelessWidget {
  const _AvatarFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 78,
    height: 78,
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

class _ReadyChip extends StatelessWidget {
  const _ReadyChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: RelioColors.success.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: RelioColors.success, size: 15),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            'ใช้งานในเครื่องได้',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: RelioColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LiveConnectivityPanel extends StatefulWidget {
  const _LiveConnectivityPanel();

  @override
  State<_LiveConnectivityPanel> createState() => _LiveConnectivityPanelState();
}

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
              padding: const EdgeInsets.all(RelioSpacing.md),
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
                                        ? 'ไม่มี Internet แต่ Nearby ยังเชื่อมต่ออยู่'
                                        : 'ยังสื่อสารในเครื่องได้เมื่อมีอุปกรณ์ Nearby'
                                  : 'Internet และ Nearby แสดงสถานะแยกกัน',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ConnectedCount(count: connected),
                    ],
                  ),
                  const SizedBox(height: 14),
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
                            icon: Icons.wifi_rounded,
                            label: 'Wi-Fi',
                            value: _radioLabel(runtime.wifiEnabled),
                            color: RelioColors.connectivityBlue,
                          ),
                          _ConnectivityTile(
                            width: tileWidth,
                            icon: Icons.bluetooth_rounded,
                            label: 'Bluetooth',
                            value: _radioLabel(runtime.bluetoothEnabled),
                            color: RelioColors.primary,
                          ),
                          _ConnectivityTile(
                            width: tileWidth,
                            icon: Icons.radar_rounded,
                            label: 'Nearby',
                            value: nearby.statusLabel,
                            color: RelioColors.connectivityCyan,
                          ),
                          _ConnectivityTile(
                            width: tileWidth,
                            icon: Icons.cloud_sync_rounded,
                            label: 'Cloud Sync',
                            value: _cloudLabel(cloud),
                            color: RelioColors.quickGreen,
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

class _ConnectedCount extends StatelessWidget {
  const _ConnectedCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 62),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
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
        Text('Nearby', style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _ConnectivityTile extends StatelessWidget {
  const _ConnectivityTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 54),
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
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
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
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
      support: 'แจ้งเหตุไปยังเพื่อนร่วมทีม',
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

class _NearbyPreview extends StatelessWidget {
  const _NearbyPreview({required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final nearby = RelioDependencyScope.of(context).nearbyService;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          icon: Icons.radar_rounded,
          title: 'อุปกรณ์ใกล้เคียง',
          action: 'ดูทั้งหมด',
          onTap: () => onNavigate('/nearby'),
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: nearby,
          builder: (context, _) {
            final peers = nearby.connectedPeers;
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: _cardDecoration(context),
              child: peers.isEmpty
                  ? Row(
                      children: [
                        const _EmptyNearbyIcon(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ยังไม่มีอุปกรณ์เชื่อมต่อ',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'เปิด Nearby เพื่อค้นหาอุปกรณ์รอบตัว',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'เปิด Nearby',
                          onPressed: () => onNavigate('/nearby'),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    )
                  : Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: peers
                          .take(3)
                          .map((peer) {
                            final deviceId = peer.deviceId;
                            return _ConnectedPeerChip(
                              peer: peer,
                              onTap: deviceId == null
                                  ? null
                                  : () => onNavigate('/chat/$deviceId'),
                            );
                          })
                          .toList(growable: false),
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _EmptyNearbyIcon extends StatelessWidget {
  const _EmptyNearbyIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: RelioColors.connectivityCyan.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.radar_rounded, color: RelioColors.connectivityCyan),
  );
}

class _ConnectedPeerChip extends StatelessWidget {
  const _ConnectedPeerChip({required this.peer, required this.onTap});

  final NearbyPeer peer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).brightness == Brightness.dark
        ? RelioColors.darkRaised
        : RelioColors.peerChip,
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RelioUserAvatar(name: peer.name, size: 42),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 155),
                  child: Text(
                    peer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Text(
                  'REAL • เชื่อมต่อแล้ว',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: RelioColors.success),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 620 ? 4 : 2;
      final gap = 10.0;
      final tileWidth = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeading(icon: Icons.bolt_rounded, title: 'แอคชันด่วน'),
          const SizedBox(height: 9),
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              _QuickActionTile(
                width: tileWidth,
                icon: Icons.chat_bubble_rounded,
                label: 'แชท',
                detail: 'พูดคุยกับเพื่อน',
                color: RelioColors.quickCyan,
                onTap: () => onNavigate('/chats'),
              ),
              _QuickActionTile(
                width: tileWidth,
                icon: Icons.location_on_rounded,
                label: 'ตำแหน่ง',
                detail: 'ดูแผนที่ Nearby',
                color: RelioColors.quickBlue,
                onTap: () => onNavigate('/nearby'),
              ),
              _QuickActionTile(
                width: tileWidth,
                icon: Icons.folder_rounded,
                label: 'ไฟล์ที่แชร์',
                detail: 'ดูไฟล์ร่วมกัน',
                color: RelioColors.quickPurple,
                onTap: () => onNavigate('/sync'),
              ),
              _QuickActionTile(
                width: tileWidth,
                icon: Icons.sync_rounded,
                label: 'ซิงก์ข้อมูล',
                detail: 'อัปเดตข้อมูล',
                color: RelioColors.quickGreen,
                onTap: () => onNavigate('/sync'),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      child: Material(
        color: dark ? RelioColors.darkRaised : color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: ValueKey('quick-$label'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 116),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withValues(alpha: dark ? 0.45 : 0.22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.72)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentMessages extends StatelessWidget {
  const _RecentMessages({required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SectionHeading(
        icon: Icons.forum_rounded,
        title: 'ข้อความล่าสุด',
        action: 'ดูแชท',
        onTap: () => onNavigate('/chats'),
      ),
      const SizedBox(height: 8),
      ...RelioMockData.chats
          .take(2)
          .map(
            (chat) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RelioChatListTile(
                chat: RelioChatPreview(
                  id: chat.id,
                  name: chat.name,
                  message: chat.message,
                  time: chat.time,
                  status: chat.status,
                  unread: chat.unread,
                  isDemo: true,
                ),
                onTap: () => onNavigate('/chat/${chat.id}'),
              ),
            ),
          ),
    ],
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: RelioColors.connectivityCyan, size: 22),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      if (action != null)
        TextButton.icon(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.chevron_right_rounded, size: 19),
          label: Text(action!),
        ),
    ],
  );
}

BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
  color: Theme.of(context).colorScheme.surface,
  borderRadius: BorderRadius.circular(22),
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
              .withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ],
);
