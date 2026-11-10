import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:shared_preferences/shared_preferences.dart';

import '../media/media_storage_service.dart';
import '../connectivity/qa_internet_simulator.dart';
import 'cloud_data_source.dart';
import 'cloud_error_mapper.dart';
import 'cloud_models.dart';
import 'cloud_storage_policy.dart';
import 'password_recovery_callback.dart';
import 'password_recovery_guard.dart';

class SupabaseCloudDataSource implements CloudDataSource {
  SupabaseCloudDataSource({
    SupabaseConfig? configuration,
    this.internetSimulator,
  }) : configuration = configuration ?? const SupabaseConfig.fromEnvironment() {
    internetSimulator?.addListener(_onInternetSimulatorChanged);
  }

  @override
  final SupabaseConfig configuration;
  final QaInternetSimulator? internetSimulator;
  SupabaseClient? _client;
  StreamSubscription<dynamic>? _authSubscription;
  CloudState _state = CloudState.notConfigured;
  AuthState _authState = AuthState.guest;
  CloudIdentity? _identity;
  Future<void>? _initialization;
  bool _initialized = false;
  bool _passwordRecovery = false;
  PasswordRecoveryGuard? _recoveryGuard;
  int _authEventGeneration = 0;
  final _cloudStates = StreamController<CloudState>.broadcast();
  final _authStates = StreamController<AuthState>.broadcast();

  @override
  CloudState get cloudState =>
      _isInternetUnavailable ? CloudState.offline : _state;
  @override
  AuthState get authState => _authState;
  @override
  CloudIdentity? get currentIdentity => _identity;
  @override
  Stream<CloudState> watchCloudState() => _cloudStates.stream;
  @override
  Stream<AuthState> watchAuthState() => _authStates.stream;

  @override
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initialization ??= _initialize().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initialize() async {
    if (_isInternetUnavailable) {
      _state = CloudState.offline;
      return;
    }
    if (!configuration.isConfigured) {
      _state = CloudState.notConfigured;
      _initialized = true;
      return;
    }
    try {
      _recoveryGuard ??= PasswordRecoveryGuard(
        await SharedPreferences.getInstance(),
      );
      await Supabase.initialize(
        url: configuration.url.trim(),
        publishableKey: configuration.anonKey.trim(),
        debug: false,
        authOptions: FlutterAuthClientOptions(
          detectSessionInUriPredicate: PasswordRecoveryCallback.accepts,
        ),
      );
      _client = Supabase.instance.client;
      final initialAuth = await _client!.auth.onAuthStateChange.first;
      _passwordRecovery =
          initialAuth.event == AuthChangeEvent.passwordRecovery ||
          _recoveryGuard!.pending;
      if (_passwordRecovery) await _recoveryGuard!.setPending(true);
      _authSubscription ??= _client!.auth.onAuthStateChange.listen(
        (event) async {
          final generation = ++_authEventGeneration;
          try {
            if (event.event == AuthChangeEvent.passwordRecovery) {
              _passwordRecovery = true;
              _authState = AuthState.passwordRecovery;
              await _recoveryGuard!.setPending(true);
            } else if (event.event == AuthChangeEvent.signedOut) {
              _passwordRecovery = false;
              _authState = AuthState.guest;
              await _recoveryGuard!.setPending(false);
            }
            if (generation != _authEventGeneration) return;
            _identity = _mapUser(event.session?.user);
            _authState = _passwordRecovery && _identity != null
                ? AuthState.passwordRecovery
                : _identity == null
                ? AuthState.guest
                : AuthState.authenticated;
            _state = _identity == null
                ? CloudState.signedOut
                : CloudState.ready;
            _authStates.add(_authState);
            _cloudStates.add(_state);
          } on Object {
            _authState = AuthState.guest;
            _state = CloudState.error;
            _authStates.add(_authState);
            _cloudStates.add(_state);
          }
        },
        onError: (Object error) {
          // SDK ตรวจ token/PKCE; ไม่ส่ง URL หรือ token ไป diagnostics
          if (!_cloudStates.isClosed) {
            _state = CloudState.error;
            _cloudStates.add(_state);
          }
        },
      );
      _identity = _mapUser(_client!.auth.currentUser);
      _authState = _passwordRecovery && _identity != null
          ? AuthState.passwordRecovery
          : _identity == null
          ? AuthState.guest
          : AuthState.authenticated;
      _state = _identity == null ? CloudState.signedOut : CloudState.ready;
      _authStates.add(_authState);
      _cloudStates.add(_state);
      _initialized = true;
    } catch (error) {
      _state = CloudState.error;
      _cloudStates.add(_state);
      throw CloudErrorMapper.map(error, fallbackCode: 'initialization');
    }
  }

  Future<SupabaseClient> _ready() async {
    if (_isInternetUnavailable) {
      throw const CloudException(
        'Cloud ถูกบล็อกโดย QA Offline Simulator',
        code: 'offline',
      );
    }
    await initialize();
    if (!configuration.isConfigured || _client == null) {
      throw const CloudException(
        'ยังไม่ได้ตั้งค่า Supabase',
        code: 'notConfigured',
      );
    }
    return _client!;
  }

  Future<void> _clearRecoveryGuard() async {
    ++_authEventGeneration;
    await _recoveryGuard?.setPending(false);
    _passwordRecovery = false;
  }

  bool get _isInternetUnavailable =>
      internetSimulator?.internetAvailable == false;

  void _onInternetSimulatorChanged() {
    final client = _client;
    if (client != null) {
      if (_isInternetUnavailable) {
        client.auth.stopAutoRefresh();
      } else {
        client.auth.startAutoRefresh();
      }
    }
    if (_isInternetUnavailable) {
      _state = CloudState.offline;
    } else if (_initialized) {
      _state = _identity == null ? CloudState.signedOut : CloudState.ready;
    }
    _cloudStates.add(_state);
  }

  void _requireAuth() {
    if (_identity == null || _authState != AuthState.authenticated) {
      throw const CloudException(
        'ต้องเข้าสู่ระบบก่อนใช้งานคลาวด์',
        code: 'signedOut',
      );
    }
  }

  CloudIdentity? _mapUser(User? user) => user == null
      ? null
      : CloudIdentity(
          userId: user.id,
          email: user.email ?? '',
          displayName: user.userMetadata?['display_name'] as String?,
          isAnonymous: user.isAnonymous,
          pendingEmail: user.newEmail,
        );

  void _publishAuthenticatedIdentity(CloudIdentity identity) {
    _identity = identity;
    _authState = AuthState.authenticated;
    _state = CloudState.ready;
    _authStates.add(_authState);
    _cloudStates.add(_state);
  }

  CloudException _failure(Object error, [String code = 'network']) =>
      CloudErrorMapper.map(error, fallbackCode: code);

  // ตรวจ owner ในเส้นทาง Storage ก่อนเรียก Cloud เพื่อไม่ให้ path ของไฟล์ชี้ข้ามบัญชี
  void _validateStoragePath(String storagePath, {String? ownerUserId}) {
    final expectedOwner = ownerUserId ?? _identity?.userId;
    if (_identity == null ||
        expectedOwner == null ||
        !CloudStoragePathPolicy.isOwnedBy(storagePath, expectedOwner)) {
      throw const CloudException(
        'เส้นทางไฟล์คลาวด์ไม่ปลอดภัย',
        code: 'invalidPath',
      );
    }
  }

  @override
  Future<CloudIdentity> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final client = await _ready();
      final response = await client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );
      final identity = _mapUser(response.user);
      if (identity == null) {
        throw const CloudException('สร้างบัญชีไม่สำเร็จ', code: 'auth');
      }
      if (response.session == null || client.auth.currentUser == null) {
        // การตอบกลับให้ยืนยันอีเมลยังไม่ใช่ session ที่ยืนยันตัวตนแล้ว
        // คิวจึงต้องอยู่ในเครื่องจนกว่าจะมี session จริง        // Do not treat an email-confirmation response as an authenticated
        // owner; queue rows must remain local until a real session exists.
        _identity = null;
        _authState = AuthState.guest;
        _state = CloudState.signedOut;
        _authStates.add(_authState);
        _cloudStates.add(_state);
        throw const CloudException(
          'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ',
          code: 'emailConfirmationRequired',
        );
      }
      _identity = identity;
      await _clearRecoveryGuard();
      _authState = AuthState.authenticated;
      _state = CloudState.ready;
      _authStates.add(_authState);
      _cloudStates.add(_state);
      await upsertProfile(displayName: displayName ?? email.split('@').first);
      return identity;
    } catch (error) {
      if (error is CloudException) rethrow;
      throw _failure(error, 'auth');
    }
  }

  @override
  Future<CloudIdentity> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final client = await _ready();
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final identity = _mapUser(response.user);
      if (identity == null) {
        throw const CloudException('เข้าสู่ระบบไม่สำเร็จ', code: 'auth');
      }
      _identity = identity;
      await _clearRecoveryGuard();
      _authState = AuthState.authenticated;
      _state = CloudState.ready;
      _authStates.add(_authState);
      _cloudStates.add(_state);
      return identity;
    } catch (error) {
      if (error is CloudException) rethrow;
      throw _failure(error, 'auth');
    }
  }

  @override
  Future<CloudIdentity> signInAnonymously() async {
    try {
      final client = await _ready();
      final current = _identity;
      if (current != null) return current;
      final response = await client.auth.signInAnonymously();
      final identity = _mapUser(response.user);
      if (identity == null || !identity.isAnonymous) {
        throw const CloudException(
          'สร้างบัญชี Guest บน Cloud ไม่สำเร็จ',
          code: 'auth',
        );
      }
      _publishAuthenticatedIdentity(identity);
      return identity;
    } catch (error) {
      if (error is CloudException) rethrow;
      throw _failure(error, 'auth');
    }
  }

  @override
  Future<CloudIdentity> requestEmailChange({required String email}) async {
    final client = await _ready();
    _requireAuth();
    final expectedUserId = _identity!.userId;
    final normalized = email.trim();
    if (normalized.isEmpty || normalized.length > 254) {
      throw const CloudException('อีเมลไม่ถูกต้อง', code: 'invalidEmail');
    }
    try {
      final response = await client.auth.updateUser(
        UserAttributes(email: normalized),
      );
      final identity = _mapUser(response.user);
      if (identity == null || identity.userId != expectedUserId) {
        throw const CloudException(
          'บัญชี Cloud เปลี่ยนระหว่างแก้ไขอีเมล',
          code: 'sessionExpired',
        );
      }
      _publishAuthenticatedIdentity(identity);
      return identity;
    } catch (error) {
      if (error is CloudException) rethrow;
      throw _failure(error, 'auth');
    }
  }

  @override
  Future<CloudEmailChangeResult> verifyEmailChange({
    required String email,
    required String token,
  }) async {
    final client = await _ready();
    _requireAuth();
    final expectedUserId = _identity!.userId;
    final expectedEmail = _identity!.pendingEmail;
    if (token.trim().length < 6 || token.trim().length > 12) {
      throw const CloudException('รหัสยืนยันไม่ถูกต้อง', code: 'invalidInput');
    }
    try {
      final response = await client.auth.verifyOTP(
        email: email.trim(),
        token: token.trim(),
        type: OtpType.emailChange,
      );
      final currentUser = client.auth.currentUser;
      if (currentUser?.id != expectedUserId) {
        throw const CloudException(
          'บัญชี Cloud เปลี่ยนระหว่างยืนยันอีเมล',
          code: 'sessionExpired',
        );
      }
      final identity = _mapUser(response.user ?? currentUser);
      if (identity == null || identity.userId != expectedUserId) {
        throw const CloudException('ยืนยันอีเมลไม่สำเร็จ', code: 'auth');
      }
      _publishAuthenticatedIdentity(identity);
      final verified =
          expectedEmail != null &&
          identity.email.toLowerCase() == expectedEmail.toLowerCase();
      return CloudEmailChangeResult(identity: identity, verified: verified);
    } catch (error) {
      if (error is CloudException) rethrow;
      throw _failure(error, 'auth');
    }
  }

  @override
  Future<CloudIdentity> setAccountPassword({required String password}) async {
    final client = await _ready();
    _requireAuth();
    final user = client.auth.currentUser;
    final expectedUserId = _identity!.userId;
    if (password.length < 8 || password.length > 256) {
      throw const CloudException(
        'รหัสผ่านไม่ตรงตามเงื่อนไข',
        code: 'weakPassword',
      );
    }
    if (user?.emailConfirmedAt == null || user?.newEmail != null) {
      throw const CloudException(
        'กรุณายืนยันอีเมลก่อนตั้งรหัสผ่าน',
        code: 'emailConfirmationRequired',
      );
    }
    try {
      final response = await client.auth.updateUser(
        UserAttributes(password: password),
      );
      final identity = _mapUser(response.user);
      if (identity == null || identity.userId != expectedUserId) {
        throw const CloudException(
          'บัญชี Cloud เปลี่ยนระหว่างตั้งรหัสผ่าน',
          code: 'sessionExpired',
        );
      }
      _publishAuthenticatedIdentity(identity);
      return identity;
    } catch (error) {
      if (error is CloudException) rethrow;
      throw _failure(error, 'auth');
    }
  }

  @override
  Future<void> signOut() async {
    if (!configuration.isConfigured || _identity == null) {
      _identity = null;
      await _clearRecoveryGuard();
      _authState = AuthState.guest;
      _state = configuration.isConfigured
          ? CloudState.signedOut
          : CloudState.notConfigured;
      _authStates.add(_authState);
      _cloudStates.add(_state);
      return;
    }
    try {
      await (await _ready()).auth.signOut();
    } catch (error) {
      if (error is CloudException) rethrow;
      throw _failure(error, 'auth');
    }
    _identity = null;
    await _clearRecoveryGuard();
    _authState = AuthState.guest;
    _state = CloudState.signedOut;
    _authStates.add(_authState);
    _cloudStates.add(_state);
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    try {
      await (await _ready()).auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: PasswordRecoveryCallback.redirectUri.toString(),
      );
    } catch (error) {
      throw _failure(error, 'passwordReset');
    }
  }

  @override
  Future<CloudIdentity> completePasswordReset({
    required String password,
  }) async {
    final client = await _ready();
    // การเปิด route เองหรือมี session ปกติไม่ใช่หลักฐาน recovery
    if (!_passwordRecovery ||
        _authState != AuthState.passwordRecovery ||
        client.auth.currentSession == null ||
        _identity == null) {
      throw const CloudException(
        'กรุณาเปิดลิงก์กู้รหัสผ่านที่ยังไม่หมดอายุจากอีเมล',
        code: 'recoveryRequired',
      );
    }
    if (password.length < 8 || password.length > 256) {
      throw const CloudException(
        'รหัสผ่านไม่ตรงตามเงื่อนไข',
        code: 'weakPassword',
      );
    }
    final expectedUserId = _identity!.userId;
    try {
      final response = await client.auth.updateUser(
        UserAttributes(password: password),
      );
      final result = _mapUser(response.user);
      if (result == null ||
          result.userId != expectedUserId ||
          !_passwordRecovery ||
          _identity?.userId != expectedUserId ||
          client.auth.currentUser?.id != expectedUserId) {
        throw const CloudException(
          'เซสชันกู้รหัสผ่านเปลี่ยนไป',
          code: 'recoveryRequired',
        );
      }
      await _clearRecoveryGuard();
      _identity = result;
      _authState = AuthState.authenticated;
      _state = CloudState.ready;
      _authStates.add(_authState);
      _cloudStates.add(_state);
      return result;
    } catch (error) {
      throw _failure(error, 'passwordReset');
    }
  }

  @override
  Future<CloudIdentity?> restoreSession() async {
    await initialize();
    return _identity;
  }

  @override
  Future<CloudProfile> fetchMyProfile() async {
    _requireAuth();
    try {
      final row = await (await _ready())
          .from('profiles')
          .select('id, display_name')
          .eq('id', _identity!.userId)
          .single();
      return CloudProfile(
        userId: row['id'] as String,
        displayName: row['display_name'] as String? ?? '',
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> upsertProfile({required String displayName}) async {
    _requireAuth();
    try {
      final client = await _ready();
      final profiles = client.from('profiles');
      final userId = _identity!.userId;
      final existing = await profiles
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      if (existing != null) {
        // นโยบาย RLS กำหนดให้ id ของ profile เปลี่ยนไม่ได้หลัง insert
        // จึงอัปเดตเฉพาะ display_name ที่ผู้ใช้แก้ไขได้        // The profiles RLS contract deliberately makes id immutable after
        // insert, so update only the user-editable display_name column.
        await profiles.update({'display_name': displayName}).eq('id', userId);
        return;
      }

      try {
        await profiles.insert({'id': userId, 'display_name': displayName});
      } on PostgrestException catch (error) {
        // Auth trigger อาจสร้าง profile ระหว่างการอ่านกับ insert
        // จัดการ race ด้วย update เฉพาะช่องที่อนุญาต ไม่ upsert id ที่ผู้ใช้ทั่วไปแก้ไม่ได้        // An Auth trigger may create the profile between the read and insert.
        // Resolve that race with the same narrowly scoped update, never upsert
        // id (which ordinary authenticated users are not allowed to update).
        if (error.code != '23505') rethrow;
        await profiles.update({'display_name': displayName}).eq('id', userId);
      }
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> upsertPrivateBackupRecord(
    CloudPrivateBackupRecord record,
  ) async {
    _requireAuth();
    if (!const {'conversation', 'message'}.contains(record.recordType) ||
        record.sourceId.isEmpty ||
        record.sourceId.length > 200 ||
        record.revision < 1) {
      throw const CloudException('ข้อมูลสำรองไม่ถูกต้อง', code: 'invalidInput');
    }
    try {
      await (await _ready()).from('private_backup_records').upsert({
        'owner_user_id': _identity!.userId,
        'record_type': record.recordType,
        'source_id': record.sourceId,
        'payload': record.payload,
        'revision': record.revision,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'owner_user_id,record_type,source_id');
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<CloudPrivateBackupRecord>> fetchPrivateBackupRecords({
    required String recordType,
    String? afterSourceId,
    int limit = 100,
  }) async {
    _requireAuth();
    if (!const {'conversation', 'message'}.contains(recordType) ||
        limit < 1 ||
        limit > 100) {
      throw const CloudException(
        'ขนาดหน้าข้อมูลไม่ถูกต้อง',
        code: 'invalidInput',
      );
    }
    try {
      var query = (await _ready())
          .from('private_backup_records')
          .select('record_type,source_id,payload,revision')
          .eq('owner_user_id', _identity!.userId)
          .eq('record_type', recordType);
      if (afterSourceId != null) query = query.gt('source_id', afterSourceId);
      final rows = await query.order('source_id').limit(limit);
      return (rows as List)
          .map((row) {
            final value = Map<String, dynamic>.from(row as Map);
            return CloudPrivateBackupRecord(
              recordType: value['record_type'] as String,
              sourceId: value['source_id'] as String,
              payload: Map<String, dynamic>.from(value['payload'] as Map),
              revision: value['revision'] as int? ?? 1,
            );
          })
          .toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deleteMyAccount() async {
    _requireAuth();
    try {
      final client = await _ready();
      await client.functions.invoke('delete-account');
      await client.auth.signOut(scope: SignOutScope.local);
      _identity = null;
      _authState = AuthState.guest;
      _state = CloudState.signedOut;
      _authStates.add(_authState);
      _cloudStates.add(_state);
    } catch (error) {
      if (error is CloudException) rethrow;
      throw _failure(error, 'delete');
    }
  }

  @override
  Future<void> upsertPushToken({
    required String deviceId,
    required String token,
  }) async {
    _requireAuth();
    if (deviceId.trim().isEmpty ||
        token.trim().isEmpty ||
        token.length > 4096) {
      throw const CloudException(
        'Push registration is invalid.',
        code: 'invalidInput',
      );
    }
    try {
      await (await _ready()).from('device_push_tokens').upsert({
        'owner_user_id': _identity!.userId,
        'device_id': deviceId,
        'token': token,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'owner_user_id,device_id');
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deletePushToken({required String deviceId}) async {
    _requireAuth();
    try {
      await (await _ready())
          .from('device_push_tokens')
          .delete()
          .eq('owner_user_id', _identity!.userId)
          .eq('device_id', deviceId);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> upsertMessage(CloudMessageDto message) async {
    _requireAuth();
    if (message.senderId != _identity!.userId) {
      throw const CloudException(
        'ข้อความไม่ได้เป็นของบัญชีปัจจุบัน',
        code: 'permissionDenied',
      );
    }
    try {
      final client = await _ready();
      final existing = await client
          .from('messages')
          .select()
          .eq('id', message.id)
          .maybeSingle();
      if (existing != null) {
        final saved = CloudMessageDto.fromJson(
          Map<String, dynamic>.from(existing),
        );
        if (saved.conversationId != message.conversationId ||
            saved.senderId != message.senderId ||
            saved.messageType != message.messageType ||
            saved.content != message.content) {
          throw const CloudException(
            'รหัสข้อความซ้ำกับข้อมูลคนละรายการ',
            code: 'invalidLocalData',
          );
        }
        return;
      }
      final data = message.toJson()
        ..remove('created_at')
        ..remove('updated_at')
        ..remove('delivery_status')
        ..remove('is_outgoing');
      await client.from('messages').insert(data);
    } catch (error) {
      if (error is CloudException) rethrow;
      // retry พร้อมกันอาจชนกันหลังตรวจการมีอยู่ของแถว
      // ยอมรับ conflict เฉพาะเมื่อ payload ที่บันทึกไว้ตรงกันทุกประการ      // Concurrent retries can race after the existence check. A conflict is
      // accepted only when the persisted immutable payload matches exactly.
      try {
        final existing = await (await _ready())
            .from('messages')
            .select()
            .eq('id', message.id)
            .maybeSingle();
        if (existing != null) {
          final saved = CloudMessageDto.fromJson(
            Map<String, dynamic>.from(existing),
          );
          if (saved.conversationId == message.conversationId &&
              saved.senderId == message.senderId &&
              saved.messageType == message.messageType &&
              saved.content == message.content) {
            return;
          }
        }
      } on Object {
        // Preserve the original safe error mapping below.
      }
      throw _failure(error);
    }
  }

  @override
  Future<CloudMessageDto?> fetchMessage(String id) async {
    _requireAuth();
    try {
      final row = await (await _ready())
          .from('messages')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : CloudMessageDto.fromJson(row);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<CloudMessageDto>> fetchMessages(String conversationId) async {
    final result = <CloudMessageDto>[];
    CloudMessageCursor? cursor;
    while (true) {
      final page = await fetchMessagesPage(
        conversationId: conversationId,
        cursor: cursor,
      );
      result.addAll(page.messages);
      if (!page.hasMore || page.messages.isEmpty) return result;
      final last = page.messages.last;
      cursor = CloudMessageCursor(createdAt: last.createdAt, id: last.id);
    }
  }

  @override
  Future<CloudConversationDto> createOrGetDirectConversation({
    required String peerUserId,
  }) async {
    _requireAuth();
    if (peerUserId.trim().isEmpty || peerUserId == _identity!.userId) {
      throw const CloudException(
        'บัญชีปลายทางไม่ถูกต้อง',
        code: 'invalidInput',
      );
    }
    try {
      final result = await (await _ready()).rpc(
        'create_or_get_direct_conversation',
        params: {'target_user_id': peerUserId},
      );
      if (result is! List || result.isEmpty) {
        throw const CloudException(
          'สร้างบทสนทนา Cloud ไม่สำเร็จ',
          code: 'invalidLocalData',
        );
      }
      final data = Map<String, dynamic>.from(result.first as Map);
      return CloudConversationDto(
        id: data['conversation_id'] as String,
        participantId: data['peer_user_id'] as String,
        displayName: data['peer_display_name'] as String? ?? '',
        updatedAt: DateTime.parse(data['updated_at'] as String),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<CloudConversationDto>> listMyDirectConversations() async {
    _requireAuth();
    try {
      final rows = await (await _ready()).rpc('list_my_direct_conversations');
      return (rows as List)
          .map((item) {
            final row = Map<String, dynamic>.from(item as Map);
            return CloudConversationDto(
              id: row['conversation_id'] as String,
              participantId: row['peer_user_id'] as String,
              displayName: row['peer_display_name'] as String? ?? '',
              updatedAt: DateTime.parse(row['updated_at'] as String),
            );
          })
          .toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CloudMessagePage> fetchMessagesPage({
    required String conversationId,
    CloudMessageCursor? cursor,
    int limit = 100,
  }) async {
    _requireAuth();
    if (limit < 1 || limit > 250) {
      throw const CloudException(
        'ขนาดหน้าข้อมูลไม่ถูกต้อง',
        code: 'invalidInput',
      );
    }
    try {
      var query = (await _ready())
          .from('messages')
          .select()
          .eq('conversation_id', conversationId);
      if (cursor != null) {
        final at = cursor.createdAt.toUtc().toIso8601String();
        query = query.or(
          'created_at.gt.$at,and(created_at.eq.$at,id.gt.${cursor.id})',
        );
      }
      final rows = await query.order('created_at').order('id').limit(limit + 1);
      final values = (rows as List)
          .map(
            (row) =>
                CloudMessageDto.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false);
      return CloudMessagePage(
        messages: values.take(limit).toList(growable: false),
        hasMore: values.length > limit,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> upsertReadReceipt(CloudReadReceipt receipt) async {
    _requireAuth();
    try {
      await (await _ready())
          .from('message_receipts')
          .upsert(
            {
              'message_id': receipt.messageId,
              'reader_id': _identity!.userId,
              'read_at': receipt.readAt.toUtc().toIso8601String(),
            },
            onConflict: 'message_id,reader_id',
            ignoreDuplicates: true,
          );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<CloudReadReceipt>> fetchReadReceipts({
    required String conversationId,
    required DateTime? afterReadAt,
    String? afterMessageId,
    String? afterReaderId,
    int limit = 100,
  }) async {
    _requireAuth();
    try {
      final rows = await (await _ready()).rpc(
        'fetch_conversation_read_receipts',
        params: {
          'target_conversation_id': conversationId,
          'after_read_at': afterReadAt?.toUtc().toIso8601String(),
          'after_message_id': afterMessageId,
          'after_reader_id': afterReaderId,
          'page_size': limit,
        },
      );
      return (rows as List)
          .map((item) {
            final row = Map<String, dynamic>.from(item as Map);
            return CloudReadReceipt(
              messageId: row['message_id'] as String,
              readerId: row['reader_id'] as String,
              readAt: DateTime.parse(row['read_at'] as String),
            );
          })
          .toList(growable: false);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> upsertConversation(CloudConversationDto conversation) async {
    _requireAuth();
    try {
      final data = conversation.toJson()..['owner_user_id'] = _identity!.userId;
      await (await _ready()).from('conversations').upsert(data);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CloudConversationDto?> fetchConversation(String id) async {
    _requireAuth();
    try {
      final row = await (await _ready())
          .from('conversations')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null
          ? null
          : CloudConversationDto.fromJson(Map<String, dynamic>.from(row));
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> upsertAttachment(CloudAttachmentDto attachment) async {
    _requireAuth();
    try {
      final data = attachment.toJson()..['owner_user_id'] = _identity!.userId;
      await (await _ready()).from('attachments').upsert(data);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CloudAttachmentDto?> fetchAttachment(String id) async {
    _requireAuth();
    try {
      final row = await (await _ready())
          .from('attachments')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null
          ? null
          : CloudAttachmentDto.fromJson(Map<String, dynamic>.from(row));
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CloudAttachmentPage> fetchConversationAttachmentsPage({
    required String conversationId,
    CloudAttachmentCursor? cursor,
    int limit = 100,
  }) async {
    _requireAuth();
    if (conversationId.isEmpty || limit < 1 || limit > 100) {
      throw const CloudException(
        'ขนาดหน้าข้อมูลไฟล์ไม่ถูกต้อง',
        code: 'invalidInput',
      );
    }
    try {
      var query = (await _ready())
          .from('attachments')
          .select('*, messages!inner(conversation_id)')
          .eq('messages.conversation_id', conversationId);
      if (cursor != null) {
        final at = cursor.createdAt.toUtc().toIso8601String();
        query = query.or(
          'created_at.gt.$at,and(created_at.eq.$at,id.gt.${cursor.id})',
        );
      }
      final rows = await query.order('created_at').order('id').limit(limit + 1);
      final values = (rows as List)
          .map(
            (row) => CloudAttachmentDto.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false);
      return CloudAttachmentPage(
        attachments: values.take(limit).toList(growable: false),
        hasMore: values.length > limit,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> upsertSos(CloudSosDto sos) async {
    _requireAuth();
    try {
      final data = sos.toJson()..['owner_user_id'] = _identity!.userId;
      await (await _ready()).from('sos_events').upsert(data);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<CloudSosDto?> fetchSos(String id) async {
    _requireAuth();
    try {
      final row = await (await _ready())
          .from('sos_events')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null
          ? null
          : CloudSosDto.fromJson(Map<String, dynamic>.from(row));
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> deactivateSos(String id) async {
    _requireAuth();
    try {
      await (await _ready())
          .from('sos_events')
          .update({'is_active': false})
          .eq('id', id);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<String> uploadAttachment({
    required String localPath,
    required String storagePath,
  }) async {
    _requireAuth();
    _validateStoragePath(storagePath);
    try {
      await (await _ready()).storage
          .from('relio-media')
          .upload(
            storagePath,
            File(localPath),
            fileOptions: const FileOptions(upsert: true),
          );
      return storagePath;
    } catch (error) {
      throw _failure(error, 'storage');
    }
  }

  @override
  Future<String> downloadAttachment({
    required String storagePath,
    required String ownerUserId,
    required MediaStorageService mediaStorage,
    required String fileName,
    required String mimeType,
    required int expectedByteSize,
    String? expectedSha256,
  }) async {
    _requireAuth();
    _validateStoragePath(storagePath, ownerUserId: ownerUserId);
    final mediaType = mimeType.startsWith('image/') ? 'image' : 'video';
    if (expectedByteSize <= 0 ||
        expectedByteSize > mediaStorage.policy.maxFor(mediaType)) {
      throw const CloudException(
        'ขนาดไฟล์ Cloud เกินขีดจำกัด',
        code: 'invalidLocalData',
      );
    }
    try {
      final bytes = await (await _ready()).storage
          .from('relio-media')
          .download(storagePath);
      return mediaStorage.storeDownloadedBytes(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        expectedByteSize: expectedByteSize,
        expectedSha256: expectedSha256,
      );
    } catch (error) {
      throw _failure(error, 'storage');
    }
  }

  @override
  Future<void> dispose() async {
    internetSimulator?.removeListener(_onInternetSimulatorChanged);
    await _authSubscription?.cancel();
    await _cloudStates.close();
    await _authStates.close();
  }
}
