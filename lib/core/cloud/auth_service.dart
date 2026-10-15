import 'cloud_data_source.dart';
import 'cloud_models.dart';
import '../identity/owner_context.dart';

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
  Future<void> signOut();
  Future<CloudIdentity?> restoreSession();
  Future<void> deleteAccount();
}

// ให้ UI เรียก Auth ผ่าน interface เดียว โดยไม่ผูกกับ Supabase SDK
class CloudAuthService implements AuthService {
  CloudAuthService(
    this.source, {
    this.rebind,
    this.onAuthenticated,
    this.onSignOut,
  });
  final Future<void> Function()? rebind;
  final Future<void> Function(String userId)? onAuthenticated;
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
  Future<void> signOut() async {
    await onSignOut?.call();
    await source.signOut();
    await _rebind(null);
  }

  @override
  Future<CloudIdentity?> restoreSession() async {
    final result = await source.restoreSession();
    if (result != null) await onAuthenticated?.call(result.userId);
    await _rebind(result?.userId);
    return result;
  }

  @override
  Future<void> deleteAccount() => source.deleteMyAccount();
}
