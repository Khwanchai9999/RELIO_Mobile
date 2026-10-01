import '../media/media_storage_service.dart';
import 'cloud_models.dart';

abstract interface class CloudDataSource {
  SupabaseConfig get configuration;
  CloudState get cloudState;
  AuthState get authState;
  CloudIdentity? get currentIdentity;
  Stream<CloudState> watchCloudState();
  Stream<AuthState> watchAuthState();
  Future<void> initialize();
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
  Future<void> upsertProfile({required String displayName});
  Future<void> upsertPushToken({
    required String deviceId,
    required String token,
  });
  Future<void> deletePushToken({required String deviceId});
  Future<void> upsertMessage(CloudMessageDto message);
  Future<CloudMessageDto?> fetchMessage(String id);
  Future<List<CloudMessageDto>> fetchMessages(String conversationId);
  Future<CloudConversationDto> createOrGetDirectConversation({
    required String peerUserId,
  });
  Future<List<CloudConversationDto>> listMyDirectConversations();
  Future<CloudMessagePage> fetchMessagesPage({
    required String conversationId,
    CloudMessageCursor? cursor,
    int limit = 100,
  });
  Future<void> upsertReadReceipt(CloudReadReceipt receipt);
  Future<List<CloudReadReceipt>> fetchReadReceipts({
    required String conversationId,
    required DateTime? afterReadAt,
    String? afterMessageId,
    String? afterReaderId,
    int limit = 100,
  });
  Future<void> upsertConversation(CloudConversationDto conversation);
  Future<CloudConversationDto?> fetchConversation(String id);
  Future<void> upsertAttachment(CloudAttachmentDto attachment);
  Future<CloudAttachmentDto?> fetchAttachment(String id);
  Future<void> upsertSos(CloudSosDto sos);
  Future<CloudSosDto?> fetchSos(String id);
  Future<void> deactivateSos(String id);
  Future<String> uploadAttachment({
    required String localPath,
    required String storagePath,
  });
  Future<String> downloadAttachment({
    required String storagePath,
    required MediaStorageService mediaStorage,
    required String fileName,
    required String mimeType,
  });
  Future<void> dispose();
}
