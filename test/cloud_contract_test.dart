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

  test(
    'guest email upgrade preserves the Cloud identity and adds recovery',
    () async {
      final cloud = FakeCloudDataSource();
      final guest = await cloud.signInAnonymously();
      final pending = await cloud.requestEmailChange(
        email: 'guest-owner@example.com',
      );
      expect(pending.userId, guest.userId);
      expect(pending.pendingEmail, 'guest-owner@example.com');

      final verified = await cloud.verifyEmailChange(
        email: 'guest-owner@example.com',
        token: '123456',
      );
      expect(verified.verified, isTrue);
      expect(verified.identity.userId, guest.userId);
      expect(verified.identity.isAnonymous, isTrue);

      final upgraded = await cloud.setAccountPassword(
        password: 'recovery-password',
      );
      expect(upgraded.userId, guest.userId);
      expect(upgraded.email, 'guest-owner@example.com');
      expect(upgraded.isAnonymous, isFalse);

      await cloud.signOut();
      final restoredAccount = FakeCloudDataSource(backend: cloud.backend);
      expect(
        (await restoredAccount.signIn(
          email: 'guest-owner@example.com',
          password: 'recovery-password',
        )).userId,
        guest.userId,
      );
      await restoredAccount.dispose();
      await cloud.dispose();
    },
  );

  test(
    'member email change preserves identity and rejects another owner email',
    () async {
      final cloud = FakeCloudDataSource();
      final member = await cloud.register(
        email: 'member-before@example.com',
        password: 'member-password',
      );
      await cloud.register(
        email: 'already-owned@example.com',
        password: 'other-password',
      );
      await cloud.signIn(
        email: 'member-before@example.com',
        password: 'member-password',
      );

      await expectLater(
        cloud.requestEmailChange(email: 'already-owned@example.com'),
        throwsA(
          isA<CloudException>().having(
            (error) => error.code,
            'code',
            'emailAlreadyUsed',
          ),
        ),
      );
      await cloud.requestEmailChange(email: 'member-after@example.com');
      final result = await cloud.verifyEmailChange(
        email: 'member-after@example.com',
        token: '654321',
      );
      expect(result.verified, isTrue);
      expect(result.identity.userId, member.userId);
      expect(result.identity.isAnonymous, isFalse);

      await cloud.signOut();
      final restored = await cloud.signIn(
        email: 'member-after@example.com',
        password: 'member-password',
      );
      expect(restored.userId, member.userId);
      await cloud.dispose();
    },
  );

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

  test(
    'read receipt pagination rejects partial cursors and unsafe limits',
    () async {
      final cloud = FakeCloudDataSource();
      final identity = await cloud.register(
        email: 'tester@example.com',
        password: 'password123',
      );
      final peer = cloud.createTestIdentity(email: 'peer@example.com');
      final conversation = await cloud.createOrGetDirectConversation(
        peerUserId: peer.userId,
      );

      await expectLater(
        cloud.fetchReadReceipts(
          conversationId: conversation.id,
          afterReadAt: DateTime.utc(2026),
          afterMessageId: null,
          afterReaderId: identity.userId,
        ),
        throwsA(isA<CloudException>()),
      );
      await expectLater(
        cloud.fetchReadReceipts(
          conversationId: conversation.id,
          afterReadAt: null,
          limit: 0,
        ),
        throwsA(isA<CloudException>()),
      );
      await expectLater(
        cloud.fetchReadReceipts(
          conversationId: conversation.id,
          afterReadAt: null,
          limit: 251,
        ),
        throwsA(isA<CloudException>()),
      );
      await cloud.dispose();
    },
  );

  test(
    'read receipt cursor pages remain ordered for tied client timestamps',
    () async {
      final cloud = FakeCloudDataSource();
      final identity = await cloud.register(
        email: 'cursor@example.com',
        password: 'password123',
      );
      final peer = cloud.createTestIdentity(email: 'cursor-peer@example.com');
      final conversation = await cloud.createOrGetDirectConversation(
        peerUserId: peer.userId,
      );
      final sameClientTime = DateTime.utc(2026, 10, 1, 10);

      for (var index = 0; index < 3; index++) {
        final id = 'receipt-message-$index';
        await cloud.upsertMessage(
          CloudMessageDto(
            id: id,
            conversationId: conversation.id,
            senderId: identity.userId,
            senderDeviceId: 'cursor-device',
            messageType: 'text',
            content: 'receipt $index',
            createdAt: sameClientTime,
            updatedAt: sameClientTime,
            deliveryStatus: 'pending',
            isOutgoing: true,
          ),
        );
        await cloud.upsertReadReceipt(
          CloudReadReceipt(
            messageId: id,
            readerId: identity.userId,
            readAt: sameClientTime,
          ),
        );
      }

      final firstPage = await cloud.fetchReadReceipts(
        conversationId: conversation.id,
        afterReadAt: null,
        limit: 2,
      );
      expect(firstPage, hasLength(2));
      expect(firstPage[1].readAt.isAfter(firstPage[0].readAt), isTrue);
      final last = firstPage.last;
      final secondPage = await cloud.fetchReadReceipts(
        conversationId: conversation.id,
        afterReadAt: last.readAt,
        afterMessageId: last.messageId,
        afterReaderId: last.readerId,
        limit: 2,
      );
      expect(secondPage, hasLength(1));
      expect(secondPage.single.messageId, 'receipt-message-2');
      await cloud.dispose();
    },
  );

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
          ownerUserId: 'fake-1',
          mediaStorage: MediaStorageService(),
          fileName: 'missing.jpg',
          mimeType: 'image/jpeg',
          expectedByteSize: 128,
          expectedSha256: null,
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
