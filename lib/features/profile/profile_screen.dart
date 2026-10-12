import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/environment.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/relio_dependencies.dart';
import '../../core/repositories/profile_avatar_repository.dart';
import '../../shared/widgets/relio_widgets.dart';

enum _AvatarAction { camera, gallery, remove }

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<String>? _localDisplayNameFuture;
  Future<bool>? _usingDefaultNameFuture;
  Future<String?>? _avatarPathFuture;
  bool _busy = false;
  bool _avatarBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    _localDisplayNameFuture ??= dependencies.identity.getDisplayName();
    _usingDefaultNameFuture ??= dependencies.identity
        .isUsingDefaultDisplayName();
    _avatarPathFuture ??= dependencies.profileAvatarRepository.getAvatarPath();
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
                  Semantics(
                    button: true,
                    label: 'รูปโปรไฟล์',
                    child: InkWell(
                      onTap: _avatarBusy ? null : () => _editAvatar(context),
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: FutureBuilder<String?>(
                              future: _avatarPathFuture,
                              builder: (context, snapshot) {
                                final imagePath = snapshot.data;
                                return imagePath == null
                                    ? Image.asset(
                                        'assets/branding/relio-logo-master.png',
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                        semanticLabel: 'โลโก้ RELIO',
                                      )
                                    : Image.file(
                                        File(imagePath),
                                        width: 72,
                                        height: 72,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Image.asset(
                                          'assets/branding/relio-logo-master.png',
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.cover,
                                          semanticLabel: 'โลโก้ RELIO',
                                        ),
                                      );
                              },
                            ),
                          ),
                          if (_avatarBusy)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _memberName(context),
                        FutureBuilder<bool>(
                          future: _usingDefaultNameFuture,
                          builder: (context, snapshot) => snapshot.data == true
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    'แนะนำให้ใช้ชื่อจริงหรือชื่อที่คนใกล้ตัวรู้จัก',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                )
                              : const SizedBox.shrink(),
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

  Widget _memberName(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall;
    return FutureBuilder<String>(
      future: _localDisplayNameFuture,
      builder: (context, snapshot) => Text(
        snapshot.data ?? 'ผู้ใช้ RELIO',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }

  Future<void> _editDisplayName(BuildContext context) async {
    final dependencies = RelioDependencyScope.of(context);
    String initialName;
    try {
      initialName = await dependencies.identity.getDisplayName();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อ่านชื่อที่แสดงไม่สำเร็จ')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final enteredName = await showDialog<String>(
      context: context,
      builder: (_) => _DisplayNameDialog(initialName: initialName),
    );
    if (enteredName != null && context.mounted) {
      final value = enteredName.trim();
      if (value.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('กรุณาระบุชื่อที่แสดง')));
      } else if (value.runes.length > 40) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ชื่อต้องไม่เกิน 40 ตัวอักษร')),
        );
      } else {
        try {
          await dependencies.identity.setDisplayName(value);
          if (context.mounted) {
            setState(() {
              _localDisplayNameFuture = dependencies.identity.getDisplayName();
              _usingDefaultNameFuture = dependencies.identity
                  .isUsingDefaultDisplayName();
            });
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
  }

  Future<void> _editAvatar(BuildContext context) async {
    final dependencies = RelioDependencyScope.of(context);
    final repository = dependencies.profileAvatarRepository;
    final currentAvatar = await repository.getAvatarPath();
    if (!context.mounted) return;
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('รูปโปรไฟล์'),
              titleTextStyle: TextStyle(fontWeight: FontWeight.w600),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('ถ่ายรูป'),
              onTap: () => Navigator.pop(sheetContext, _AvatarAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกจากเครื่อง'),
              onTap: () => Navigator.pop(sheetContext, _AvatarAction.gallery),
            ),
            if (currentAvatar != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('ลบรูป'),
                onTap: () => Navigator.pop(sheetContext, _AvatarAction.remove),
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('ยกเลิก'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    setState(() => _avatarBusy = true);
    try {
      if (action == _AvatarAction.remove) {
        await repository.removeAvatar();
      } else {
        final picked = await ImagePicker().pickImage(
          source: action == _AvatarAction.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: 256,
          maxHeight: 256,
          imageQuality: 82,
          requestFullMetadata: false,
        );
        if (picked == null) return;
        await repository.storePickedImage(picked);
      }
      if (!context.mounted) return;
      setState(() {
        _avatarPathFuture = repository.getAvatarPath();
      });
    } on ProfileAvatarException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('จัดการรูปโปรไฟล์ไม่สำเร็จ')),
        );
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
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

class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('เปลี่ยนชื่อที่แสดง'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 40,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'ชื่อของคุณ',
        helperText: 'ชื่อนี้จะแสดงกับผู้ใช้ RELIO ที่อยู่ใกล้เคียง',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('บันทึก'),
      ),
    ],
  );
}
