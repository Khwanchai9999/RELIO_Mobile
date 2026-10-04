import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'SQLite chat and pending UUID survive disconnect and service/database restart',
    () async {
      final root = await Directory.systemTemp.createTemp('relio-chat-restart-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/chat.sqlite');
      var db = AppDatabase.withExecutor(NativeDatabase(file));
      var repos = RelioRepositories(db);
      NearbyService serviceFor(AppDatabase db, RelioRepositories repos) =>
          NearbyService(
            transport: MockNearbyTransport(),
            messages: repos.messages,
            conversations: repos.conversations,
            identity: RelioDeviceIdentityRepository(db),
            nearbyDevices: repos.nearbyDevices,
          );
      var service = serviceFor(db, repos);
      await service.initialize();
      await repos.conversations.ensureConversation(
        id: 'persistent-room',
        participantId: 'peer-device',
        displayName: 'สมชาย',
        participantStatus: DeviceStatus.normal,
      );
      final message = await repos.messages.createOutgoingText(
        conversationId: 'persistent-room',
        senderId: 'self',
        senderDeviceId: 'self-device',
        text: 'ข้อความที่รอส่ง',
      );
      await service.disconnect('temporary-endpoint');
      await service.close();
      await db.close();
      db = AppDatabase.withExecutor(NativeDatabase(file));
      repos = RelioRepositories(db);
      service = serviceFor(db, repos);
      await service.initialize();
      addTearDown(() async {
        await service.close();
        await db.close();
      });
      expect(service.connectedPeerCount, 0);
      expect(
        (await repos.conversations.listConversations()).single.id,
        'persistent-room',
      );
      final bubbles = await repos.messages
          .watchMessages('persistent-room')
          .first;
      expect(bubbles.single.id, message.id);
      expect(bubbles.single.text, 'ข้อความที่รอส่ง');
      expect(bubbles.single.status, DeliveryStatus.pending);
    },
  );
}
