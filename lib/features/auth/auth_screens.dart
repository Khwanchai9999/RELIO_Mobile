import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';
import 'register_validation.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final dependencies = RelioDependencyScope.of(context);
      // ส่งข้อมูลเข้าสู่ AuthService; หน้าจอไม่จัดการ token หรือ SDK เอง
      await dependencies.authService.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
      unawaited(dependencies.syncPushRegistration());
      if (mounted) {
        try {
          final snapshot = await dependencies.permissionService
              .readNearbyPermissions();
          if (mounted) {
            context.go(snapshot.allGranted ? '/home' : '/permissions');
          }
        } on Object {
          // หากอ่านสถานะ native ไม่ได้ ให้เปิดหน้าที่ตรวจ/ขอสิทธิ์แทนการเดาว่าครบแล้ว
          if (mounted) {
            context.go('/permissions');
          }
        }
      }
    } on CloudException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'เข้าสู่ระบบ',
      onBack: () => context.go('/welcome'),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _AuthIntro(
              title: 'ยินดีต้อนรับกลับ',
              subtitle: 'เข้าสู่ระบบเพื่อใช้งาน RELIO',
            ),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'อีเมล',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: RegisterValidation.emailError,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'รหัสผ่าน',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'กรุณากรอกรหัสผ่าน'
                  : value.length < 6
                  ? 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร'
                  : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {},
                child: const Text('ลืมรหัสผ่าน?'),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: Text(_busy ? 'กำลังเข้าสู่ระบบ...' : 'เข้าสู่ระบบ'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/home'),
              child: const Text('ใช้งานแบบออฟไลน์'),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => context.push('/register'),
              child: const Text('ยังไม่มีบัญชี? สร้างบัญชีใหม่'),
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _agreed = false;
  bool _busy = false;
  bool _showPassword = false;
  bool _showConfirmation = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final dependencies = RelioDependencyScope.of(context);
      await dependencies.authService.register(
        email: RegisterValidation.normalizeEmail(_email.text),
        password: _password.text,
        displayName: _name.text.trim(),
      );
      unawaited(dependencies.syncPushRegistration());
      if (mounted) context.go('/permissions');
    } on CloudException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'สร้างบัญชีใหม่',
      onBack: () => context.go('/welcome'),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _AuthIntro(
              title: 'เริ่มต้นกับ RELIO',
              subtitle: 'สร้างบัญชีสำหรับการสื่อสารที่ปลอดภัย',
            ),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'ชื่อ-นามสกุล',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'กรุณากรอกชื่อ'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'อีเมล',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: RegisterValidation.emailError,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'รหัสผ่าน',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() {
                    _showPassword = !_showPassword;
                  }),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (value) =>
                  RegisterValidation.passwordError(value ?? ''),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _PasswordRequirement(
                    label: 'อย่างน้อย 8 ตัวอักษร',
                    satisfied: RegisterValidation.hasMinimumLength(
                      _password.text,
                    ),
                  ),
                  _PasswordRequirement(
                    label: 'มีตัวพิมพ์ใหญ่',
                    satisfied: RegisterValidation.hasUppercase(_password.text),
                  ),
                  _PasswordRequirement(
                    label: 'มีตัวพิมพ์เล็ก',
                    satisfied: RegisterValidation.hasLowercase(_password.text),
                  ),
                  _PasswordRequirement(
                    label: 'มีตัวเลข',
                    satisfied: RegisterValidation.hasNumber(_password.text),
                  ),
                  _PasswordRequirement(
                    label: 'มีอักขระพิเศษ',
                    satisfied: RegisterValidation.hasSpecialCharacter(
                      _password.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmation,
              obscureText: !_showConfirmation,
              decoration: InputDecoration(
                labelText: 'ยืนยันรหัสผ่าน',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() {
                    _showConfirmation = !_showConfirmation;
                  }),
                  icon: Icon(
                    _showConfirmation
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (value) => RegisterValidation.confirmationError(
                _password.text,
                value ?? '',
              ),
            ),
            const SizedBox(height: 14),
            CheckboxListTile(
              value: _agreed,
              onChanged: (value) => setState(() => _agreed = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'ฉันยอมรับนโยบายความเป็นส่วนตัวและเงื่อนไขการใช้งานของ RELIO',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: !_agreed || _busy ? null : _register,
              child: Text(_busy ? 'กำลังสร้างบัญชี...' : 'สร้างบัญชี'),
            ),
            TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('มีบัญชีแล้ว? เข้าสู่ระบบ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordRequirement extends StatelessWidget {
  const _PasswordRequirement({required this.label, required this.satisfied});

  final String label;
  final bool satisfied;

  @override
  Widget build(BuildContext context) {
    final color = satisfied
        ? Theme.of(context).colorScheme.primary
        : RelioColors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          satisfied ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  static const permissions = [
    (
      Icons.radar_rounded,
      'อุปกรณ์ใกล้เคียง',
      'ค้นหาและสื่อสารกับผู้ใช้ RELIO ใกล้คุณ',
    ),
    (
      Icons.bluetooth_rounded,
      'Bluetooth',
      'เชื่อมต่ออุปกรณ์ใกล้เคียงโดยไม่ใช้อินเทอร์เน็ต',
    ),
    (Icons.wifi_rounded, 'Wi-Fi', 'ช่วยเพิ่มระยะการสื่อสารผ่าน Wi-Fi Direct'),
    (
      Icons.location_on_outlined,
      'ตำแหน่ง',
      'แชร์ตำแหน่งล่าสุดเมื่อเกิดเหตุฉุกเฉิน',
    ),
    (
      Icons.photo_library_outlined,
      'รูปภาพ / วิดีโอ',
      'แนบสื่อเพื่อแชร์ข้อมูลฉุกเฉิน',
    ),
    (
      Icons.notifications_none_rounded,
      'การแจ้งเตือน',
      'รับแจ้งเตือนเมื่อมี SOS หรือข้อความใหม่',
    ),
  ];

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _startedReading = false;
  bool _checking = true;
  bool _requesting = false;
  bool? _allGranted;
  bool _permissionStateKnown = false;
  String? _statusMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startedReading) return;
    _startedReading = true;
    unawaited(_readPermissions());
  }

  Future<void> _readPermissions() async {
    try {
      final snapshot = await RelioDependencyScope.of(
        context,
      ).permissionService.readNearbyPermissions();
      if (!mounted) return;
      setState(() {
        _allGranted = snapshot.allGranted;
        _permissionStateKnown = snapshot.isKnown;
        _statusMessage = snapshot.isKnown
            ? null
            : 'อ่านเวอร์ชัน Android ไม่ได้ จึงตรวจสอบสิทธิ์ Nearby ไม่สำเร็จ';
        _checking = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _allGranted = null;
        _statusMessage = 'ตรวจสอบสิทธิ์ไม่สำเร็จ กรุณาลองอีกครั้ง';
        _checking = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    if (_checking || _requesting) return;
    setState(() {
      _requesting = true;
      _statusMessage = null;
    });
    try {
      final snapshot = await RelioDependencyScope.of(
        context,
      ).permissionService.requestNearbyPermissions();
      if (!mounted) return;
      if (snapshot.allGranted) {
        context.go('/home');
        return;
      }
      setState(() {
        _permissionStateKnown = snapshot.isKnown;
        _allGranted = snapshot.isKnown ? false : null;
        _statusMessage = snapshot.isKnown
            ? 'ยังไม่ได้รับอนุญาตสิทธิ์ Nearby ที่จำเป็นบางรายการ คุณลองอีกครั้งหรือข้ามไปก่อนได้'
            : 'อ่านเวอร์ชัน Android ไม่ได้ จึงตรวจสอบสิทธิ์ Nearby ไม่สำเร็จ';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'ขอสิทธิ์ไม่สำเร็จ กรุณาลองอีกครั้ง';
      });
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RelioSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: [
                  const Icon(
                    Icons.radar_rounded,
                    size: 68,
                    color: RelioColors.primary,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'อนุญาตการเข้าถึง',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'หน้านี้ตรวจและขอสิทธิ์ Android ที่จำเป็นต่อ Nearby ส่วนตำแหน่ง รูปภาพ/วิดีโอ และการแจ้งเตือนจะใช้ตามฟีเจอร์และสิทธิ์ของระบบ',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 22),
                  ...PermissionsScreen.permissions.map(
                    (permission) => Card(
                      child: ListTile(
                        leading: Icon(
                          permission.$1,
                          color: RelioColors.primary,
                        ),
                        title: Text(permission.$2),
                        subtitle: Text(permission.$3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_checking)
                    const Text('กำลังตรวจสอบสิทธิ์ Nearby...')
                  else if (_statusMessage != null)
                    Text(
                      _statusMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else if (_permissionStateKnown)
                    Text(
                      _allGranted == true
                          ? 'สิทธิ์ Nearby ที่จำเป็นได้รับอนุญาตแล้ว'
                          : 'ยังมีสิทธิ์ Nearby ที่จำเป็นซึ่งไม่ได้รับอนุญาต',
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _checking || _requesting
                        ? null
                        : _requestPermissions,
                    child: Text(
                      _requesting ? 'กำลังขอสิทธิ์...' : 'อนุญาตทั้งหมด',
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('ข้ามขั้นตอนนี้'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'คุณยังเข้าแอปได้โดยข้าม แต่ Nearby อาจใช้งานไม่ได้จนกว่าจะอนุญาตสิทธิ์ที่จำเป็น',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.onBack,
    required this.child,
    super.key,
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RelioAppBar(title: title, onBack: onBack),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthIntro extends StatelessWidget {
  const _AuthIntro({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: RelioColors.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Center(
              child: Text(
                'R',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
