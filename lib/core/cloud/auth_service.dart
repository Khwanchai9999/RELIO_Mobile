import 'cloud_data_source.dart';
import 'cloud_models.dart';
import '../identity/owner_context.dart';

// สัญญา Auth ที่หน้าจอและ SyncEngine ใช้ โดยไม่ผูกกับชนิดของ Supabase SDK
// guest/offline เป็นสถานะที่รองรับ และการ sign out ไม่ลบข้อมูล SQLite
abstract interface class AuthService {
  AuthState get state;
  CloudIdentity? get identity;
  Stream<AuthState> watchState();
  Future<CloudIdentity> register({
    required String email,
    required String password,
    String? displayName,
  });
  Future<CloudIdentity> signIn({
    required String email,
    required String password,
  });
  Future<CloudIdentity> signInAnonymously();
  Future<CloudIdentity> requestEmailChange({required String email});
  Future<CloudEmailChangeResult> verifyEmailChange({
    required String email,
    required String token,
  });
  Future<CloudIdentity> setAccountPassword({required String password});
  Future<void> signOut();
  Future<void> requestPasswordReset({required String email});
  Future<void> completePasswordReset({required String password});
  Future<CloudIdentity?> restoreSession();
  Future<void> deleteAccount();
}

// ให้ UI เรียก Auth ผ่าน interface เดียว โดยไม่ผูกกับ Supabase SDK
class CloudAuthService implements AuthService {
  CloudAuthService(
    this.source, {
    this.rebind,
    this.onAuthenticated,
    this.onRestored,
    this.onSignOut,
  });
  final Future<void> Function()? rebind;
  final Future<void> Function(String userId)? onAuthenticated;
  final Future<void> Function(String userId)? onRestored;
  final Future<void> Function()? onSignOut;
  final CloudDataSource source;

  Future<void> _rebind(String? expectedUserId) async {
    try {
      await rebind?.call();
    } on OwnerChangedException {
      // Auth event ซ้ำอาจยกเลิก profile refresh เดิม; listener โหลด owner ล่าสุดต่อได้
      // ยอมรับเฉพาะ session เดิมที่สำเร็จแล้ว ไม่กลบการสลับไปบัญชีอื่นจริง
      if (source.currentIdentity?.userId != expectedUserId) rethrow;
    }
    if (source.currentIdentity?.userId != expectedUserId) {
      throw const OwnerChangedException();
    }
  }

  @override
  AuthState get state => source.authState;
  @override
  CloudIdentity? get identity => source.currentIdentity;
  @override
  Stream<AuthState> watchState() => source.watchAuthState();
  @override
  Future<CloudIdentity> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final result = await source.register(
      email: email,
      password: password,
      displayName: displayName,
    );
    await onAuthenticated?.call(result.userId);
    await _rebind(source.currentIdentity?.userId);
    return result;
  }

  @override
  Future<CloudIdentity> signIn({
    required String email,
    required String password,
  }) async {
    final result = await source.signIn(email: email, password: password);
    await onAuthenticated?.call(result.userId);
    await _rebind(result.userId);
    return result;
  }

  @override
  Future<CloudIdentity> signInAnonymously() => source.signInAnonymously();

  @override
  Future<CloudIdentity> requestEmailChange({required String email}) =>
      source.requestEmailChange(email: email.trim());

  @override
  Future<CloudEmailChangeResult> verifyEmailChange({
    required String email,
    required String token,
  }) => source.verifyEmailChange(email: email.trim(), token: token.trim());

  @override
  Future<CloudIdentity> setAccountPassword({required String password}) =>
      source.setAccountPassword(password: password);

  @override
  Future<void> signOut() async {
    await onSignOut?.call();
    await source.signOut();
    await _rebind(null);
  }

  @override
  Future<CloudIdentity?> restoreSession() async {
    final result = await source.restoreSession();
    if (result != null && !result.isAnonymous) {
      await onRestored?.call(result.userId);
    }
    await _rebind(result?.userId);
    return result;
  }

  @override
  Future<void> deleteAccount() => source.deleteMyAccount();

  @override
  Future<void> requestPasswordReset({required String email}) =>
      source.requestPasswordReset(email: email.trim());

  @override
  Future<void> completePasswordReset({required String password}) async {
    final result = await source.completePasswordReset(password: password);
    await onAuthenticated?.call(result.userId);
    await _rebind(result.userId);
  }
}
