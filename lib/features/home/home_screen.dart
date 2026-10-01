import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/connectivity/runtime_connectivity.dart';
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
  late final RelioDependencies _dependencies;
  bool _dependenciesLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_dependenciesLoaded) {
      _dependencies = RelioDependencyScope.of(context);
      _dependenciesLoaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const RelioUserAvatar(name: 'มินนี่', size: 42),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('สวัสดี 👋', style: Theme.of(context).textTheme.bodySmall),
                Text('มินนี่', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _dependencies.connectivityStatus.refresh(),
            tooltip: 'ตรวจสอบสถานะเครือข่ายจริง',
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: () {},
            tooltip: 'การแจ้งเตือน',
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 32 : 16,
                    16,
                    wide ? 32 : 16,
                    24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _LiveConnectivityPanel(),
                          const SizedBox(height: 18),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _EmergencyCard(
                                  icon: Icons.warning_amber_rounded,
                                  title: 'SOS',
                                  detail: 'ขอความช่วยเหลือ',
                                  color: RelioColors.sos,
                                  onTap: () => context.go('/sos'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _EmergencyCard(
                                  icon: Icons.shield_outlined,
                                  title: 'Rescue',
                                  detail: 'โหมดหน่วยกู้ภัย',
                                  color: RelioColors.rescue,
                                  onTap: () => context.go('/rescue'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _HomeLeftColumn(
                                    onNavigate: (route) => context.go(route),
                                  ),
                                ),
                                const SizedBox(width: 24),
                                SizedBox(
                                  width: 380,
                                  child: _NearbyPreview(
                                    onNavigate: (route) => context.go(route),
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _NearbyPreview(
                              onNavigate: (route) => context.go(route),
                            ),
                            const SizedBox(height: 20),
                            _HomeLeftColumn(
                              onNavigate: (route) => context.go(route),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.09),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 25),
              ),
              const SizedBox(height: 13),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                detail,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NearbyPreview extends StatelessWidget {
  const _NearbyPreview({required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final nearby = RelioDependencyScope.of(context).nearbyService;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RelioSectionHeader(
          title: 'อุปกรณ์ใกล้เคียง',
          action: () => onNavigate('/nearby'),
        ),
        AnimatedBuilder(
          animation: nearby,
          builder: (context, _) {
            final peers = nearby.connectedPeers;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: peers.isEmpty
                    ? const Text('ยังไม่มีอุปกรณ์จริงเชื่อมต่อ')
                    : Wrap(
                        spacing: 14,
                        runSpacing: 12,
                        children: peers
                            .map((peer) {
                              final id = peer.deviceId;
                              final name = peer.name;
                              return InkWell(
                                onTap: id == null
                                    ? null
                                    : () => onNavigate('/chat/$id'),
                                borderRadius: BorderRadius.circular(12),
                                child: Column(
                                  children: [
                                    RelioUserAvatar(
                                      name: name,
                                      size: 48,
                                      status: id == null
                                          ? null
                                          : nearby.peerStatuses[id],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(name),
                                    Text(
                                      'REAL • ${id == null ? 'กำลังยืนยันตัวตน' : 'เชื่อมต่อแล้ว'}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              );
                            })
                            .toList(growable: false),
                      ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HomeLeftColumn extends StatelessWidget {
  const _HomeLeftColumn({required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const RelioSectionHeader(title: 'แอคชันด่วน'),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.25,
          children: [
            RelioQuickActionCard(
              icon: Icons.chat_bubble_outline,
              label: 'แชท',
              color: RelioColors.primary,
              onTap: () => onNavigate('/chats'),
            ),
            RelioQuickActionCard(
              icon: Icons.location_on_outlined,
              label: 'ตำแหน่ง',
              color: RelioColors.rescue,
              onTap: () => onNavigate('/nearby'),
            ),
            RelioQuickActionCard(
              icon: Icons.folder_outlined,
              label: 'ไฟล์ที่แชร์',
              color: const Color(0xFF8B5CF6),
              onTap: () => onNavigate('/sync'),
            ),
            RelioQuickActionCard(
              icon: Icons.sync_rounded,
              label: 'ซิงก์ข้อมูล',
              color: RelioColors.success,
              onTap: () => onNavigate('/sync'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        RelioSectionHeader(
          title: 'ข้อความล่าสุด',
          action: () => onNavigate('/chats'),
        ),
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
}

class _LiveConnectivityPanel extends StatelessWidget {
  const _LiveConnectivityPanel();

  @override
  Widget build(BuildContext context) {
    final dependencies = RelioDependencyScope.of(context);
    final merged = Listenable.merge([
      dependencies.connectivityStatus,
      dependencies.nearbyService,
    ]);
    return AnimatedBuilder(
      animation: merged,
      builder: (context, _) => StreamBuilder<SyncEngineSnapshot>(
        stream: dependencies.syncEngine.watchState(),
        initialData: dependencies.syncEngine.snapshot,
        builder: (context, snapshot) {
          final internet = dependencies.connectivityStatus.status;
          final runtime = internet.runtime;
          final nearby = dependencies.nearbyService;
          final cloud = snapshot.data?.cloudState ?? CloudState.notConfigured;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(RelioSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'สถานะการเชื่อมต่อจริง',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 18,
                    runSpacing: 9,
                    children: [
                      _LiveStatusLine(
                        label: 'Internet',
                        value: _internetLabel(internet.reachability),
                        color: _internetColor(internet.reachability),
                      ),
                      _LiveStatusLine(
                        label: 'Wi-Fi',
                        value: _radioLabel(runtime.wifiEnabled),
                      ),
                      _LiveStatusLine(
                        label: 'Bluetooth',
                        value: _radioLabel(runtime.bluetoothEnabled),
                      ),
                      _LiveStatusLine(
                        label: 'Nearby',
                        value: nearby.statusLabel,
                        color: RelioColors.primary,
                      ),
                      _LiveStatusLine(
                        label: 'เชื่อมต่อแล้ว',
                        value: '${nearby.connectedPeerCount} เครื่อง',
                      ),
                      _LiveStatusLine(
                        label: 'Cloud Sync',
                        value: _cloudLabel(cloud),
                        color: cloud == CloudState.ready
                            ? RelioColors.success
                            : RelioColors.warning,
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

class _LiveStatusLine extends StatelessWidget {
  const _LiveStatusLine({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 9, color: color ?? RelioColors.primary),
      const SizedBox(width: 6),
      Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

String _internetLabel(InternetReachability state) => switch (state) {
  InternetReachability.checking => 'กำลังตรวจสอบ',
  InternetReachability.online => 'ออนไลน์',
  InternetReachability.offline => 'ออฟไลน์',
  InternetReachability.limited => 'จำกัด / ตรวจสอบปลายทางไม่ได้',
  InternetReachability.unknown => 'ไม่ทราบ',
};

Color _internetColor(InternetReachability state) => switch (state) {
  InternetReachability.online => RelioColors.success,
  InternetReachability.offline => RelioColors.warning,
  InternetReachability.limited => RelioColors.warning,
  InternetReachability.checking ||
  InternetReachability.unknown => RelioColors.muted,
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
