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

class FakeCloudBackend {
  final users = <String, ({String password, CloudIdentity identity})>{};
  final pushTokens = <String, String>{};
  final messages = <String, CloudMessageDto>{};
  final conversations = <String, CloudConversationDto>{};
  final attachments = <String, CloudAttachmentDto>{};
  final sosEvents = <String, CloudSosDto>{};
  final files = <String, Uint8List>{};
  final conversationOwners = <String, String>{};
  final messageOwners = <String, String>{};
  final attachmentOwners = <String, String>{};
  final sosOwners = <String, String>{};
  final conversationMembers = <String, Set<String>>{};
  final directConversationIds = <String, String>{};
  final readReceipts = <String, CloudReadReceipt>{};
  DateTime? lastMessageServerTime;
}

class FakeCloudDataSource implements CloudDataSource {
  FakeCloudDataSource({
    this.configured = true,
    this.offline = false,
    this.failureMode = FakeCloudFailure.none,
    FakeCloudBackend? backend,
  }) : backend = backend ?? FakeCloudBackend();

  @override
  final SupabaseConfig configuration = const SupabaseConfig(
    url: 'https://fake.local',
    anonKey: 'fake',
  );
  final bool configured;
  final FakeCloudBackend backend;
  bool offline;
  FakeCloudFailure failureMode;
  CloudState _state = CloudState.signedOut;
  AuthState _authState = AuthState.guest;
  CloudIdentity? _identity;
  final _cloudStates = StreamController<CloudState>.broadcast();
  final _authStates = StreamController<AuthState>.broadcast();
  Map<String, String> get pushTokens => backend.pushTokens;
  Map<String, ({String password, CloudIdentity identity})> get _users =>
      backend.users;
  Map<String, CloudMessageDto> get messages => backend.messages;
  Map<String, CloudConversationDto> get conversations => backend.conversations;
  Map<String, CloudAttachmentDto> get attachments => backend.attachments;
  Map<String, CloudSosDto> get sosEvents => backend.sosEvents;
  Map<String, Uint8List> get files => backend.files;
  Map<String, String> get _conversationOwners => backend.conversationOwners;
  Map<String, String> get _messageOwners => backend.messageOwners;
  Map<String, String> get _attachmentOwners => backend.attachmentOwners;
  Map<String, String> get _sosOwners => backend.sosOwners;
  Map<String, Set<String>> get _conversationMembers =>
      backend.conversationMembers;
  Map<String, String> get _directConversationIds =>
      backend.directConversationIds;
  Map<String, CloudReadReceipt> get readReceipts => backend.readReceipts;

  CloudIdentity createTestIdentity({
    required String email,
    String? displayName,
  }) {
    final identity = CloudIdentity(
      userId: 'fake-${_users.length + 1}',
      email: email,
      displayName: displayName,
    );
    _users[email] = (password: 'password', identity: identity);
    return identity;
  }

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
  Future<void> upsertPushToken({
    required String deviceId,
    required String token,
  }) async {
    _requireAuth();
    if (deviceId.isEmpty || token.isEmpty) {
      throw const CloudException(
        'Push registration is invalid.',
        code: 'invalidInput',
      );
    }
    pushTokens['${_identity!.userId}:$deviceId'] = token;
  }

  @override
  Future<void> deletePushToken({required String deviceId}) async {
    _requireAuth();
    pushTokens.remove('${_identity!.userId}:$deviceId');
  }

  @override
  Future<void> upsertMessage(CloudMessageDto message) async {
    _requireAuth();
    final members = _conversationMembers[message.conversationId];
    if (message.senderId != _identity!.userId ||
        !(members?.contains(_identity!.userId) ?? false) ||
        (_messageOwners[message.id] != null &&
            _messageOwners[message.id] != _identity!.userId)) {
      throw const CloudException(
        'ข้อความไม่ได้เป็นของบัญชีปัจจุบัน',
        code: 'permissionDenied',
      );
    }
    final existing = messages[message.id];
    if (existing != null &&
        (existing.conversationId != message.conversationId ||
            existing.senderId != message.senderId ||
            existing.content != message.content ||
            existing.messageType != message.messageType)) {
      throw const CloudException(
        'รหัสข้อความซ้ำกับข้อมูลคนละรายการ',
        code: 'invalidLocalData',
      );
    }
    if (existing == null) {
      final now = DateTime.now().toUtc();
      final previous = backend.lastMessageServerTime;
      final serverTime = previous == null || now.isAfter(previous)
          ? now
          : previous.add(const Duration(microseconds: 1));
      backend.lastMessageServerTime = serverTime;
      messages[message.id] = CloudMessageDto(
        id: message.id,
        conversationId: message.conversationId,
        senderId: message.senderId,
        senderDeviceId: message.senderDeviceId,
        messageType: message.messageType,
        content: message.content,
        createdAt: serverTime,
        updatedAt: serverTime,
        deliveryStatus: 'pending',
        isOutgoing: false,
      );
    }
    _messageOwners[message.id] = _identity!.userId;
  }

  @override
  Future<CloudMessageDto?> fetchMessage(String id) async {
    _requireAuth();
    final message = messages[id];
    if (message == null) return null;
    _requireConversationMember(message.conversationId);
    return message;
  }

  @override
  Future<List<CloudMessageDto>> fetchMessages(String conversationId) async {
    _requireAuth();
    _requireConversationMember(conversationId);
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
  Future<CloudConversationDto> createOrGetDirectConversation({
    required String peerUserId,
  }) async {
    _requireAuth();
    CloudIdentity? peer;
    for (final entry in _users.values) {
      if (entry.identity.userId == peerUserId) {
        peer = entry.identity;
        break;
      }
    }
    final selectedPeer = peer;
    if (selectedPeer == null || selectedPeer.userId == _identity!.userId) {
      throw const CloudException(
        'บัญชีปลายทางไม่ถูกต้อง',
        code: 'invalidInput',
      );
    }
    final participants = [_identity!.userId, selectedPeer.userId]..sort();
    final key = participants.join(':');
    final id = _directConversationIds.putIfAbsent(
      key,
      () => 'fake-conversation-${_directConversationIds.length + 1}',
    );
    final members = _conversationMembers.putIfAbsent(id, () => <String>{});
    members.addAll(participants);
    _conversationOwners.putIfAbsent(id, () => participants.first);
    conversations.putIfAbsent(
      id,
      () => CloudConversationDto(
        id: id,
        participantId: selectedPeer.userId,
        displayName: selectedPeer.displayName ?? selectedPeer.email,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    return CloudConversationDto(
      id: id,
      participantId: selectedPeer.userId,
      displayName: selectedPeer.displayName ?? selectedPeer.email,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<List<CloudConversationDto>> listMyDirectConversations() async {
    _requireAuth();
    return _conversationMembers.entries
        .where((entry) => entry.value.contains(_identity!.userId))
        .map((entry) {
          final peerId = entry.value.firstWhere(
            (userId) => userId != _identity!.userId,
          );
          final peer = _users.values
              .map((user) => user.identity)
              .firstWhere((user) => user.userId == peerId);
          final conversation = conversations[entry.key]!;
          return CloudConversationDto(
            id: entry.key,
            participantId: peerId,
            displayName: peer.displayName ?? peer.email,
            updatedAt: conversation.updatedAt,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<CloudMessagePage> fetchMessagesPage({
    required String conversationId,
    CloudMessageCursor? cursor,
    int limit = 100,
  }) async {
    _requireAuth();
    _requireConversationMember(conversationId);
    if (limit < 1 || limit > 250) {
      throw const CloudException(
        'ขนาดหน้าข้อมูลไม่ถูกต้อง',
        code: 'invalidInput',
      );
    }
    final rows =
        messages.values
            .where((message) => message.conversationId == conversationId)
            .where((message) {
              if (cursor == null) return true;
              final time = message.createdAt.compareTo(cursor.createdAt);
              return time > 0 ||
                  (time == 0 && message.id.compareTo(cursor.id) > 0);
            })
            .toList()
          ..sort((a, b) {
            final time = a.createdAt.compareTo(b.createdAt);
            return time == 0 ? a.id.compareTo(b.id) : time;
          });
    return CloudMessagePage(
      messages: rows.take(limit).toList(growable: false),
      hasMore: rows.length > limit,
    );
  }

  @override
  Future<void> upsertReadReceipt(CloudReadReceipt receipt) async {
    _requireAuth();
    final message = messages[receipt.messageId];
    if (message == null) {
      throw const CloudException('ไม่พบข้อความ', code: 'notFound');
    }
    _requireConversationMember(message.conversationId);
    if (receipt.readerId != _identity!.userId) {
      throw const CloudException(
        'ใบตอบรับไม่ได้เป็นของบัญชีปัจจุบัน',
        code: 'permissionDenied',
      );
    }
    readReceipts.putIfAbsent(
      '${receipt.messageId}:${receipt.readerId}',
      () => receipt,
    );
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
    _requireConversationMember(conversationId);
    final rows =
        readReceipts.values.where((receipt) {
          final message = messages[receipt.messageId];
          if (message?.conversationId != conversationId) return false;
          if (afterReadAt == null) return true;
          final time = receipt.readAt.compareTo(afterReadAt);
          if (time != 0) return time > 0;
          final messageOrder = receipt.messageId.compareTo(
            afterMessageId ?? '',
          );
          if (messageOrder != 0) return messageOrder > 0;
          return receipt.readerId.compareTo(afterReaderId ?? '') > 0;
        }).toList()..sort((a, b) {
          final time = a.readAt.compareTo(b.readAt);
          if (time != 0) return time;
          final message = a.messageId.compareTo(b.messageId);
          return message == 0 ? a.readerId.compareTo(b.readerId) : message;
        });
    return rows.take(limit).toList(growable: false);
  }

  @override
  Future<CloudConversationDto?> fetchConversation(String id) async {
    _requireAuth();
    final conversation = conversations[id];
    if (conversation == null) return null;
    _requireConversationMember(id);
    return CloudConversationDto(
      id: id,
      participantId: _conversationMembers[id]!.firstWhere(
        (userId) => userId != _identity!.userId,
      ),
      displayName: conversation.displayName,
      updatedAt: conversation.updatedAt,
    );
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

  void _requireConversationMember(String conversationId) {
    if (!(_conversationMembers[conversationId]?.contains(_identity!.userId) ??
        false)) {
      throw const CloudException(
        'ไม่มีสิทธิ์เข้าถึงบทสนทนา',
        code: 'permissionDenied',
      );
    }
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
    _conversationMembers.clear();
    _directConversationIds.clear();
    readReceipts.clear();
    failureMode = FakeCloudFailure.none;
  }
}
