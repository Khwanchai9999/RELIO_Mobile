import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/relio_colors.dart';
import '../../app/theme/relio_spacing.dart';
import '../../core/cloud/cloud_models.dart';
import '../../core/relio_dependencies.dart';
import '../../shared/widgets/relio_widgets.dart';

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
      await RelioDependencyScope.of(
        context,
      ).authService.signIn(email: _email.text.trim(), password: _password.text);
      if (mounted) context.go('/permissions');
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
              validator: (value) => value == null || !value.contains('@')
                  ? 'กรุณากรอกอีเมล'
                  : null,
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
              validator: (value) => value == null || value.length < 6
                  ? 'กรุณากรอกรหัสผ่านอย่างน้อย 6 ตัวอักษร'
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
      await RelioDependencyScope.of(context).authService.register(
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text.trim(),
      );
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
              validator: (value) => value == null || !value.contains('@')
                  ? 'กรุณากรอกอีเมล'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'รหัสผ่าน',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) => value == null || value.length < 8
                  ? 'อย่างน้อย 8 ตัวอักษร'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmation,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'ยืนยันรหัสผ่าน',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) =>
                  value != _password.text ? 'รหัสผ่านไม่ตรงกัน' : null,
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

class PermissionsScreen extends StatelessWidget {
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
                    'RELIO ต้องการสิทธิ์เหล่านี้เพื่อให้ทำงานได้เต็มประสิทธิภาพ คุณสามารถเปลี่ยนแปลงได้ในการตั้งค่า',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 22),
                  ...permissions.map(
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
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('อนุญาตทั้งหมด'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('ข้ามขั้นตอนนี้'),
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
