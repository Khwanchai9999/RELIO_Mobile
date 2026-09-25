import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../data/mock_data.dart';
import '../../shared/widgets/relio_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _internetOnline = true;

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
          TextButton.icon(
            onPressed: () => setState(() => _internetOnline = !_internetOnline),
            icon: Icon(
              _internetOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              size: 14,
            ),
            label: Text(_internetOnline ? 'ออนไลน์' : 'ออฟไลน์'),
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
          RelioConnectivityBanner(internetOnline: _internetOnline),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RelioSectionHeader(
          title: 'อุปกรณ์ใกล้เคียง',
          action: () => onNavigate('/nearby'),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...RelioMockData.devices
                      .take(4)
                      .map(
                        (device) => Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: InkWell(
                            onTap: () => onNavigate('/chat/${device.id}'),
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              children: [
                                RelioUserAvatar(
                                  name: device.name,
                                  size: 48,
                                  status: device.status,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  device.approximateDistance,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  InkWell(
                    onTap: () => onNavigate('/nearby'),
                    borderRadius: BorderRadius.circular(30),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                          child: const Center(child: Text('+1')),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'อีก 1',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                  chat: chat,
                  onTap: () => onNavigate('/chat/${chat.id}'),
                ),
              ),
            ),
        Card(
          child: InkWell(
            onTap: () => onNavigate('/sync'),
            borderRadius: BorderRadius.circular(16),
            child: const Padding(
              padding: EdgeInsets.all(RelioSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.sync_rounded, color: RelioColors.primary),
                  SizedBox(width: 8),
                  Expanded(child: Text('ซิงก์ข้อมูลแล้ว')),
                  Text('10:24'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
