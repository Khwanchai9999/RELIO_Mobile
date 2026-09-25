import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../media/media_storage_service.dart';
import 'cloud_data_source.dart';
import 'cloud_models.dart';

class FakeCloudDataSource implements CloudDataSource {
  FakeCloudDataSource({this.configured = true, this.offline = false});

  @override
  final SupabaseConfig configuration = const SupabaseConfig(
    url: 'https://fake.local',
    anonKey: 'fake',
  );
  final bool configured;
  bool offline;
  CloudState _state = CloudState.signedOut;
  AuthState _authState = AuthState.guest;
  CloudIdentity? _identity;
  final _cloudStates = StreamController<CloudState>.broadcast();
  final _authStates = StreamController<AuthState>.broadcast();
  final _users = <String, ({String password, CloudIdentity identity})>{};
  final messages = <String, CloudMessageDto>{};
  final conversations = <String, CloudConversationDto>{};
  final attachments = <String, CloudAttachmentDto>{};
  final sosEvents = <String, CloudSosDto>{};
  final files = <String, Uint8List>{};

  @override
  CloudState get cloudState => configured ? _state : CloudState.notConfigured;
  @override
  AuthState get authState => configured ? _authState : AuthState.guest;
  @override
  CloudIdentity? get currentIdentity => _identity;
  @override
  Stream<CloudState> watchCloudState() => _cloudStates.stream;
  @override
  Stream<AuthState> watchAuthState() => _authStates.stream;

  void _check() {
    if (!configured) {
      throw const CloudException(
        'ยังไม่ได้ตั้งค่า Supabase',
        code: 'notConfigured',
      );
    }
    if (offline) {
      throw const CloudException(
        'ออฟไลน์ ไม่สามารถเชื่อมต่อคลาวด์ได้',
        code: 'offline',
      );
    }
  }

  void _requireAuth() {
    _check();
    if (_identity == null) {
      throw const CloudException(
        'ต้องเข้าสู่ระบบก่อนใช้งานคลาวด์',
        code: 'signedOut',
      );
    }
  }

  @override
  Future<void> initialize() async {
    if (!configured) return;
    _state = _identity == null ? CloudState.signedOut : CloudState.ready;
    _cloudStates.add(_state);
  }

  @override
  Future<CloudIdentity> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _check();
    if (_users.containsKey(email)) {
      throw const CloudException('อีเมลนี้ถูกใช้งานแล้ว', code: 'auth');
    }
    final identity = CloudIdentity(
      userId: 'fake-${_users.length + 1}',
      email: email,
      displayName: displayName,
    );
    _users[email] = (password: password, identity: identity);
    _identity = identity;
    _authState = AuthState.authenticated;
    _state = CloudState.ready;
    _cloudStates.add(_state);
    _authStates.add(_authState);
    return identity;
  }

  @override
  Future<CloudIdentity> signIn({
    required String email,
    required String password,
  }) async {
    _check();
    final user = _users[email];
    if (user == null || user.password != password) {
      throw const CloudException('อีเมลหรือรหัสผ่านไม่ถูกต้อง', code: 'auth');
    }
    _identity = user.identity;
    _authState = AuthState.authenticated;
    _state = CloudState.ready;
    _cloudStates.add(_state);
    _authStates.add(_authState);
    return _identity!;
  }

  @override
  Future<void> signOut() async {
    _identity = null;
    _authState = AuthState.guest;
    _state = configured ? CloudState.signedOut : CloudState.notConfigured;
    _authStates.add(_authState);
    _cloudStates.add(_state);
  }

  @override
  Future<CloudIdentity?> restoreSession() async {
    await initialize();
    return _identity;
  }

  @override
  Future<void> upsertProfile({required String displayName}) async =>
      _requireAuth();
  @override
  Future<void> upsertMessage(CloudMessageDto message) async {
    _requireAuth();
    messages[message.id] = message;
  }

  @override
  Future<CloudMessageDto?> fetchMessage(String id) async {
    _requireAuth();
    return messages[id];
  }

  @override
  Future<List<CloudMessageDto>> fetchMessages(String conversationId) async {
    _requireAuth();
    return messages.values
        .where((item) => item.conversationId == conversationId)
        .toList();
  }

  @override
  Future<void> upsertConversation(CloudConversationDto conversation) async {
    _requireAuth();
    conversations[conversation.id] = conversation;
  }

  @override
  Future<CloudConversationDto?> fetchConversation(String id) async {
    _requireAuth();
    return conversations[id];
  }

  @override
  Future<void> upsertAttachment(CloudAttachmentDto attachment) async {
    _requireAuth();
    attachments[attachment.id] = attachment;
  }

  @override
  Future<CloudAttachmentDto?> fetchAttachment(String id) async {
    _requireAuth();
    return attachments[id];
  }

  @override
  Future<void> upsertSos(CloudSosDto sos) async {
    _requireAuth();
    sosEvents[sos.id] = sos;
  }

  @override
  Future<CloudSosDto?> fetchSos(String id) async {
    _requireAuth();
    return sosEvents[id];
  }

  @override
  Future<void> deactivateSos(String id) async {
    _requireAuth();
    final current = sosEvents[id];
    if (current != null) {
      sosEvents[id] = CloudSosDto(
        id: current.id,
        ownerDeviceId: current.ownerDeviceId,
        message: current.message,
        latitude: current.latitude,
        longitude: current.longitude,
        createdAt: current.createdAt,
        isActive: false,
      );
    }
  }

  @override
  Future<String> uploadAttachment({
    required String localPath,
    required String storagePath,
  }) async {
    _requireAuth();
    files[storagePath] = await File(localPath).readAsBytes();
    return storagePath;
  }

  @override
  Future<String> downloadAttachment({
    required String storagePath,
    required MediaStorageService mediaStorage,
    required String fileName,
    required String mimeType,
  }) async {
    _requireAuth();
    final bytes = files[storagePath];
    if (bytes == null) {
      throw const CloudException('ไม่พบไฟล์บนคลาวด์', code: 'notFound');
    }
    return mediaStorage.storeDownloadedBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  Future<void> dispose() async {
    await _cloudStates.close();
    await _authStates.close();
  }
}
