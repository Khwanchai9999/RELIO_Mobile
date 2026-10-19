import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/cloud/auth_service.dart';
import 'package:relio_mobile/core/identity/owner_context.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/core/repositories/profile_avatar_repository.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'support/nearby_pair.dart';

class DelayedProfileCloud extends FakeCloudDataSource {
  Completer<void>? gate;
  Completer<void>? requested;
  @override
  Future<CloudProfile> fetchMyProfile() async {
    final result = await super.fetchMyProfile();
    final wait = gate;
    if (wait != null) {
      requested?.complete();
      await wait.future;
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'duplicate auth event cancelling profile refresh does not fail login',
    () async {
      final cloud = FakeCloudDataSource();
      addTearDown(cloud.dispose);
      final account = await cloud.register(
        email: 'race@qa.test',
        password: 'password',
      );
      await cloud.signOut();
      final auth = CloudAuthService(
        cloud,
        rebind: () async {
          throw const OwnerChangedException();
        },
      );
      final result = await auth.signIn(
        email: 'race@qa.test',
        password: 'password',
      );
      expect(result.userId, account.userId);
      expect(auth.state, AuthState.authenticated);
      expect(auth.identity?.userId, account.userId);
    },
  );

  test(
    'profile rebind cancellation cannot hide a real account switch',
    () async {
      final cloud = FakeCloudDataSource();
      addTearDown(cloud.dispose);
      await cloud.register(email: 'race@qa.test', password: 'password');
      await cloud.signOut();
      final auth = CloudAuthService(
        cloud,
        rebind: () async {
          await cloud.signOut();
          throw const OwnerChangedException();
        },
      );
      await expectLater(
        auth.signIn(email: 'race@qa.test', password: 'password'),
        throwsA(isA<OwnerChangedException>()),
      );
      expect(auth.identity, isNull);
    },
  );

  test(
    'A B Guest profiles, avatars and histories remain isolated offline',
    () async {
      String? active;
      final changes = StreamController<Object?>.broadcast(sync: true);
      final db = AppDatabase.memory();
      final repos = RelioRepositories(
        db,
        ownerUserIdProvider: () => active,
        ownerScopeChanges: changes.stream,
      );
      final identity = RelioDeviceIdentityRepository(
        db,
        profiles: repos.profiles,
      );
      final root = await Directory.systemTemp.createTemp('relio-principals-');
      final avatars = ProfileAvatarRepository(
        db,
        rootDirectory: root,
        profiles: repos.profiles,
      );
      addTearDown(() async {
        repos.profiles.dispose();
        await repos.ownerContext.dispose();
        await changes.close();
        await db.close();
        await root.delete(recursive: true);
      });
      final png = File('${root.path}/source.png');
      final recorder = ui.PictureRecorder();
      ui.Canvas(
        recorder,
      ).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
      final picture = recorder.endRecording();
      final image = await picture.toImage(1, 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await png.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      final device = await identity.getDeviceId();
      await repos.nearbyDevices.upsert(
        deviceId: 'bob-device',
        displayName: 'Bob',
        status: DeviceStatus.normal,
      );
      await repos.nearbyDevices.setTrustedIdentity(
        deviceId: 'bob-device',
        publicIdentityKey: 'existing-key',
        fingerprint: 'a' * 64,
      );
      final rooms = <String, String>{};
      final images = <String, String>{};
      final attachmentIds = <String, String>{};
      for (final entry in <String?, String>{
        null: 'GuestOne',
        'a': 'Jane',
        'b': 'Minnie',
      }.entries) {
        active = entry.key;
        changes.add(null);
        await identity.setDisplayName(entry.value);
        images[entry.value] = await avatars.storePickedImage(XFile(png.path));
        final room = await repos.conversations.ensureConversation(
          id: 'bob-device',
          participantId: 'bob-device',
          displayName: 'Bob',
          remotePrincipalId: 'account:bob',
          participantStatus: DeviceStatus.normal,
        );
        rooms[entry.value] = room.id;
        final message = await repos.messages.createOutgoingText(
          conversationId: room.id,
          senderId: active ?? device,
          senderDeviceId: device,
          text: '${entry.value} private',
        );
        final attachment = await repos.attachments.createPending(
          id: 'attachment-${entry.value}',
          conversationId: room.id,
          messageId: message.id,
          transferId: 'transfer-${entry.value}',
          mediaType: MediaType.image,
          fileName: 'source.png',
          mimeType: 'image/png',
          localPath: png.path,
          byteSize: await png.length(),
        );
        attachmentIds[entry.value] = attachment.id;
      }
      expect(rooms.values.toSet(), hasLength(3));
      for (final entry in [
        const MapEntry<String?, String>('a', 'Jane'),
        const MapEntry<String?, String>('b', 'Minnie'),
        const MapEntry<String?, String>(null, 'GuestOne'),
        const MapEntry<String?, String>('a', 'Jane'),
      ]) {
        active = entry.key;
        changes.add(null);
        expect(await identity.getDisplayName(), entry.value);
        expect(await avatars.getAvatarPath(), images[entry.value]);
        final room = await repos.conversations.resolveRouteTarget(
          rooms[entry.value]!,
        );
        expect(
          (await repos.messages.listMessages(room.id)).single.text,
          '${entry.value} private',
        );
        for (final other in rooms.entries.where((e) => e.key != entry.value)) {
          expect(
            await repos.conversations.getConversation(other.value),
            isNull,
          );
          expect(await repos.messages.listMessages(other.value), isEmpty);
          expect(
            await repos.attachments.getById(attachmentIds[other.key]!),
            isNull,
          );
        }
      }
      active = 'b';
      changes.add(null);
      await avatars.removeAvatar();
      expect(await File(images['Jane']!).exists(), isTrue);
      expect(await File(images['GuestOne']!).exists(), isTrue);
      expect(await identity.getDeviceId(), device);
      final trust = (await repos.nearbyDevices.getDevice('bob-device'))!;
      expect(trust.publicIdentityKey, 'existing-key');
      expect(trust.publicIdentityFingerprint, 'a' * 64);
      expect(trust.isTrusted, isTrue);
    },
  );

  test(
    'delayed A Cloud profile cannot replace B or a newer local edit',
    () async {
      final cloud = DelayedProfileCloud();
      await cloud.register(
        email: 'a@profile.test',
        password: 'password',
        displayName: 'Jane',
      );
      await cloud.register(
        email: 'b@profile.test',
        password: 'password',
        displayName: 'Minnie',
      );
      final deps = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(),
        cloudDataSource: cloud,
      );
      addTearDown(deps.dispose);
      await deps.repositories.profiles.refresh();
      expect(await deps.identity.getDisplayName(), 'Minnie');
      await cloud.signIn(email: 'a@profile.test', password: 'password');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final oldGate = Completer<void>();
      cloud.gate = oldGate;
      cloud.requested = Completer<void>();
      final stale = deps.repositories.profiles.refresh().catchError(
        (Object _) {},
      );
      await cloud.requested!.future;
      cloud.gate = null;
      await deps.authService.signIn(
        email: 'b@profile.test',
        password: 'password',
      );
      expect(await deps.identity.getDisplayName(), 'Minnie');
      oldGate.complete();
      await stale;
      expect(await deps.identity.getDisplayName(), 'Minnie');
      final editGate = Completer<void>();
      cloud.gate = editGate;
      cloud.requested = Completer<void>();
      final oldProfile = deps.repositories.profiles.refresh();
      await cloud.requested!.future;
      await deps.identity.setDisplayName('Minnie edited offline');
      cloud.gate = null;
      editGate.complete();
      await oldProfile;
      expect(await deps.identity.getDisplayName(), 'Minnie edited offline');
    },
  );

  test(
    'profile sync keeps an immutable owner name across account switch',
    () async {
      final cloud = FakeCloudDataSource();
      final deps = RelioDependencies(
        database: AppDatabase.memory(),
        transport: MockNearbyTransport(),
        cloudDataSource: cloud,
      );
      addTearDown(deps.dispose);
      final a = await deps.authService.register(
        email: 'a@snapshot.test',
        password: 'password',
        displayName: 'Jane',
      );
      await deps.identity.setDisplayName('Jane local edit');
      final b = await deps.authService.register(
        email: 'b@snapshot.test',
        password: 'password',
        displayName: 'Minnie',
      );
      final snapshots = await deps.database
          .customSelect('SELECT * FROM profile_sync_snapshots')
          .get();
      expect(snapshots.single.read<String>('owner_user_id'), a.userId);
      expect(snapshots.single.read<String>('display_name'), 'Jane local edit');
      await deps.syncEngine.run();
      expect(cloud.profiles[a.userId]!.displayName, 'Jane');
      expect(cloud.profiles[b.userId]!.displayName, 'Minnie');
      await deps.authService.signIn(
        email: 'a@snapshot.test',
        password: 'password',
      );
      await deps.syncEngine.run();
      expect(cloud.profiles[a.userId]!.displayName, 'Jane local edit');
      expect(cloud.profiles[b.userId]!.displayName, 'Minnie');
    },
  );

  test(
    'remote Jane to Minnie changes logical chat without resetting trust or transport',
    () async {
      String? active = 'jane';
      final changes = StreamController<Object?>.broadcast(sync: true);
      final pair = await HandshakePair.create(
        requireBothNativeAccepts: true,
        currentUserIdProviderA: () => active,
        ownerChangesA: changes.stream,
        displayNameA: 'Jane',
      );
      addTearDown(() async {
        await pair.close();
        await changes.close();
      });
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
      await waitFor(
        () async => (await pair.repositoriesB.conversations.listConversations())
            .any((r) => r.displayName == 'Jane'),
      );
      final janeRoom =
          (await pair.repositoriesB.conversations.listConversations()).single;
      final pin = (await pair.repositoriesB.nearbyDevices.getDevice(
        'device-a',
      ))!.publicIdentityFingerprint;
      final proofCount = pair.transportA.sentPackets
          .where((p) => p == 'identityProof')
          .length;
      active = 'minnie';
      changes.add(null);
      await waitFor(
        () async =>
            (await pair.repositoriesA.profiles.current()).principalId ==
            'account:minnie',
      );
      await pair.identityA.setDisplayName('Minnie');
      await waitFor(
        () async => (await pair.repositoriesB.conversations.listConversations())
            .any((r) => r.displayName == 'Minnie'),
      );
      final rooms = await pair.repositoriesB.conversations.listConversations();
      expect(rooms, hasLength(2));
      expect(rooms.singleWhere((r) => r.id == janeRoom.id).displayName, 'Jane');
      final bob = (await pair.repositoriesB.profiles.current()).principalId;
      final stale = RelioPacket.textMessage(
        senderDeviceId: 'device-b',
        senderUserId: 'bob',
        messageId: 'to-jane-while-minnie',
        conversationId: janeRoom.id,
        text: 'private Jane',
        timestamp: DateTime.now(),
      ).withPrincipals(bob, 'account:jane');
      pair.transportA.receivePacket(stale);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        await pair.repositoriesA.messages.getMessage(
          stale.payload['messageId']! as String,
        ),
        isNull,
      );
      expect(
        await pair.databaseA.select(pair.databaseA.messages).get(),
        isEmpty,
      );
      pair.transportA.receivePacket(
        RelioPacket.textMessage(
          senderDeviceId: 'device-b',
          senderUserId: 'bob',
          messageId: 'legacy-private-without-principals',
          conversationId: janeRoom.id,
          text: 'legacy',
          timestamp: DateTime.now(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        await pair.databaseA.select(pair.databaseA.messages).get(),
        isEmpty,
      );
      final valid = RelioPacket.textMessage(
        senderDeviceId: 'device-b',
        senderUserId: 'bob',
        messageId: 'to-minnie',
        conversationId: 'device-b',
        text: 'Minnie only',
        timestamp: DateTime.now(),
      ).withPrincipals(bob, 'account:minnie');
      pair.transportA.receivePacket(valid);
      await waitFor(
        () async =>
            await pair.repositoriesA.messages.getMessage('to-minnie') != null,
      );
      active = 'jane';
      changes.add(null);
      await pair.identityA.setDisplayName('Jane');
      expect(await pair.repositoriesA.messages.getMessage('to-minnie'), isNull);
      await waitFor(
        () async =>
            (await pair.repositoriesB.conversations.resolveRouteTarget(
              'device-a',
            )).id ==
            janeRoom.id,
      );

      expect(
        pair.transportA.sentPackets.where((p) => p == 'identityProof').length,
        proofCount,
      );
      expect(pair.serviceA.isDeviceConnected('device-b'), isTrue);
      expect(
        (await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        ))!.publicIdentityFingerprint,
        pin,
      );
    },
  );

  test(
    'delayed media completion is discarded after A to B to A epoch change',
    () async {
      String? active = 'a';
      final changes = StreamController<Object?>.broadcast(sync: true);
      final pair = await HandshakePair.create(
        requireBothNativeAccepts: true,
        currentUserIdProviderA: () => active,
        ownerChangesA: changes.stream,
      );
      addTearDown(() async {
        await pair.close();
        await changes.close();
      });
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
      await waitFor(
        () async => (await pair.repositoriesB.conversations.listConversations())
            .isNotEmpty,
      );
      final room = await pair.repositoriesB.conversations.resolveRouteTarget(
        'device-a',
      );
      final file = File('${pair.logsB.directory!.path}/delayed.png');
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII=',
      );
      await file.writeAsBytes(bytes);
      final attachment = await pair.repositoriesB.attachments.createPending(
        id: 'delayed-attachment',
        conversationId: room.id,
        messageId: 'delayed-message',
        transferId: 'delayed-transfer',
        mediaType: MediaType.image,
        fileName: 'delayed.png',
        mimeType: 'image/png',
        localPath: file.path,
        byteSize: bytes.length,
      );
      final message = await pair.repositoriesB.messages.createOutgoingMedia(
        conversationId: room.id,
        senderId: 'bob',
        senderDeviceId: 'device-b',
        type: MessageType.image,
        fileName: 'delayed.png',
        localPath: file.path,
        attachmentId: attachment.id,
        messageId: attachment.messageId,
      );
      pair.transportB.holdFiles = true;
      await pair.serviceB.sendMediaMessage(message, attachment);
      await waitFor(
        () async => (await readEvents(
          pair.logsA,
        )).any((e) => e['event'] == 'media_metadata_received'),
      );
      active = 'b';
      changes.add(null);
      await pair.identityA.setDisplayName('B');
      active = 'a';
      changes.add(null);
      await pair.identityA.setDisplayName('A again');
      pair.transportB.holdFiles = false;
      await pair.transportB.deliverFiles();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        await pair.databaseA.select(pair.databaseA.messages).get(),
        isEmpty,
      );
      expect(
        await pair.databaseA.select(pair.databaseA.attachments).get(),
        isEmpty,
      );
    },
  );

  test(
    'v9 migration preserves legacy data and quarantines absent or conflicting ownership',
    () async {
      final root = await Directory.systemTemp.createTemp('relio-v9-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/db.sqlite');
      final old = AppDatabase.withExecutor(NativeDatabase(file));
      await old.customSelect('SELECT 1').get();
      final now = DateTime(2025);
      await old
          .into(old.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'device_id',
              value: 'keep-device',
              updatedAt: now,
            ),
          );
      await old
          .into(old.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'display_name',
              value: 'Legacy Jane',
              updatedAt: now,
            ),
          );
      await old
          .into(old.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'profile_avatar_path',
              value: '/keep/avatar.png',
              updatedAt: now,
            ),
          );
      for (final id in ['unknown', 'known', 'conflict']) {
        await old
            .into(old.conversations)
            .insert(
              ConversationsCompanion.insert(
                id: id,
                participantId: 'peer',
                displayName: 'Keep $id',
                participantStatus: 'normal',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await old
            .into(old.messages)
            .insert(
              MessagesCompanion.insert(
                id: 'm-$id',
                conversationId: id,
                senderId: 'a',
                messageType: 'text',
                content: 'keep content',
                createdAt: now,
                updatedAt: now,
                deliveryStatus: 'pending',
                isOutgoing: true,
              ),
            );
        if (id != 'unknown') {
          await old.customStatement(
            'INSERT INTO conversation_scopes VALUES (?,?,?)',
            [id, 'a', id],
          );
        }
      }
      await old
          .into(old.syncQueue)
          .insert(
            SyncQueueCompanion.insert(
              id: 'conflict-q',
              entityType: 'message',
              entityId: 'm-conflict',
              operation: 'messageUpsert',
              status: 'pending',
              ownerUserId: const Value('b'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await old
          .into(old.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: 'keep-attachment',
              messageId: 'm-known',
              transferId: 'keep-transfer',
              mediaType: 'image',
              fileName: 'keep.jpg',
              mimeType: 'image/jpeg',
              localPath: '/keep/media.jpg',
              byteSize: 123,
              transferStatus: 'completed',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final peers = DriftNearbyDeviceRepository(old);
      await peers.upsert(
        deviceId: 'keep-peer',
        displayName: 'Peer',
        status: DeviceStatus.normal,
      );
      await peers.setTrustedIdentity(
        deviceId: 'keep-peer',
        publicIdentityKey: 'keep-key',
        fingerprint: 'b' * 64,
      );
      for (final table in [
        'conversation_principals',
        'local_principal_profiles',
        'remote_principal_profiles',
        'nearby_active_principals',
        'profile_sync_snapshots',
        'queue_principals',
      ]) {
        await old.customStatement('DROP TABLE $table');
      }
      await old.customStatement('PRAGMA user_version=9');
      await old.close();
      final db = AppDatabase.withExecutor(NativeDatabase(file));
      String? active;
      final repos = RelioRepositories(db, ownerUserIdProvider: () => active);
      addTearDown(db.close);
      expect(await repos.conversations.listConversations(), isEmpty);
      active = 'a';
      expect((await repos.conversations.listConversations()).map((r) => r.id), [
        'known',
      ]);
      expect(await db.select(db.messages).get(), hasLength(3));
      final attachment = (await db.select(db.attachments).get()).single;
      expect(attachment.id, 'keep-attachment');
      expect(attachment.localPath, '/keep/media.jpg');
      expect(attachment.createdAt, now);
      expect(
        (await repos.nearbyDevices.getDevice(
          'keep-peer',
        ))!.publicIdentityFingerprint,
        'b' * 64,
      );

      expect(
        (await db.select(db.appSettings).get())
            .singleWhere((r) => r.key == 'device_id')
            .value,
        'keep-device',
      );
      final legacy = await db
          .customSelect(
            "SELECT * FROM local_principal_profiles WHERE kind='legacyUnknown'",
          )
          .getSingle();
      expect(legacy.read<String>('display_name'), 'Legacy Jane');
      expect(legacy.read<String>('avatar_path'), '/keep/avatar.png');
      expect(db.schemaVersion, 11);
    },
  );
}
