import 'cloud_data_source.dart';
import 'cloud_models.dart';

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
  CloudAuthService(this.source, {this.rebind});
  final Future<void> Function()? rebind;
  final CloudDataSource source;
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
    await rebind?.call();
    return result;
  }

  @override
  Future<CloudIdentity> signIn({
    required String email,
    required String password,
  }) async {
    final result = await source.signIn(email: email, password: password);
    await rebind?.call();
    return result;
  }

  @override
  Future<void> signOut() async {
    await source.signOut();
    await rebind?.call();
  }

  @override
  Future<CloudIdentity?> restoreSession() async {
    final result = await source.restoreSession();
    await rebind?.call();
    return result;
  }

  @override
  Future<void> deleteAccount() => source.deleteMyAccount();
}
