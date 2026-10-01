import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../media/media_storage_service.dart';
import 'cloud_data_source.dart';
import 'cloud_error_mapper.dart';
import 'cloud_models.dart';
import 'cloud_storage_policy.dart';

class SupabaseCloudDataSource implements CloudDataSource {
  SupabaseCloudDataSource({SupabaseConfig? configuration})
    : configuration = configuration ?? const SupabaseConfig.fromEnvironment();

  @override
  final SupabaseConfig configuration;
  SupabaseClient? _client;
  StreamSubscription<dynamic>? _authSubscription;
  CloudState _state = CloudState.notConfigured;
  AuthState _authState = AuthState.guest;
  CloudIdentity? _identity;
  Future<void>? _initialization;
  bool _initialized = false;
  final _cloudStates = StreamController<CloudState>.broadcast();
  final _authStates = StreamController<AuthState>.broadcast();

  @override
  CloudState get cloudState => _state;
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
    if (!configuration.isConfigured) {
      _state = CloudState.notConfigured;
      _initialized = true;
      return;
    }
    try {
      await Supabase.initialize(
        url: configuration.url.trim(),
        publishableKey: configuration.anonKey.trim(),
        debug: false,
      );
      _client = Supabase.instance.client;
      _authSubscription ??= _client!.auth.onAuthStateChange.listen((event) {
        _identity = _mapUser(event.session?.user);
        _authState = _identity == null
            ? AuthState.guest
            : AuthState.authenticated;
        _state = _identity == null ? CloudState.signedOut : CloudState.ready;
        _authStates.add(_authState);
        _cloudStates.add(_state);
      });
      _identity = _mapUser(_client!.auth.currentUser);
      _authState = _identity == null
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
    await initialize();
    if (!configuration.isConfigured || _client == null) {
      throw const CloudException(
        'ยังไม่ได้ตั้งค่า Supabase',
        code: 'notConfigured',
      );
    }
    return _client!;
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
        );

  CloudException _failure(Object error, [String code = 'network']) =>
      CloudErrorMapper.map(error, fallbackCode: code);

  void _validateStoragePath(String storagePath) {
    if (_identity == null ||
        !CloudStoragePathPolicy.isOwnedBy(storagePath, _identity!.userId)) {
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
        // Do not treat an email-confirmation response as an authenticated
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
  Future<void> signOut() async {
    if (!configuration.isConfigured || _identity == null) {
      _identity = null;
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
    _authState = AuthState.guest;
    _state = CloudState.signedOut;
    _authStates.add(_authState);
    _cloudStates.add(_state);
  }

  @override
  Future<CloudIdentity?> restoreSession() async {
    await initialize();
    return _identity;
  }

  @override
  Future<void> upsertProfile({required String displayName}) async {
    _requireAuth();
    try {
      await (await _ready()).from('profiles').upsert({
        'id': _identity!.userId,
        'display_name': displayName,
      });
    } catch (error) {
      throw _failure(error);
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
      await (await _ready()).from('messages').upsert(message.toJson());
    } catch (error) {
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
    _requireAuth();
    try {
      final rows = await (await _ready())
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at');
      return (rows as List)
          .map(
            (row) =>
                CloudMessageDto.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
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
    required MediaStorageService mediaStorage,
    required String fileName,
    required String mimeType,
  }) async {
    _requireAuth();
    _validateStoragePath(storagePath);
    try {
      final bytes = await (await _ready()).storage
          .from('relio-media')
          .download(storagePath);
      return mediaStorage.storeDownloadedBytes(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );
    } catch (error) {
      throw _failure(error, 'storage');
    }
  }

  @override
  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _cloudStates.close();
    await _authStates.close();
  }
}
