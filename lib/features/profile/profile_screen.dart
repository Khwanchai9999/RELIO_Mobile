import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/environment.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<CloudProfile>? _profileFuture;
  Future<String>? _localDisplayNameFuture;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (dependencies.authService.identity != null && _profileFuture == null) {
      _profileFuture = dependencies.cloudDataSource.fetchMyProfile();
    }
    _localDisplayNameFuture ??= dependencies.identity.getDisplayName();
  }

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
                        _memberName(context, identity),
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
          if (identity != null) ...[
            RelioSettingTile(
              icon: Icons.content_copy_rounded,
              title: 'Cloud Account ID',
              subtitle: 'แตะเพื่อคัดลอกและแชร์กับผู้ติดต่อที่เชื่อถือได้',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: identity.userId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('คัดลอก Cloud Account ID แล้ว'),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
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
            title: 'แก้ไขข้อมูลสมาชิก',
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
              onPressed: _busy
                  ? null
                  : () async {
                      await dependencies.removePushRegistration();
                      await dependencies.authService.signOut();
                      if (context.mounted) context.go('/welcome');
                    },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('ออกจากระบบ'),
            ),
          if (identity != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _confirmDeleteAccount(context),
              icon: const Icon(Icons.delete_outline),
              label: Text(_busy ? 'กำลังลบบัญชี...' : 'ลบบัญชี'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memberName(BuildContext context, CloudIdentity? identity) {
    final style = Theme.of(context).textTheme.headlineSmall;
    if (identity == null) {
      return FutureBuilder<String>(
        future: _localDisplayNameFuture,
        builder: (context, snapshot) =>
            Text(snapshot.data ?? 'ผู้ใช้ RELIO', style: style),
      );
    }
    return FutureBuilder<CloudProfile>(
      future: _profileFuture,
      builder: (context, snapshot) => Text(
        snapshot.hasError
            ? 'อ่านข้อมูลสมาชิกไม่สำเร็จ'
            : snapshot.data?.displayName ?? 'กำลังโหลดข้อมูลสมาชิก...',
        style: style,
      ),
    );
  }

  Future<void> _editDisplayName(BuildContext context) async {
    final dependencies = RelioDependencyScope.of(context);
    String initialName;
    try {
      initialName = dependencies.authService.identity == null
          ? await dependencies.identity.getDisplayName()
          : (await (_profileFuture ??= dependencies.cloudDataSource
                    .fetchMyProfile()))
                .displayName;
    } on CloudException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    final controller = TextEditingController(text: initialName);
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
        try {
          if (dependencies.authService.identity != null) {
            await dependencies.cloudDataSource.upsertProfile(
              displayName: value,
            );
            _profileFuture = dependencies.cloudDataSource.fetchMyProfile();
          } else {
            await dependencies.identity.setDisplayName(value);
          }
          if (context.mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('บันทึกข้อมูลสมาชิกแล้ว')),
            );
          }
        } on CloudException catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.message)));
          }
        }
      }
    }
    controller.dispose();
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบบัญชี'),
        content: const Text(
          'บัญชีนี้จะเข้าสู่ระบบไม่ได้อีก ข้อมูลตำแหน่งและอุปกรณ์จะถูกลบ '
          'ส่วนประวัติแชตจะยังอยู่ โดยเปลี่ยนชื่อเป็น “บัญชีที่ลบแล้ว”',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบบัญชี'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted || _busy) return;

    setState(() => _busy = true);
    try {
      await RelioDependencyScope.of(context).authService.deleteAccount();
      if (context.mounted) context.go('/login');
    } on CloudException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
