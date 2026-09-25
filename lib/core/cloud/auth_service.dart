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
}

class CloudAuthService implements AuthService {
  CloudAuthService(this.source);
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
  }) => source.register(
    email: email,
    password: password,
    displayName: displayName,
  );
  @override
  Future<CloudIdentity> signIn({
    required String email,
    required String password,
  }) => source.signIn(email: email, password: password);
  @override
  Future<void> signOut() => source.signOut();
  @override
  Future<CloudIdentity?> restoreSession() => source.restoreSession();
}
