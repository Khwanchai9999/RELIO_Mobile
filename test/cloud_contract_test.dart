import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/media/media_storage_service.dart';

void main() {
  test(
    'missing or unsafe Supabase configuration is not considered configured',
    () {
      expect(const SupabaseConfig.fromEnvironment().isConfigured, isFalse);
      expect(
        const SupabaseConfig(
          url: 'https://example.supabase.co',
          anonKey: 'service_role_secret',
        ).isConfigured,
        isFalse,
      );
    },
  );

  test('fake cloud supports register, session restore, and sign out', () async {
    final cloud = FakeCloudDataSource();
    final identity = await cloud.register(
      email: 'tester@example.com',
      password: 'password123',
      displayName: 'Tester',
    );

    expect(identity.userId, 'fake-1');
    expect(cloud.authState, AuthState.authenticated);
    expect(await cloud.restoreSession(), identity);

    await cloud.signOut();
    expect(cloud.authState, AuthState.guest);
    expect(cloud.cloudState, CloudState.signedOut);
    await cloud.dispose();
  });

  test('fake cloud rejects access while unconfigured or signed out', () async {
    final unconfigured = FakeCloudDataSource(configured: false);
    await expectLater(
      unconfigured.upsertMessage(_message()),
      throwsA(isA<CloudException>()),
    );

    final signedOut = FakeCloudDataSource();
    await expectLater(
      signedOut.upsertMessage(_message()),
      throwsA(isA<CloudException>()),
    );
    await unconfigured.dispose();
    await signedOut.dispose();
  });

  test('fake cloud upsert is idempotent by local UUID', () async {
    final cloud = FakeCloudDataSource();
    await cloud.register(email: 'tester@example.com', password: 'password123');
    final peer = cloud.createTestIdentity(email: 'peer@example.com');
    final conversation = await cloud.createOrGetDirectConversation(
      peerUserId: peer.userId,
    );
    final message = _message(conversationId: conversation.id);
    await cloud.upsertMessage(message);
    await cloud.upsertMessage(message);
    expect(cloud.messages, hasLength(1));
    expect((await cloud.fetchMessage(message.id))?.content, 'hello');
    await cloud.dispose();
  });

  test('DTO preserves stable message fields and UTC timestamps', () {
    final original = _message();
    final decoded = CloudMessageDto.fromJson(original.toJson());
    expect(decoded.id, original.id);
    expect(decoded.conversationId, original.conversationId);
    expect(decoded.createdAt.toUtc(), original.createdAt.toUtc());
    expect(decoded.deliveryStatus, 'pending');
  });

  test(
    'cloud download uses the application-owned media storage service',
    () async {
      final cloud = FakeCloudDataSource();
      await cloud.register(
        email: 'tester@example.com',
        password: 'password123',
      );
      await expectLater(
        cloud.downloadAttachment(
          storagePath: 'users/fake-1/messages/missing/attachment',
          mediaStorage: MediaStorageService(),
          fileName: 'missing.jpg',
          mimeType: 'image/jpeg',
        ),
        throwsA(isA<CloudException>()),
      );
      await cloud.dispose();
    },
  );
}

CloudMessageDto _message({String conversationId = 'conversation-1'}) =>
    CloudMessageDto(
      id: 'message-1',
      conversationId: conversationId,
      senderId: 'fake-1',
      senderDeviceId: 'device-1',
      messageType: 'text',
      content: 'hello',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      deliveryStatus: 'pending',
      isOutgoing: true,
    );
