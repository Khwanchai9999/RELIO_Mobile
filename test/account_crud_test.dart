import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:relio_mobile/core/cloud/cloud_error_mapper.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/profile/profile_screen.dart';

class _CountingCloud extends FakeCloudDataSource {
  int deleteCalls = 0;

  @override
  Future<void> deleteMyAccount() async {
    deleteCalls++;
    await super.deleteMyAccount();
  }
}

void main() {
  test('delete errors map to safe account messages', () {
    final offline = CloudErrorMapper.map(
      const FunctionsFetchException(details: 'private transport detail'),
      fallbackCode: 'delete',
    );
    expect(offline.message, 'Cloud ไม่พร้อมใช้งาน');
    expect(offline.message, isNot(contains('private')));

    final expired = CloudErrorMapper.map(
      const FunctionsHttpException(status: 401, details: 'private auth detail'),
      fallbackCode: 'delete',
    );
    expect(expired.message, 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง');
    expect(expired.message, isNot(contains('private')));

    final blocked = CloudErrorMapper.map(
      const FunctionsHttpException(
        status: 409,
        details: 'private dependency detail',
      ),
      fallbackCode: 'delete',
    );
    expect(
      blocked.message,
      'ยังไม่สามารถลบบัญชีนี้ได้ เนื่องจากมีข้อมูลที่ระบบต้องตรวจสอบ',
    );
    expect(blocked.message, isNot(contains('private')));

    final failed = CloudErrorMapper.map(
      const FunctionsHttpException(
        status: 500,
        details: 'private server detail',
      ),
      fallbackCode: 'delete',
    );
    expect(failed.message, 'ไม่สามารถลบบัญชีได้ กรุณาลองใหม่');
    expect(failed.message, isNot(contains('private')));
  });

  test('profile reads and updates the authenticated account record', () async {
    final cloud = FakeCloudDataSource();
    addTearDown(cloud.dispose);
    final registered = await cloud.register(
      email: 'member@example.com',
      password: 'RelioDemo123!',
      displayName: 'Member One',
    );

    final before = await cloud.fetchMyProfile();
    expect(before.userId, registered.userId);
    expect(before.displayName, 'Member One');

    await cloud.upsertProfile(displayName: 'Member Updated');
    final after = await cloud.fetchMyProfile();
    expect(after.userId, registered.userId);
    expect(after.displayName, 'Member Updated');
  });

  test(
    'account deletion has no target parameter and preserves other users',
    () async {
      final backend = FakeCloudBackend();
      final deletingUser = FakeCloudDataSource(backend: backend);
      final otherUser = FakeCloudDataSource(backend: backend);
      final signedOut = FakeCloudDataSource(backend: backend);
      addTearDown(deletingUser.dispose);
      addTearDown(otherUser.dispose);
      addTearDown(signedOut.dispose);
      await deletingUser.register(
        email: 'delete-me@example.com',
        password: 'test-password',
        displayName: 'Delete Me',
      );
      await otherUser.register(
        email: 'keep-me@example.com',
        password: 'test-password',
        displayName: 'Keep Me',
      );
      final deletingUserId = deletingUser.currentIdentity!.userId;
      final conversation = await deletingUser.createOrGetDirectConversation(
        peerUserId: otherUser.currentIdentity!.userId,
      );
      await deletingUser.upsertMessage(
        CloudMessageDto(
          id: 'shared-message',
          conversationId: conversation.id,
          senderId: deletingUserId,
          senderDeviceId: 'device-a',
          messageType: 'text',
          content: 'Shared history',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          deliveryStatus: 'synced',
          isOutgoing: true,
        ),
      );

      await deletingUser.deleteMyAccount();
      expect(deletingUser.currentIdentity, isNull);
      expect(
        backend.profiles[conversation.participantId]?.displayName,
        'Keep Me',
      );
      expect(backend.profiles[deletingUserId]?.displayName, 'บัญชีที่ลบแล้ว');
      await expectLater(
        signedOut.signIn(
          email: 'delete-me@example.com',
          password: 'test-password',
        ),
        throwsA(isA<Exception>()),
      );
      await signedOut.signIn(
        email: 'keep-me@example.com',
        password: 'test-password',
      );
      expect((await signedOut.fetchMyProfile()).displayName, 'Keep Me');
      expect(
        (await signedOut.fetchMessages(conversation.id)).single.content,
        'Shared history',
      );
    },
  );

  testWidgets(
    'delete confirmation cancel preserves account; confirm deletes once',
    (tester) async {
      final cloud = _CountingCloud();
      final dependencies = RelioDependencies(
        database: AppDatabase.memory(),
        cloudDataSource: cloud,
        useMockTransport: true,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await dependencies.dispose();
      });
      await dependencies.initializeAuth();
      await cloud.register(
        email: 'member@example.com',
        password: 'RelioDemo123!',
        displayName: 'Member One',
      );
      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(path: '/login', builder: (_, _) => const Text('LOGIN PAGE')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              RelioDependencyScope(dependencies: dependencies, child: child!),
        ),
      );
      await tester.pumpAndSettle();

      expect(cloud.currentIdentity, isNotNull);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('โปรไฟล์'), findsOneWidget);
      expect(find.text('member@example.com'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ลบบัญชี').first);
      await tester.tap(find.text('ลบบัญชี').first);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'บัญชีนี้จะเข้าสู่ระบบไม่ได้อีก ข้อมูลตำแหน่งและอุปกรณ์จะถูกลบ '
          'ส่วนประวัติแชตจะยังอยู่ โดยเปลี่ยนชื่อเป็น “บัญชีที่ลบแล้ว”',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(cloud.deleteCalls, 0);
      expect(cloud.currentIdentity, isNotNull);

      await tester.ensureVisible(find.text('ลบบัญชี').first);
      await tester.tap(find.text('ลบบัญชี').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบบัญชี').last);
      await tester.pumpAndSettle();
      expect(cloud.deleteCalls, 1);
      expect(cloud.currentIdentity, isNull);
      expect(find.text('LOGIN PAGE'), findsOneWidget);
      await expectLater(
        cloud.signIn(email: 'member@example.com', password: 'RelioDemo123!'),
        throwsA(isA<Exception>()),
      );
    },
  );
}
