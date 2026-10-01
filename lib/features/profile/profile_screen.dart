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
    final dependencies = RelioDependencyScope.of(context);
    final identity = dependencies.authService.identity;
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/branding/relio-logo-master.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      semanticLabel: 'โลโก้ RELIO',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FutureBuilder<String>(
                          future: dependencies.identity.getDisplayName(),
                          builder: (context, snapshot) => Text(
                            snapshot.data ??
                                identity?.displayName ??
                                'ผู้ใช้ RELIO',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
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
                    onPressed: () => _editDisplayName(context),
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
            onTap: () => _editDisplayName(context),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.medical_information_outlined,
            title: 'ข้อมูลฉุกเฉิน',
            subtitle: 'ยังไม่มีข้อมูลที่บันทึกไว้',
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.notifications_none_rounded,
            title: 'การแจ้งเตือน',
            subtitle: 'ยังไม่รองรับการแจ้งเตือนจากระบบ',
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
            icon: Icons.sync_rounded,
            title: 'สถานะการซิงก์',
            subtitle: 'ดูสถานะคิว Cloud จริง',
            onTap: () => context.push('/sync'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.lock_outline,
            title: 'ความเป็นส่วนตัว',
            onTap: () => _showPrivacy(context),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.info_outline,
            title: 'เกี่ยวกับ RELIO',
            subtitle:
                'เวอร์ชัน ${RelioBuildInfo.versionName}+${RelioBuildInfo.buildNumber}',
            onTap: () => _showAbout(context),
          ),
          const SizedBox(height: 14),
          if (identity != null)
            OutlinedButton.icon(
              onPressed: () async {
                await dependencies.authService.signOut();
                if (context.mounted) context.go('/welcome');
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('ออกจากระบบ'),
            ),
        ],
      ),
    );
  }

  Future<void> _editDisplayName(BuildContext context) async {
    final dependencies = RelioDependencyScope.of(context);
    final controller = TextEditingController(
      text: await dependencies.identity.getDisplayName(),
    );
    if (!context.mounted) {
      controller.dispose();
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ชื่อที่แสดง'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'ชื่อของคุณ'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (saved == true && context.mounted) {
      final value = controller.text.trim();
      if (value.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('กรุณาระบุชื่อที่แสดง')));
      } else {
        await dependencies.identity.setDisplayName(value);
        (context as Element).markNeedsBuild();
      }
    }
    controller.dispose();
  }

  void _showAbout(BuildContext context) => showAboutDialog(
    context: context,
    applicationName: RelioBuildInfo.appName,
    applicationVersion:
        '${RelioBuildInfo.versionName}+${RelioBuildInfo.buildNumber}',
    applicationIcon: Image.asset(
      'assets/branding/relio-logo-master.png',
      width: 52,
      height: 52,
    ),
    children: const [
      Text('สื่อสารและขอความช่วยเหลือผ่านอุปกรณ์ใกล้เคียง แม้ออฟไลน์'),
      SizedBox(height: 8),
      Text('ข้อมูลหลักจัดเก็บในเครื่อง; Cloud เป็นทางเลือก'),
    ],
  );

  void _showPrivacy(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('ความเป็นส่วนตัว'),
      content: const Text(
        'RELIO เก็บข้อมูลการสื่อสารไว้ในเครื่องก่อนเสมอ และใช้ Cloud เฉพาะเมื่อกำหนดค่าบัญชีไว้ ข้อมูลตำแหน่งจะขอเมื่อคุณสั่งแชร์ตำแหน่งหรือเปิด SOS เท่านั้น',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );
}
