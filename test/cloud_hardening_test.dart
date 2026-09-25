import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:relio_mobile/core/cloud/cloud_error_mapper.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/cloud/cloud_storage_policy.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/cloud/supabase_cloud_data_source.dart';

void main() {
  test('configuration validation rejects unsafe or malformed values', () {
    expect(
      const SupabaseConfig(
        url: 'http://example.supabase.co',
        anonKey: 'key',
      ).isConfigured,
      isFalse,
    );
    expect(
      const SupabaseConfig(
        url: 'https://example.supabase.co',
        anonKey: 'service_role_secret',
      ).isConfigured,
      isFalse,
    );
    expect(
      const SupabaseConfig(
        url: 'https://example.supabase.co',
        anonKey: 'public-anon-key',
      ).isConfigured,
      isTrue,
    );
  });

  test(
    'unconfigured Supabase adapter initializes safely and idempotently',
    () async {
      final source = SupabaseCloudDataSource(
        configuration: const SupabaseConfig(url: '', anonKey: ''),
      );
      await source.initialize();
      await source.initialize();
      expect(source.cloudState, CloudState.notConfigured);
      expect(source.authState, AuthState.guest);
      await source.dispose();
    },
  );

  test('storage policy accepts only the current user path shape', () {
    const path = 'users/user-a/messages/message-a/attachment-a-photo.jpg';
    expect(CloudStoragePathPolicy.isOwnedBy(path, 'user-a'), isTrue);
    expect(CloudStoragePathPolicy.isOwnedBy(path, 'user-b'), isFalse);
    expect(
      CloudStoragePathPolicy.isOwnedBy(
        'users/user-a/messages/message-a/../private.txt',
        'user-a',
      ),
      isFalse,
    );
    expect(
      CloudStoragePathPolicy.forAttachment(
        userId: 'user-a',
        messageId: 'message-a',
        attachmentId: 'attachment-a',
        fileName: 'photo from guest.jpg',
      ),
      'users/user-a/messages/message-a/attachment-a-photo_from_guest.jpg',
    );
  });

  test('Cloud errors map to safe stable codes without backend payloads', () {
    final auth = CloudErrorMapper.map(
      const AuthException('sensitive backend detail', statusCode: '401'),
    );
    expect(auth.code, 'auth');
    expect(auth.message, isNot(contains('sensitive')));

    final network = CloudErrorMapper.map(
      TimeoutException('private request detail'),
    );
    expect(network.code, 'offline');
    expect(network.message, isNot(contains('private')));
  });

  test('FakeCloud enforces server-side message account isolation', () async {
    final cloud = FakeCloudDataSource();
    addTearDown(cloud.dispose);
    await cloud.register(email: 'a@example.com', password: 'password');
    await cloud.upsertMessage(_message(senderId: 'fake-1'));
    await cloud.signOut();
    await cloud.register(email: 'b@example.com', password: 'password');

    await expectLater(
      cloud.fetchMessage('message-a'),
      throwsA(
        isA<CloudException>().having(
          (error) => error.code,
          'code',
          'permissionDenied',
        ),
      ),
    );
    await expectLater(
      cloud.upsertMessage(_message(senderId: 'fake-1')),
      throwsA(isA<CloudException>()),
    );
  });

  test(
    'FakeCloud rejects attachment paths outside the current account',
    () async {
      final cloud = FakeCloudDataSource();
      addTearDown(cloud.dispose);
      await cloud.register(email: 'a@example.com', password: 'password');
      await expectLater(
        cloud.uploadAttachment(
          localPath: 'missing.jpg',
          storagePath: 'users/fake-2/messages/message-a/attachment.jpg',
        ),
        throwsA(
          isA<CloudException>().having(
            (error) => error.code,
            'code',
            'invalidPath',
          ),
        ),
      );
    },
  );
}

CloudMessageDto _message({required String senderId}) => CloudMessageDto(
  id: 'message-a',
  conversationId: 'conversation-a',
  senderId: senderId,
  senderDeviceId: 'device-a',
  messageType: 'text',
  content: 'test message',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  deliveryStatus: 'pending',
  isOutgoing: true,
);
