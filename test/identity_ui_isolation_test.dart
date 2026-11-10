import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/core/feature_flags/feature_flags.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/features/nearby/nearby_screen.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relay/relay_route_planner.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/chat/chat_screens.dart';
import 'package:relio_mobile/features/profile/profile_screen.dart';

void main() {
  testWidgets(
    'Nearby opens a new scoped chat after account switches on same hardware',
    (tester) async {
      final cloud = FakeCloudDataSource();
      await cloud.register(email: 'a@route.test', password: 'password');
      final db = AppDatabase.memory();
      final flags = FeatureFlagController(
        repository: FeatureFlagRepository(RelioSettingsRepository(db)),
        allowLocalOverrides: true,
      );
      await flags.initialize();
      await flags.setOverride(RelioFeatureFlag.nearbyMapUi, false);
      final deps = RelioDependencies(
        database: db,
        transport: MockNearbyTransport(),
        cloudDataSource: cloud,
        featureFlags: flags,
      );
      final old = await deps.repositories.conversations.ensureConversation(
        id: 'physical-bob',
        participantId: 'physical-bob',
        displayName: 'Jane private header',
        participantStatus: DeviceStatus.normal,
        remotePrincipalId: 'guest:bob',
      );
      await (deps.repositories.conversations as DriftConversationRepository)
          .rememberRemotePrincipal(
            'physical-bob',
            'guest:bob',
            'Bob scoped peer',
            1,
          );
      await deps.authService.register(
        email: 'b@route.test',
        password: 'password',
      );
      deps.nearbyService.discoveredPeers.add(
        const NearbyPeer(
          id: 'endpoint-bob',
          name: 'Bob scoped peer',
          deviceId: 'physical-bob',
          connected: true,
        ),
      );
      deps.nearbyService.peerStates['endpoint-bob'] =
          NearbyConnectionState.connected;
      final router = GoRouter(
        initialLocation: '/nearby',
        routes: [
          GoRoute(path: '/nearby', builder: (_, _) => const NearbyScreen()),
          GoRoute(
            path: '/chat/:id',
            builder: (_, state) =>
                ChatRoomScreen(chatId: state.pathParameters['id']!),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await deps.dispose();
      });
      await tester.pumpWidget(
        RelioDependencyScope(
          dependencies: deps,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.text('Bob scoped peer'));
      await tester.tap(find.text('Bob scoped peer'));
      await tester.pumpAndSettle();
      expect(find.text('Bob scoped peer'), findsOneWidget);
      expect(find.text('Jane private header'), findsNothing);
      final rooms = await deps.repositories.conversations.listConversations();
      expect(rooms, hasLength(1));
      expect(rooms.single.id, isNot(old.id));
      expect(
        await deps.repositories.conversations.getConversation(old.id),
        isNull,
      );
    },
  );
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('ไม่สามารถเปิดรูปภาพนี้ได้'), findsOneWidget);
      await deps.authService.signIn(
        email: 'b@viewer.test',
        password: 'password',
      );
      await tester.pumpAndSettle();
      expect(find.text('ไม่สามารถเปิดรูปภาพนี้ได้'), findsNothing);
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
      if (RelioBuildInfo.isTest) {
        await deps.nearbyService.configureTextRouteMode(
          RelayTextRouteMode.automatic,
        );
        expect(deps.nearbyService.qaPlaintextTextEnabled, isTrue);
      }
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
      expect(
        find.text('โหมดทดสอบ QA • ข้อความที่ผ่านรีเลย์ไม่เข้ารหัส'),
        findsNothing,
      );
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
