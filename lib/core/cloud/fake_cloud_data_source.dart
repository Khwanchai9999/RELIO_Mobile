import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../media/media_storage_service.dart';
import 'cloud_data_source.dart';
import 'cloud_models.dart';
import 'cloud_storage_policy.dart';

enum FakeCloudFailure {
  none,
  offline,
  timeout,
  temporaryServer,
  rateLimit,
  unauthenticated,
  permissionDenied,
  uploadFailure,
}

class FakeCloudDataSource implements CloudDataSource {
  FakeCloudDataSource({
    this.configured = true,
    this.offline = false,
    this.failureMode = FakeCloudFailure.none,
  });

  @override
  final SupabaseConfig configuration = const SupabaseConfig(
    url: 'https://fake.local',
    anonKey: 'fake',
  );
  final bool configured;
  bool offline;
  FakeCloudFailure failureMode;
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
  final _conversationOwners = <String, String>{};
  final _messageOwners = <String, String>{};
  final _attachmentOwners = <String, String>{};
  final _sosOwners = <String, String>{};

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
    final failure = offline ? FakeCloudFailure.offline : failureMode;
    if (failure != FakeCloudFailure.none &&
        failure != FakeCloudFailure.uploadFailure) {
      final (message, code) = switch (failure) {
        FakeCloudFailure.offline => (
          'ออฟไลน์ ไม่สามารถเชื่อมต่อคลาวด์ได้',
          'offline',
        ),
        FakeCloudFailure.timeout => ('Cloud timeout', 'timeout'),
        FakeCloudFailure.temporaryServer => (
          'Cloud server ชั่วคราวขัดข้อง',
          'server',
        ),
        FakeCloudFailure.rateLimit => ('Cloud rate limit', 'rateLimit'),
        FakeCloudFailure.unauthenticated => (
          'ต้องเข้าสู่ระบบก่อนใช้งานคลาวด์',
          'signedOut',
        ),
        FakeCloudFailure.permissionDenied => (
          'ไม่มีสิทธิ์เขียน Cloud',
          'permissionDenied',
        ),
        FakeCloudFailure.none || FakeCloudFailure.uploadFailure => ('', ''),
      };
      throw CloudException(message, code: code);
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
    if (message.senderId != _identity!.userId ||
        (_messageOwners[message.id] != null &&
            _messageOwners[message.id] != _identity!.userId)) {
      throw const CloudException(
        'ข้อความไม่ได้เป็นของบัญชีปัจจุบัน',
        code: 'permissionDenied',
      );
    }
    messages[message.id] = message;
    _messageOwners[message.id] = _identity!.userId;
  }

  @override
  Future<CloudMessageDto?> fetchMessage(String id) async {
    _requireAuth();
    _requireRecordOwner(_messageOwners[id]);
    return messages[id];
  }

  @override
  Future<List<CloudMessageDto>> fetchMessages(String conversationId) async {
    _requireAuth();
    _requireRecordOwner(_conversationOwners[conversationId]);
    return messages.values
        .where((item) => item.conversationId == conversationId)
        .toList();
  }

  @override
  Future<void> upsertConversation(CloudConversationDto conversation) async {
    _requireAuth();
    if (_conversationOwners[conversation.id] != null &&
        _conversationOwners[conversation.id] != _identity!.userId) {
      throw const CloudException(
        'บทสนทนาไม่ได้เป็นของบัญชีปัจจุบัน',
        code: 'permissionDenied',
      );
    }
    conversations[conversation.id] = conversation;
    _conversationOwners[conversation.id] = _identity!.userId;
  }

  @override
  Future<CloudConversationDto?> fetchConversation(String id) async {
    _requireAuth();
    _requireRecordOwner(_conversationOwners[id]);
    return conversations[id];
  }

  @override
  Future<void> upsertAttachment(CloudAttachmentDto attachment) async {
    _requireAuth();
    if (!CloudStoragePathPolicy.isOwnedBy(
          attachment.storagePath,
          _identity!.userId,
        ) ||
        (_messageOwners[attachment.messageId] != null &&
            _messageOwners[attachment.messageId] != _identity!.userId) ||
        (_attachmentOwners[attachment.id] != null &&
            _attachmentOwners[attachment.id] != _identity!.userId)) {
      throw const CloudException(
        'ไฟล์แนบไม่ได้เป็นของบัญชีปัจจุบัน',
        code: 'permissionDenied',
      );
    }
    attachments[attachment.id] = attachment;
    _attachmentOwners[attachment.id] = _identity!.userId;
  }

  @override
  Future<CloudAttachmentDto?> fetchAttachment(String id) async {
    _requireAuth();
    _requireRecordOwner(_attachmentOwners[id]);
    return attachments[id];
  }

  @override
  Future<void> upsertSos(CloudSosDto sos) async {
    _requireAuth();
    if (_sosOwners[sos.id] != null && _sosOwners[sos.id] != _identity!.userId) {
      throw const CloudException(
        'ข้อมูล SOS ไม่ได้เป็นของบัญชีปัจจุบัน',
        code: 'permissionDenied',
      );
    }
    sosEvents[sos.id] = sos;
    _sosOwners[sos.id] = _identity!.userId;
  }

  @override
  Future<CloudSosDto?> fetchSos(String id) async {
    _requireAuth();
    _requireRecordOwner(_sosOwners[id]);
    return sosEvents[id];
  }

  @override
  Future<void> deactivateSos(String id) async {
    _requireAuth();
    _requireRecordOwner(_sosOwners[id]);
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
    if (!CloudStoragePathPolicy.isOwnedBy(storagePath, _identity!.userId)) {
      throw const CloudException(
        'เส้นทางไฟล์คลาวด์ไม่ปลอดภัย',
        code: 'invalidPath',
      );
    }
    if (failureMode == FakeCloudFailure.uploadFailure) {
      throw const CloudException('อัปโหลดไฟล์ไม่สำเร็จ', code: 'storage');
    }
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
    if (!CloudStoragePathPolicy.isOwnedBy(storagePath, _identity!.userId)) {
      throw const CloudException(
        'เส้นทางไฟล์คลาวด์ไม่ปลอดภัย',
        code: 'invalidPath',
      );
    }
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

  @override
  Future<void> dispose() async {
    await _cloudStates.close();
    await _authStates.close();
  }

  void _requireRecordOwner(String? ownerUserId) {
    if (ownerUserId != null && ownerUserId != _identity!.userId) {
      throw const CloudException(
        'ข้อมูลไม่ได้เป็นของบัญชีปัจจุบัน',
        code: 'permissionDenied',
      );
    }
  }

  void resetCloudState() {
    messages.clear();
    conversations.clear();
    attachments.clear();
    sosEvents.clear();
    files.clear();
    _conversationOwners.clear();
    _messageOwners.clear();
    _attachmentOwners.clear();
    _sosOwners.clear();
    failureMode = FakeCloudFailure.none;
  }
}
