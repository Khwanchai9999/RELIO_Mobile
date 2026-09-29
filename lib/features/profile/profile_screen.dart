import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/environment.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final identity = RelioDependencyScope.of(context).authService.identity;
    return Scaffold(
      appBar: RelioAppBar(
        title: 'โปรไฟล์',
        actions: [
          IconButton(
            onPressed: () => context.push('/settings'),
            tooltip: 'ตั้งค่า',
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          RelioSpacing.lg,
          16,
          RelioSpacing.lg,
          24,
        ),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const RelioUserAvatar(name: 'มินนี่', size: 72),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          identity?.displayName ?? 'มินนี่',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          identity?.email ?? 'ใช้งานแบบออฟไลน์',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('แก้ไขโปรไฟล์เป็น prototype ใน v0.1'),
                      ),
                    ),
                    tooltip: 'แก้ไขโปรไฟล์',
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          RelioSettingTile(
            icon: Icons.shield_outlined,
            title: 'โหมดหน่วยกู้ภัย (Rescue)',
            subtitle: 'ดูสถานะและเปลี่ยนโหมดจริง',
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/rescue'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.dark_mode_outlined,
            title: 'ธีม',
            subtitle: 'จัดการในตั้งค่า',
            onTap: () => context.push('/settings/theme'),
          ),
          const SizedBox(height: 18),
          Text(
            'บัญชีและแอป',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.person_outline,
            title: 'ข้อมูลส่วนตัว',
            onTap: () => _prototype(context, 'ข้อมูลส่วนตัว'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.medical_information_outlined,
            title: 'ข้อมูลฉุกเฉิน',
            onTap: () => _prototype(context, 'ข้อมูลฉุกเฉิน'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.notifications_none_rounded,
            title: 'การแจ้งเตือน',
            subtitle: 'ตัวอย่างการตั้งค่า • ยังไม่ผูกการแจ้งเตือนระบบ',
            onTap: () => _prototype(context, 'การแจ้งเตือน'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.link_rounded,
            title: 'การเชื่อมต่อ',
            subtitle: 'ตรวจดูสถานะ Internet, Bluetooth และ Nearby จริง',
            onTap: () => context.push('/settings'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.storage_outlined,
            title: 'พื้นที่จัดเก็บ',
            subtitle: 'ตัวอย่างข้อมูลพื้นที่ • ไม่ใช่ค่าจากระบบ',
            onTap: () => context.push('/sync'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.sync_rounded,
            title: 'สถานะการซิงก์',
            subtitle: 'ดูสถานะคิว Cloud จริง',
            onTap: () => context.push('/sync'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.lock_outline,
            title: 'ความเป็นส่วนตัว',
            onTap: () => _prototype(context, 'ความเป็นส่วนตัว'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.info_outline,
            title: 'เกี่ยวกับ RELIO',
            subtitle:
                'เวอร์ชัน ${RelioBuildInfo.versionName}+${RelioBuildInfo.buildNumber}',
            onTap: () => _prototype(context, 'เกี่ยวกับ RELIO'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () async {
              await RelioDependencyScope.of(context).authService.signOut();
              if (context.mounted) context.go('/welcome');
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
  }

  void _prototype(BuildContext context, String label) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$label เป็น prototype ใน v0.1')));
}
