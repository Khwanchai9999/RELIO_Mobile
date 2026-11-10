// หน้าขอส่งลิงก์กู้คืนรหัสผ่าน และแสดงผลการส่งคำขอจาก AuthService
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/cloud/cloud_models.dart';
import '../../core/relio_dependencies.dart';
import 'auth_screens.dart' show AuthScaffold;
import 'register_validation.dart';

// รับคำขอกู้รหัสผ่านและส่งผ่าน AuthService โดยไม่เปิดเผยว่ามีอีเมลในระบบหรือไม่
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Forgot Password Screen State)
class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _requested = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await RelioDependencyScope.of(
        context,
      ).authService.requestPasswordReset(email: _email.text);
      if (mounted) setState(() => _requested = true);
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
  Widget build(BuildContext context) => AuthScaffold(
    title: 'ลืมรหัสผ่าน',
    onBack: () => context.go('/login'),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'กรอกอีเมลของบัญชีเพื่อขอลิงก์ตั้งรหัสผ่านใหม่ ต้องเชื่อมต่อ Internet',
          ),
          const SizedBox(height: 20),
          if (_requested) ...[
            Semantics(
              liveRegion: true,
              child: const Text(
                'ส่งคำขอแล้ว หากมีบัญชีและระบบส่งอีเมลได้ คุณจะได้รับลิงก์กู้รหัสผ่าน โปรดตรวจกล่องจดหมายและจดหมายขยะ แล้วเปิดลิงก์บนเครื่องนี้',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.go('/login'),
              child: const Text('กลับเข้าสู่ระบบ'),
            ),
          ] else ...[
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'อีเมล'),
              validator: RegisterValidation.emailError,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _request,
              child: Text(_busy ? 'กำลังส่งคำขอ...' : 'ขอลิงก์กู้รหัสผ่าน'),
            ),
          ],
        ],
      ),
    ),
  );
}
