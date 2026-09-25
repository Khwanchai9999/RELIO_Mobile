import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../media/media_storage_service.dart';
import 'cloud_data_source.dart';
import 'cloud_models.dart';

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
  Future<void> initialize() async {
    if (!configuration.isConfigured) {
      _state = CloudState.notConfigured;
      return;
    }
    try {
      // The SDK's initialize call is idempotent and its `instance` getter
      // asserts before initialization, so do not probe instance first.
      await Supabase.initialize(
        url: configuration.url,
        publishableKey: configuration.anonKey,
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
    } catch (error) {
      _state = CloudState.error;
      _cloudStates.add(_state);
      throw CloudException(
        'เริ่มต้นบริการคลาวด์ไม่สำเร็จ',
        code: 'initialization',
      );
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
    if (_identity == null) {
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
      CloudException('การเชื่อมต่อคลาวด์ไม่สำเร็จ', code: code);

  void _validateStoragePath(String storagePath) {
    final expectedPrefix = 'users/${_identity!.userId}/messages/';
    if (!storagePath.startsWith(expectedPrefix) ||
        storagePath.contains('..') ||
        storagePath.contains('\\')) {
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
      _identity = identity;
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
      return identity;
    } catch (error) {
      if (error is CloudException) rethrow;
      throw _failure(error, 'auth');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await (await _ready()).auth.signOut();
    } catch (error) {
      if (error is CloudException) rethrow;
      throw _failure(error, 'auth');
    }
    _identity = null;
    _authState = AuthState.guest;
    _state = CloudState.signedOut;
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
  Future<void> upsertMessage(CloudMessageDto message) async {
    _requireAuth();
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

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _cloudStates.close();
    await _authStates.close();
  }
}
