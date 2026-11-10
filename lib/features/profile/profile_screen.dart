// หน้าโปรไฟล์สำหรับแก้ข้อมูลของ principal ปัจจุบันและจัดการรูปประจำตัวผ่าน repository
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/connectivity/runtime_connectivity.dart';
import '../../core/repositories/principal_profile_repository.dart';
import '../../core/relio_dependencies.dart';
import '../../core/repositories/profile_avatar_repository.dart';
import '../../shared/widgets/relio_widgets.dart';

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Avatar Action)
enum _AvatarAction { camera, gallery, remove }

// แสดงและแก้ Profile ของ principal ที่เลือก โดย Repository เป็นเจ้าของข้อมูล local
// การเปลี่ยนบัญชี Cloud ไม่เปลี่ยน device identity หรือข้อมูล Guest ที่บันทึกไว้
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Profile Screen State)
class _ProfileScreenState extends State<ProfileScreen> {
  Future<String>? _localDisplayNameFuture;
  Future<bool>? _usingDefaultNameFuture;
  Future<String?>? _avatarPathFuture;
  PrincipalProfileRepository? _profiles;
  RelioDependencies? _authDependencies;
  StreamSubscription<void>? _authSubscription;
  int _profileRevision = 0;
  bool _busy = false;
  bool _avatarBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = RelioDependencyScope.of(context);
    if (_authDependencies != dependencies) {
      _authSubscription?.cancel();
      _authDependencies = dependencies;
      _authSubscription = dependencies.localAuthChanges.listen((_) {
        if (mounted) setState(() {});
      });
    }
    if (_profiles != dependencies.repositories.profiles) {
      _profiles?.removeListener(_refreshProfile);
      _profiles = dependencies.repositories.profiles;
      _profiles!.addListener(_refreshProfile);
    }
    _localDisplayNameFuture ??= dependencies.identity.getDisplayName();
    _usingDefaultNameFuture ??= dependencies.identity
        .isUsingDefaultDisplayName();
    _avatarPathFuture ??= dependencies.profileAvatarRepository.getAvatarPath();
  }

  void _refreshProfile() {
    if (!mounted) return;
    final dependencies = RelioDependencyScope.of(context);
    setState(() {
      _profileRevision++;
      _localDisplayNameFuture = dependencies.identity.getDisplayName();
      _usingDefaultNameFuture = dependencies.identity
          .isUsingDefaultDisplayName();
      _avatarPathFuture = dependencies.profileAvatarRepository.getAvatarPath();
    });
  }

  @override
  void dispose() {
    _profiles?.removeListener(_refreshProfile);
    _authSubscription?.cancel();
    super.dispose();
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
            tooltip: 'ตั้งค่า',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
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
                          FutureBuilder<String>(
                            key: ValueKey('avatar-name:$_profileRevision'),
                            future: _localDisplayNameFuture,
                            builder: (context, nameSnapshot) =>
                                FutureBuilder<String?>(
                                  key: ValueKey('avatar:$_profileRevision'),
                                  future: _avatarPathFuture,
                                  builder: (context, avatarSnapshot) =>
                                      RelioPrincipalAvatar(
                                        name: nameSnapshot.data ?? '',
                                        imagePath: avatarSnapshot.data,
                                        size: 72,
                                      ),
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
                          key: ValueKey('default:$_profileRevision'),
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
                          identity?.email ??
                              (dependencies.hasOfflineAuthenticatedPrincipal
                                  ? 'บัญชีที่เข้าสู่ระบบไว้ • ออฟไลน์'
                                  : 'ใช้งานแบบออฟไลน์'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _editDisplayName(context),
                    tooltip: 'แก้ไขชื่อ',
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'บัญชีและแอป',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.medical_information_outlined,
            title: 'ข้อมูลฉุกเฉิน',
            subtitle: 'บันทึกผู้ติดต่อฉุกเฉินไว้ในเครื่อง',
            onTap: () => context.push('/profile/emergency'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.dark_mode_outlined,
            title: 'ธีมแอป',
            subtitle: 'สว่าง / มืด / ตามระบบ',
            onTap: () => context.push('/settings/theme'),
          ),
          const SizedBox(height: 8),
          RelioSettingTile(
            icon: Icons.settings_outlined,
            title: 'การตั้งค่า',
            subtitle: 'การแจ้งเตือนและข้อมูลแอป',
            onTap: () => context.push('/settings'),
          ),
          const SizedBox(height: 8),
          if (identity != null && !dependencies.isGuestCloudSession) ...[
            ExpansionTile(
              title: const Text('รายละเอียดบัญชี'),
              children: [
                RelioSettingTile(
                  icon: Icons.content_copy_rounded,
                  title: 'Cloud Account ID',
                  subtitle: 'แตะเพื่อคัดลอกและแชร์กับผู้ติดต่อที่เชื่อถือได้',
                  onTap: () async {
                    if (dependencies.repositories.ownerContext
                            .capture()
                            .userId !=
                        identity.userId) {
                      return;
                    }
                    await Clipboard.setData(
                      ClipboardData(text: identity.userId),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('คัดลอก Cloud Account ID แล้ว'),
                        ),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                RelioSettingTile(
                  icon: Icons.mark_email_unread_outlined,
                  title: 'เปลี่ยนอีเมลบัญชี',
                  subtitle: identity.pendingEmail != null
                      ? 'รอยืนยัน ${identity.pendingEmail}'
                      : identity.email,
                  onTap: _busy ? null : () => _manageAccountEmail(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (!dependencies.hasAuthenticatedPrincipal)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: FilledButton.icon(
                key: const ValueKey('guest-login'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF15803D),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => context.go('/login'),
                icon: const Icon(Icons.login_rounded),
                label: const Text('เข้าสู่ระบบ'),
              ),
            ),
          if (!dependencies.hasAuthenticatedPrincipal)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                key: const ValueKey('guest-exit-offline'),
                onPressed: _busy ? null : () => _confirmGuestExit(context),
                icon: const Icon(Icons.exit_to_app_rounded),
                label: const Text('ออกจากโหมดออฟไลน์'),
              ),
            ),
          if (dependencies.hasAuthenticatedPrincipal)
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

  Future<void> _manageAccountEmail(BuildContext context) async {
    final dependencies = RelioDependencyScope.of(context);
    try {
      if (!dependencies.cloudDataSource.configuration.isConfigured) {
        throw const CloudException(
          'ยังไม่ได้ตั้งค่า Supabase',
          code: 'notConfigured',
        );
      }
      if (!dependencies.internetSimulator.internetAvailable) {
        throw const CloudException(
          'เปลี่ยนอีเมลต้องใช้อินเทอร์เน็ต',
          code: 'offline',
        );
      }
      RuntimeConnectivitySnapshot runtime;
      try {
        runtime = await dependencies.connectivityStatus
            .readRuntimeSnapshot()
            .timeout(const Duration(seconds: 2));
      } on TimeoutException {
        throw const CloudException(
          'ตรวจสอบอินเทอร์เน็ตไม่สำเร็จ',
          code: 'offline',
        );
      }
      if (runtime.hasInternetRoute == false ||
          runtime.internetValidated == false) {
        throw const CloudException(
          'เปลี่ยนอีเมลต้องใช้อินเทอร์เน็ต',
          code: 'offline',
        );
      }

      if (!context.mounted) return;
      final identity = dependencies.authService.identity;
      final changed = await showDialog<bool>(
        context: context,
        builder: (_) => _AccountEmailDialog(
          dependencies: dependencies,
          initialEmail: identity?.pendingEmail ?? identity?.email ?? '',
          currentEmail: identity?.email ?? '',
          startWithVerification: identity?.pendingEmail != null,
        ),
      );
      if (changed == true && context.mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปเดตบัญชีด้วยอีเมลแล้ว')),
        );
      }
    } on CloudException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('จัดการอีเมลบัญชีไม่สำเร็จ')),
        );
      }
    }
  }

  Future<void> _confirmGuestExit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ออกจากโหมดออฟไลน์?'),
        content: const Text(
          'คุณจะกลับไปหน้าเริ่มต้น โดยข้อมูลที่บันทึกไว้ในเครื่องจะไม่ถูกลบ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ออกจากโหมดออฟไลน์'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted || _busy) return;

    setState(() => _busy = true);
    try {
      final dependencies = RelioDependencyScope.of(context);
      final deviceId = await dependencies.identity.getDeviceId();
      final activeSos = await dependencies.repositories.sos.readActive(
        ownerDeviceId: deviceId,
      );
      if (!context.mounted) return;
      if (activeSos != null) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('ยังมี SOS กำลังใช้งาน'),
            content: const Text(
              'ปิดหรือจัดการ SOS ก่อนออกจากโหมดออฟไลน์ ข้อมูลฉุกเฉินจะยังคงอยู่ในเครื่อง',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ปิด'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  context.go('/sos/active');
                },
                child: const Text('ไปที่ SOS'),
              ),
            ],
          ),
        );
        return;
      }
      final exited = await dependencies.exitGuestMode();
      if (!context.mounted) return;
      if (!exited) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('ยังเชื่อมต่ออุปกรณ์อยู่'),
            content: const Text(
              'จบการเชื่อมต่อกับอุปกรณ์ใกล้เคียงก่อนออกจากโหมดออฟไลน์ เพื่อไม่ให้การสื่อสารถูกขัดจังหวะ',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ปิด'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  context.go('/nearby');
                },
                child: const Text('ไปที่ Nearby'),
              ),
            ],
          ),
        );
        return;
      }
      // Guest ไม่มี Cloud session ให้ sign out; กลับ Welcome โดยคง local data และ identity ไว้
      context.go('/welcome');
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ตรวจสอบสถานะ SOS ไม่สำเร็จ จึงยังออกจากโหมดออฟไลน์ไม่ได้',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _memberName(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall;
    return FutureBuilder<String>(
      key: ValueKey('name:$_profileRevision'),
      future: _localDisplayNameFuture,
      builder: (context, snapshot) => Text(
        snapshot.data ?? 'ผู้ใช้ RELIO',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }

  Future<void> _editDisplayName(BuildContext context) =>
      RelioDependencyScope.of(context).repositories.ownerContext
          .run(() => _editDisplayNameOwned(context))
          .catchError((Object _) {});

  Future<void> _editDisplayNameOwned(BuildContext context) async {
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

  Future<void> _editAvatar(BuildContext context) =>
      RelioDependencyScope.of(context).repositories.ownerContext
          .run(() => _editAvatarOwned(context))
          .catchError((Object _) {});

  Future<void> _editAvatarOwned(BuildContext context) async {
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
    final owners = RelioDependencyScope.of(context).repositories.ownerContext;
    final owner = owners.capture();
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
    if (confirmed != true ||
        !context.mounted ||
        _busy ||
        !owners.isCurrent(owner)) {
      return;
    }

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
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Account Email Dialog)
class _AccountEmailDialog extends StatefulWidget {
  const _AccountEmailDialog({
    required this.dependencies,
    required this.initialEmail,
    required this.currentEmail,
    required this.startWithVerification,
  });

  final RelioDependencies dependencies;
  final String initialEmail;
  final String currentEmail;
  final bool startWithVerification;

  @override
  State<_AccountEmailDialog> createState() => _AccountEmailDialogState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Account Email Dialog State)
class _AccountEmailDialogState extends State<_AccountEmailDialog> {
  late final TextEditingController _emailController;
  final _currentEmailCodeController = TextEditingController();
  final _newEmailCodeController = TextEditingController();
  late int _stage;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _stage = widget.startWithVerification ? 1 : 0;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _currentEmailCodeController.dispose();
    _newEmailCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) return;
    final dependencies = widget.dependencies;
    setState(() => _working = true);
    try {
      if (_stage == 0) {
        await dependencies.authService.requestEmailChange(
          email: _emailController.text,
        );
        if (mounted) setState(() => _stage = 1);
        return;
      }
      if (_stage == 1) {
        final currentToken = _currentEmailCodeController.text.trim();
        final newToken = _newEmailCodeController.text.trim();
        if (currentToken.isEmpty && newToken.isEmpty) {
          throw const CloudException(
            'กรุณากรอกรหัสยืนยันจากอีเมล',
            code: 'invalidInput',
          );
        }
        if (currentToken.isNotEmpty && widget.currentEmail.isNotEmpty) {
          final result = await dependencies.authService.verifyEmailChange(
            email: widget.currentEmail,
            token: currentToken,
          );
          if (result.verified) {
            _finishEmailVerification();
            return;
          }
          _currentEmailCodeController.clear();
        }
        if (newToken.isNotEmpty) {
          final result = await dependencies.authService.verifyEmailChange(
            email: _emailController.text,
            token: newToken,
          );
          if (result.verified) {
            _finishEmailVerification();
            return;
          }
          _newEmailCodeController.clear();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'ยืนยันรหัสที่ได้รับแล้ว หากมีรหัสอีกฉบับให้กรอกจากอีกอีเมลเพื่อดำเนินการต่อ',
              ),
            ),
          );
        }
        return;
      }
    } on CloudException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ทำรายการไม่สำเร็จ กรุณาลองใหม่')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _finishEmailVerification() {
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final title = _stage == 0 ? 'เปลี่ยนอีเมลบัญชี' : 'ยืนยันอีเมล';
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_stage == 0)
              TextField(
                controller: _emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'อีเมลใหม่',
                  helperText: 'ระบบจะส่งรหัสยืนยันไปยังอีเมลนี้',
                ),
              ),
            if (_stage == 1) ...[
              Text(_emailController.text),
              const SizedBox(height: 12),
              if (widget.currentEmail.isNotEmpty) ...[
                TextField(
                  controller: _currentEmailCodeController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'รหัสจากอีเมลปัจจุบัน',
                    helperText: widget.currentEmail,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _newEmailCodeController,
                autofocus: widget.currentEmail.isEmpty,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'รหัสจากอีเมลใหม่',
                  helperText: 'หากได้รับรหัสเดียว ให้กรอกรหัสใหม่ที่นี่',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _working ? null : _submit,
          child: _working
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_stage == 0 ? 'ส่งรหัสยืนยัน' : 'ยืนยันอีเมล'),
        ),
      ],
    );
  }
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Display Name Dialog)
class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Display Name Dialog State)
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
