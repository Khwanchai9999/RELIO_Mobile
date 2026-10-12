import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/media/media_storage_service.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/core/sync/sync_engine.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

import 'support/nearby_pair.dart';
import 'support/recording_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'three contacts reuse pinned peers and the same conversations',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);
      await approve(pair);
      final key = (await pair.repositoriesB.nearbyDevices.getDevice(
        'device-a',
      ))!.publicIdentityKey;
      for (var contact = 2; contact <= 3; contact++) {
        await pair.serviceA.disconnect('endpoint-b');
        await waitFor(
          () => pair.serviceB.deviceIdForEndpoint('endpoint-a') == null,
        );
        pair.transportB.discoverPeer();
        await approveReconnect(pair);
        await identified(pair);
        expect(pair.serviceA.pendingConnectionRequests, isEmpty);
        expect(pair.serviceB.pendingConnectionRequests, isEmpty);
        expect(
          await pair.repositoriesA.nearbyDevices.listDevices(),
          hasLength(1),
        );
        expect(
          await pair.repositoriesB.nearbyDevices.listDevices(),
          hasLength(1),
        );
        expect(
          await pair.repositoriesA.conversations.listConversations(),
          hasLength(1),
        );
        expect(
          await pair.repositoriesB.conversations.listConversations(),
          hasLength(1),
        );
        expect(
          (await pair.repositoriesB.nearbyDevices.getDevice(
            'device-a',
          ))!.publicIdentityKey,
          key,
        );
      }
      expect(
        pair.transportB.sentPackets.where((t) => t == 'identityProof'),
        hasLength(3),
      );
    },
  );

  for (final blocked in [false, true]) {
    test(
      '${blocked ? 'block' : 'untrust'} disables rediscovery auto reconnect and retains history',
      () async {
        final pair = await HandshakePair.create();
        addTearDown(pair.close);
        await approve(pair);
        await pair.serviceA.disconnect('endpoint-b');
        await waitFor(
          () => pair.serviceB.deviceIdForEndpoint('endpoint-a') == null,
        );
        if (blocked) {
          await pair.repositoriesB.nearbyDevices.setBlocked('device-a', true);
        } else {
          await pair.repositoriesB.nearbyDevices.setTrusted('device-a', false);
        }
        final before = (await readEvents(pair.logsB)).length;
        pair.transportB.discoverPeer();
        await waitFor(
          () async => (await readEvents(
            pair.logsB,
          )).skip(before).any((e) => e['event'] == 'auto_reconnect_suppressed'),
        );
        expect(pair.serviceB.deviceIdForEndpoint('endpoint-a'), isNull);
        expect(
          (await pair.repositoriesB.nearbyDevices.getDevice(
            'device-a',
          ))!.autoReconnectEnabled,
          isFalse,
        );
        expect(
          await pair.repositoriesB.conversations.getConversation('device-a'),
          isNotNull,
        );
        if (!blocked) {
          await pair.serviceA.connect('endpoint-b');
          await waitFor(
            () => pair.serviceB.pendingConnectionRequests.isNotEmpty,
          );
          expect(pair.serviceB.deviceIdForEndpoint('endpoint-a'), isNull);
        }
      },
    );
  }

  test(
    'offline pending text retries the original UUID and receives one ACK',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);
      await approve(pair);
      await pair.serviceA.disconnect('endpoint-b');
      await waitFor(
        () => pair.serviceA.deviceIdForEndpoint('endpoint-b') == null,
      );
      final sent = await pair.repositoriesA.messages.createOutgoingText(
        conversationId: 'device-b',
        senderId: 'user-a',
        senderDeviceId: 'device-a',
        text: 'ถึงไหนแล้ว',
      );
      await pair.serviceA.sendMessage(sent);
      final bubbles = await pair.repositoriesA.messages
          .watchMessages('device-b')
          .first;
      expect(bubbles.single.id, sent.id);
      expect(bubbles.single.status, DeliveryStatus.pending);
      pair.transportB.discoverPeer();
      await approveReconnect(pair);
      await waitFor(
        () async =>
            (await pair.repositoriesA.messages.getMessage(sent.id))?.status ==
            DeliveryStatus.delivered,
      );
      expect(
        (await pair.repositoriesA.messages.listMessages('device-b')).single.id,
        sent.id,
      );
      expect(
        (await pair.repositoriesB.messages.listMessages('device-a')).single.id,
        sent.id,
      );
    },
  );

  for (final mode in [
    'preview',
    'private',
    'active',
    'other-screen',
    'background',
  ]) {
    test(
      'notification decision follows persistence and visibility: $mode',
      () async {
        final sink = RecordingNotifications();
        addTearDown(sink.taps.close);
        final pair = await HandshakePair.create(notificationsB: sink);
        addTearDown(pair.close);
        await approve(pair);
        await pair.repositoriesB.settings.setBool(
          'notification_preview',
          mode != 'private',
        );
        sink.beforeShow = (id) async =>
            expect(await pair.repositoriesB.messages.getMessage(id), isNotNull);
        pair.serviceB.setActiveConversation(
          mode == 'preview' || mode == 'private' ? null : 'device-a',
        );
        pair.serviceB.updateLifecycleContext(
          lifecycleState: mode == 'background' ? 'paused' : 'resumed',
          route: mode == 'other-screen' ? '/settings' : '/chat/device-a',
        );
        final packet = RelioPacket.textMessage(
          senderDeviceId: 'device-a',
          senderUserId: 'user-a',
          messageId: 'message-$mode',
          conversationId: 'device-b',
          text: 'ถึงไหนแล้ว',
          timestamp: DateTime.now(),
        );
        pair.transportB.receivePacket(packet);
        await waitFor(
          () =>
              pair.transportB.packets.any((p) => p.type == RelioPacketType.ack),
        );
        expect(
          await pair.repositoriesB.messages.getMessage('message-$mode'),
          isNotNull,
        );
        final conversation = (await pair.repositoriesB.conversations
            .getConversation('device-a'))!;
        if (mode == 'active') {
          expect(sink.shown, isEmpty);
          expect(conversation.unreadCount, 0);
        } else {
          expect(sink.shown, hasLength(1));
          expect(sink.shown.single.title, 'สมชาย');
          expect(
            sink.shown.single.body,
            mode == 'private' ? 'คุณมีข้อความใหม่' : 'ถึงไหนแล้ว',
          );
          expect(sink.shown.single.route, '/chat/device-a');
          expect(conversation.unreadCount, 1);
        }
      },
    );
  }

  for (final cloudFirst in [false, true]) {
    test(
      'Nearby and Cloud dedupe UUID including notification cloudFirst=$cloudFirst',
      () async {
        final sink = RecordingNotifications();
        addTearDown(sink.taps.close);
        final pair = await HandshakePair.create(notificationsB: sink);
        addTearDown(pair.close);
        await approve(pair);
        final cloud = FakeCloudDataSource();
        addTearDown(cloud.dispose);
        final accountB = await cloud.register(
          email: 'b@example.com',
          password: 'test-password',
        );
        final accountA = cloud.createTestIdentity(
          email: 'a@example.com',
          displayName: 'สมชาย',
        );
        final engine = SyncEngine(
          repositories: pair.repositoriesB,
          cloud: cloud,
          identity: RelioDeviceIdentityRepository(pair.databaseB),
          mediaStorage: MediaStorageService(
            rootDirectory: pair.logsB.directory,
          ),
          localNotifications: sink,
        );
        addTearDown(engine.dispose);
        final link = await engine.linkConversationToCloud(
          localConversationId: 'device-a',
          peerUserId: accountA.userId,
        );
        await cloud.signIn(email: accountA.email, password: 'password');
        final now = DateTime.now().toUtc();
        await cloud.upsertMessage(
          CloudMessageDto(
            id: 'shared-uuid',
            conversationId: link.cloudConversationId,
            senderId: accountA.userId,
            senderDeviceId: 'device-a',
            messageType: 'text',
            content: 'ถึงไหนแล้ว',
            createdAt: now,
            updatedAt: now,
            deliveryStatus: 'delivered',
            isOutgoing: true,
          ),
        );
        await cloud.signIn(email: accountB.email, password: 'test-password');
        final packet = RelioPacket.textMessage(
          senderDeviceId: 'device-a',
          senderUserId: accountA.userId,
          messageId: 'shared-uuid',
          conversationId: 'device-b',
          text: 'ถึงไหนแล้ว',
          timestamp: now,
        );
        if (cloudFirst) {
          await engine.initialize();
          await engine.run();
        }
        for (var i = 0; i < 3; i++) {
          pair.transportB.receivePacket(packet);
        }
        await waitFor(
          () =>
              pair.transportB.packets
                  .where((p) => p.type == RelioPacketType.ack)
                  .length ==
              3,
        );
        if (!cloudFirst) {
          await engine.initialize();
        }
        await engine.run();
        expect(
          await pair.repositoriesB.messages.watchMessages('device-a').first,
          hasLength(1),
        );
        expect(
          (await pair.repositoriesB.conversations.getConversation(
            'device-a',
          ))!.unreadCount,
          1,
        );
        expect(sink.shown, hasLength(1));
      },
    );
  }
}

Future<void> approveReconnect(HandshakePair pair) async {
  await waitFor(
    () =>
        pair.serviceA.pendingConnectionRequests.isNotEmpty ||
        pair.serviceB.pendingConnectionRequests.isNotEmpty,
  );
  for (final endpoint
      in pair.serviceA.pendingConnectionRequests.keys.toList()) {
    await pair.serviceA.acceptConnectionRequest(endpoint);
  }
  for (final endpoint
      in pair.serviceB.pendingConnectionRequests.keys.toList()) {
    await pair.serviceB.acceptConnectionRequest(endpoint);
  }
}

Future<void> approve(HandshakePair pair) async {
  await pair.serviceA.connect('endpoint-b');
  await waitFor(
    () => pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
  );
  await pair.serviceB.acceptConnectionRequest('endpoint-a');
  await identified(pair);
}

Future<void> identified(HandshakePair pair) async {
  await waitFor(
    () =>
        pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
        pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
  );
  await waitFor(
    () async =>
        (await pair.repositoriesB.conversations.getConversation('device-a')) !=
        null,
  );
}
