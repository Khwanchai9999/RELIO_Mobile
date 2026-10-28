import 'package:shared_preferences/shared_preferences.dart';

/// เก็บเฉพาะ guard ไม่เก็บ token; session จริงยังให้ Supabase SDK ตรวจสอบ
class PasswordRecoveryGuard {
  PasswordRecoveryGuard(this.preferences);
  final SharedPreferences preferences;
  static const _key = 'relio_auth_password_recovery_pending';
  bool get pending => preferences.getBool(_key) ?? false;
  Future<void> setPending(bool pending) async {
    final saved = pending
        ? await preferences.setBool(_key, true)
        : await preferences.remove(_key);
    if (!saved) throw StateError('Recovery guard could not be persisted');
  }
}
