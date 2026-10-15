import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/chat/chat_screens.dart';
import 'package:relio_mobile/features/profile/profile_screen.dart';

void main() {
  testWidgets(
    'private image viewer hides its captured file after owner switch',
    (tester) async {
      final cloud = FakeCloudDataSource();
      await cloud.register(email: 'a@viewer.test', password: 'password');
      await cloud.register(email: 'b@viewer.test', password: 'password');
      await cloud.signIn(email: 'a@viewer.test', password: 'password');
      final deps = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(),
        cloudDataSource: cloud,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await deps.dispose();
      });
      final room = await deps.repositories.conversations.ensureConversation(
        id: 'viewer-peer',
        participantId: 'viewer-peer',
        remotePrincipalId: 'account:bob',
        displayName: 'Bob',
        participantStatus: DeviceStatus.normal,
      );
      await deps.repositories.messages.createOutgoingMedia(
        conversationId: room.id,
        senderId: cloud.currentIdentity!.userId,
        senderDeviceId: 'local',
        type: MessageType.image,
        fileName: 'private.png',
        localPath: 'missing-private-image.png',
        attachmentId: 'private-attachment',
        messageId: 'private-media',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: deps,
            child: ChatRoomScreen(chatId: room.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('เปิดรูปภาพเต็มจอ'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await deps.authService.signIn(
        email: 'b@viewer.test',
        password: 'password',
      );
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    },
  );

  testWidgets(
    'open chat clears A header and message shell under B, restores A',
    (tester) async {
      final cloud = FakeCloudDataSource();
      await cloud.register(
        email: 'a@ui.test',
        password: 'password',
        displayName: 'Jane',
      );
      await cloud.register(
        email: 'b@ui.test',
        password: 'password',
        displayName: 'Minnie',
      );
      await cloud.signIn(email: 'a@ui.test', password: 'password');
      final deps = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(),
        cloudDataSource: cloud,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await deps.dispose();
      });
      final room = await deps.repositories.conversations.ensureConversation(
        id: 'bob-device',
        participantId: 'bob-device',
        remotePrincipalId: 'account:bob',
        displayName: 'Bob private header',
        participantStatus: DeviceStatus.normal,
      );
      await deps.repositories.messages.createOutgoingText(
        conversationId: room.id,
        senderId: cloud.currentIdentity!.userId,
        senderDeviceId: 'local-device',
        text: 'Jane private body',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: deps,
            child: ChatRoomScreen(chatId: room.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bob private header'), findsOneWidget);
      expect(find.text('Jane private body'), findsOneWidget);
      await deps.authService.signIn(email: 'b@ui.test', password: 'password');
      await tester.pumpAndSettle();
      expect(find.text('Bob private header'), findsNothing);
      expect(find.text('Jane private body'), findsNothing);
      await deps.authService.signIn(email: 'a@ui.test', password: 'password');
      await tester.pumpAndSettle();
      expect(find.text('Bob private header'), findsOneWidget);
      expect(find.text('Jane private body'), findsOneWidget);
    },
  );

  testWidgets(
    'open profile rebinds Jane Minnie Guest without retaining old name',
    (tester) async {
      final cloud = FakeCloudDataSource();
      final deps = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(),
        cloudDataSource: cloud,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await deps.dispose();
      });
      await deps.identity.setDisplayName('GuestOne');
      await deps.authService.register(
        email: 'a@profile-ui.test',
        password: 'password',
        displayName: 'Jane',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: deps,
            child: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Jane'), findsOneWidget);
      await deps.authService.register(
        email: 'b@profile-ui.test',
        password: 'password',
        displayName: 'Minnie',
      );
      await tester.pumpAndSettle();
      expect(find.text('Jane'), findsNothing);
      expect(find.text('Minnie'), findsOneWidget);
      await deps.authService.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Minnie'), findsNothing);
      expect(find.text('GuestOne'), findsOneWidget);
    },
  );
}
