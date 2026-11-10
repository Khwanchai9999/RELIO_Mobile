import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/identity/owner_context.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'support/nearby_pair.dart';

class DelayedConversationCloud extends FakeCloudDataSource {
  Completer<void>? gate;
  final requested = Completer<void>();
  @override
  Future<List<CloudConversationDto>> listMyDirectConversations() async {
    final rows = await super.listMyDirectConversations();
    if (gate != null) {
      requested.complete();
      await gate!.future;
    }
    return rows;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'private message never chooses a connected device by display name',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () =>
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
            pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a' &&
            pair.serviceA.peerStates['endpoint-b'] ==
                NearbyConnectionState.connected &&
            pair.serviceB.peerStates['endpoint-a'] ==
                NearbyConnectionState.connected,
      );
      await pair.serviceA.acceptConnectionRequest('endpoint-b');
      await pair.serviceB.acceptConnectionRequest('endpoint-a');
      await waitFor(() => pair.serviceA.deviceToEndpointId['device-b'] != null);
      final room = await pair.repositoriesA.conversations.ensureConversation(
        id: 'absent-device',
        participantId: 'absent-device',
        displayName: 'Peer',
        participantStatus: DeviceStatus.normal,
      );
      final message = await pair.repositoriesA.messages.createOutgoingText(
        conversationId: room.id,
        senderId: 'device-a',
        senderDeviceId: 'device-a',
        text: 'private to absent device',
      );
      final before = pair.transportA.sentPackets
          .where((p) => p == 'textMessage')
          .length;
      await pair.serviceA.sendMessage(message);
      expect(
        pair.transportA.sentPackets.where((p) => p == 'textMessage').length,
        before,
      );
      expect(
        (await pair.repositoriesA.messages.getMessage(message.id))!.status,
        DeliveryStatus.pending,
      );
    },
  );
  // ป้องกันงาน async เก่ากลับมาใช้ได้เมื่อสลับ A ไป B แล้วกลับ A แม้ชื่อ owner จะตรงอีกครั้ง
  test('owner epoch rejects A to B to A async work', () async {
    var active = 'a';
    final changes = StreamController<Object?>.broadcast(sync: true);
    final context = OwnerContext(() => active, changes.stream);
    addTearDown(context.dispose);
    addTearDown(changes.close);
    final old = context.capture();
    active = 'b';
    changes.add(null);
    active = 'a';
    changes.add(null);
    expect(context.isCurrent(old), isFalse);
    expect(
      () => context.requireCurrent(old),
      throwsA(isA<OwnerChangedException>()),
    );
  });

  test('same-owner auth refresh does not invalidate in-flight work', () async {
    var active = 'jane';
    final changes = StreamController<Object?>.broadcast(sync: true);
    final context = OwnerContext(() => active, changes.stream);
    addTearDown(context.dispose);
    addTearDown(changes.close);

    final snapshot = context.capture();
    changes.add(null);

    expect(context.isCurrent(snapshot), isTrue);
    expect(context.capture().generation, snapshot.generation);

    active = 'minnie';
    changes.add(null);
    expect(context.isCurrent(snapshot), isFalse);
  });

  test(
    'new B subscriber never receives cached A conversation preview',
    () async {
      var active = 'a';
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final changes = StreamController<Object?>.broadcast(sync: true);
      addTearDown(changes.close);
      final repos = RelioRepositories(
        db,
        ownerUserIdProvider: () => active,
        ownerScopeChanges: changes.stream,
      );
      final room = await repos.conversations.ensureConversation(
        id: 'peer',
        participantId: 'peer',
        displayName: 'A private name',
        participantStatus: DeviceStatus.normal,
      );
      await repos.messages.createOutgoingText(
        conversationId: room.id,
        senderId: 'a',
        senderDeviceId: 'local',
        text: 'A private preview',
      );
      await repos.conversations.watchConversations().firstWhere(
        (r) => r.isNotEmpty,
      );
      active = 'b';
      changes.add(null);
      final first = await repos.conversations.watchConversations().first;
      expect(first, isEmpty);
    },
  );

  test(
    'A cloud import completing after B login creates no B row or A link',
    () async {
      final cloud = DelayedConversationCloud();
      final a = await cloud.register(
        email: 'a@example.test',
        password: 'RelioDemo123!',
      );
      final peer = cloud.createTestIdentity(email: 'peer@example.test');
      await cloud.createOrGetDirectConversation(peerUserId: peer.userId);
      await cloud.register(email: 'b@example.test', password: 'RelioDemo123!');
      await cloud.signIn(email: 'a@example.test', password: 'RelioDemo123!');
      final deps = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(),
        cloudDataSource: cloud,
      );
      addTearDown(deps.dispose);
      cloud.gate = Completer<void>();
      final run = deps.syncEngine.run();
      await cloud.requested.future;
      await cloud.signIn(email: 'b@example.test', password: 'RelioDemo123!');
      cloud.gate!.complete();
      await run;
      expect(
        await deps.repositories.conversations.listConversations(),
        isEmpty,
      );
      expect(
        await deps.repositories.cloudLinks.listForOwner(a.userId),
        isEmpty,
      );
    },
  );
}
