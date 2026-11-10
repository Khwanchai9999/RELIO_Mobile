// หน้าตั้งรหัสผ่านใหม่หลังยืนยัน recovery state จากระบบยืนยันตัวตน
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/cloud/cloud_models.dart';
import '../../core/relio_dependencies.dart';
import 'auth_screens.dart' show AuthScaffold;
import 'register_validation.dart';

// เปลี่ยนรหัสผ่านได้เมื่อ AuthService ยืนยัน recovery session แล้วเท่านั้น
// การเปิด route โดยไม่มี credential ที่ผ่านการตรวจไม่สร้างสิทธิ์แก้บัญชี
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

// รายละเอียดภายในสำหรับประกอบหน้าจอหรือจัดรูปข้อมูลของโมดูลนี้ (Reset Password Screen State)
class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await RelioDependencyScope.of(
        context,
      ).authService.completePasswordReset(password: _password.text);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ตั้งรหัสผ่านใหม่แล้ว')));
        context.go('/home');
      }
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

  Future<void> _cancel() async {
    if (_busy) return;
    final auth = RelioDependencyScope.of(context).authService;
    setState(() => _busy = true);
    try {
      if (auth.state == AuthState.passwordRecovery) await auth.signOut();
      if (mounted) context.go('/login');
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
    final auth = RelioDependencyScope.of(context).authService;
    return AuthScaffold(
      title: 'ตั้งรหัสผ่านใหม่',
      onBack: _cancel,
      child: StreamBuilder<AuthState>(
        stream: auth.watchState(),
        initialData: auth.state,
        builder: (context, snapshot) {
          if (snapshot.data != AuthState.passwordRecovery) {
            return Column(
              children: [
                const Text('กรุณาเปิดลิงก์กู้รหัสผ่านที่ยังไม่หมดอายุจากอีเมล'),
                TextButton(
                  onPressed: () => context.go('/forgot-password'),
                  child: const Text('ขอลิงก์ใหม่'),
                ),
              ],
            );
          }
          return Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ใช้รหัสผ่านอย่างน้อย 8 ตัว มีตัวพิมพ์ใหญ่ ตัวพิมพ์เล็ก ตัวเลข และอักขระพิเศษ',
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  maxLength: 256,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(labelText: 'รหัสผ่านใหม่'),
                  validator: (value) =>
                      RegisterValidation.passwordError(value ?? ''),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmation,
                  enabled: !_busy,
                  obscureText: true,
                  maxLength: 256,
                  decoration: const InputDecoration(
                    labelText: 'ยืนยันรหัสผ่านใหม่',
                  ),
                  validator: (value) => RegisterValidation.confirmationError(
                    _password.text,
                    value ?? '',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _complete,
                  child: Text(_busy ? 'กำลังบันทึก...' : 'บันทึกรหัสผ่านใหม่'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
