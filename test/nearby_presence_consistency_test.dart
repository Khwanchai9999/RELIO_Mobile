import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/feature_flags/feature_flags.dart';
import 'package:relio_mobile/core/nearby/nearby_readiness.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/presentation/peer_connection_presence.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/nearby/nearby_screen.dart';

const _ready = NearbyReadiness(
  policy: NearbyPermissionPolicy(34),
  legacyPermissionsGranted: true,
  bluetoothAvailable: true,
  bluetoothEnabled: true,
  wifiAvailable: true,
  wifiEnabled: true,
  playServicesStatus: 'available',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'one verified live peer stays online while six cached peers stay offline',
    () async {
      final database = AppDatabase.memory();
      final repositories = RelioRepositories(database);
      final identity = RelioDeviceIdentityRepository(database);
      final transport = MockNearbyTransport();
      late NearbyService service;

      Future<NearbyService> createService(NearbyTransport transport) async {
        final result = NearbyService(
          transport: transport,
          messages: repositories.messages,
          conversations: repositories.conversations,
          identity: identity,
          nearbyDevices: repositories.nearbyDevices,
        );
        await result.initialize();
        result.updateReadiness(_ready);
        return result;
      }

      for (var index = 0; index < 6; index++) {
        await repositories.nearbyDevices.upsert(
          deviceId: 'cached-$index',
          displayName: 'Cached peer $index',
          status: DeviceStatus.normal,
        );
      }
      await repositories.nearbyDevices.upsert(
        deviceId: 'live-device',
        displayName: 'Live peer',
        status: DeviceStatus.normal,
      );
      await repositories.conversations.ensureConversation(
        id: 'cached-0',
        participantId: 'cached-0',
        remotePrincipalId: 'guest:cached-0',
        displayName: 'Cached peer 0',
        participantStatus: DeviceStatus.normal,
      );
      await repositories.messages.createOutgoingText(
        conversationId: 'cached-0',
        senderId: 'local-user',
        senderDeviceId: 'local-device',
        text: 'Keep this history',
      );

      service = await createService(transport);
      addTearDown(() async {
        await service.close();
        await database.close();
      });

      transport.simulatePeer(
        id: 'live-endpoint',
        name: 'Live peer',
        deviceId: 'live-device',
      );
      transport.simulatePeer(
        id: 'cached-endpoint',
        name: 'Cached peer 0',
        deviceId: 'cached-0',
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.connectedPeerCount, 0);
      expect(
        service.presenceForDevice('cached-0'),
        PeerConnectionPresence.offline,
        reason: 'Discovery by itself is not an authenticated session.',
      );
      expect(
        service.presenceForDevice('live-device'),
        PeerConnectionPresence.offline,
      );
      service.updateReadiness(
        const NearbyReadiness(
          policy: NearbyPermissionPolicy(34),
          legacyPermissionsGranted: true,
          transportAvailable: false,
        ),
      );
      expect(
        service.presenceForDevice('cached-0'),
        PeerConnectionPresence.unknown,
      );
      service.updateReadiness(_ready);

      await service.connect('live-endpoint');
      await _waitFor(
        () =>
            service.presenceForDevice('live-device') ==
            PeerConnectionPresence.online,
      );

      expect(service.connectedPeerCount, 1);
      expect(
        service.presenceForPrincipal('live-device', 'guest:another-account'),
        PeerConnectionPresence.offline,
      );
      expect(
        service.presenceForPrincipal('live-device', null),
        PeerConnectionPresence.unknown,
      );
      expect(service.authenticatedConnectedPeers.map((peer) => peer.deviceId), [
        'live-device',
      ]);
      for (var index = 0; index < 6; index++) {
        expect(
          service.presenceForDevice('cached-$index'),
          PeerConnectionPresence.offline,
        );
      }

      transport.simulateConnectionLoss('live-endpoint');
      await _waitFor(() => service.connectedPeerCount == 0);
      expect(
        service.presenceForDevice('live-device'),
        PeerConnectionPresence.offline,
      );

      await service.close();
      service = await createService(MockNearbyTransport());
      expect(service.connectedPeerCount, 0);
      expect(
        service.presenceForDevice('live-device'),
        PeerConnectionPresence.offline,
        reason: 'A new service instance must not restore an old Online state.',
      );
      expect(
        (await repositories.conversations.listConversations())
            .single
            .participantId,
        'cached-0',
      );
      expect(
        (await repositories.messages.listMessages('cached-0')).single.text,
        'Keep this history',
      );
    },
  );

  testWidgets(
    'Nearby unified list counts live and historical peers without QA clutter',
    (tester) async {
      final database = AppDatabase.memory();
      final transport = MockNearbyTransport();
      final flags = FeatureFlagController(
        repository: FeatureFlagRepository(RelioSettingsRepository(database)),
        allowLocalOverrides: true,
      );
      await flags.initialize();
      await flags.setOverride(RelioFeatureFlag.nearbyMapUi, false);
      final dependencies = RelioDependencies(
        database: database,
        transport: transport,
        featureFlags: flags,
      );
      // This test covers the peer list, so model a prior explicit location
      // sharing refusal instead of allowing the first-use consent modal to
      // intercept the draggable sheet gestures.
      await dependencies.repositories.settings.setBool(
        'nearby_live_location_enabled',
        false,
      );
      for (var index = 0; index < 6; index++) {
        await database
            .into(database.nearbyDevices)
            .insert(
              NearbyDevicesCompanion.insert(
                deviceId: 'cached-$index',
                displayName: 'Cached peer $index',
                status: DeviceStatus.normal.name,
                lastSeenAt: DateTime.now().subtract(Duration(days: index + 2)),
              ),
            );
      }
      await dependencies.nearbyService.initialize();
      dependencies.nearbyService.updateReadiness(_ready);
      dependencies.nearbyService.discoveredPeers.addAll([
        const NearbyPeer(
          id: 'sos-endpoint',
          name: 'Active SOS peer',
          deviceId: 'active-sos',
        ),
        const NearbyPeer(
          id: 'rescue-endpoint',
          name: 'Active Rescue peer',
          deviceId: 'active-rescue',
        ),
      ]);
      dependencies.nearbyService.peerStatuses
        ..['active-sos'] = DeviceStatus.sos
        ..['active-rescue'] = DeviceStatus.rescue;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await dependencies.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: dependencies,
            child: const NearbyScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('ทั้งหมด (8)'), findsOneWidget);
      expect(find.text('SOS (1)'), findsOneWidget);
      expect(find.text('Rescue (1)'), findsOneWidget);
      expect(find.text('อุปกรณ์ที่เข้าถึงได้ • 0 เครื่อง'), findsOneWidget);
      expect(find.textContaining('เคยพบ'), findsNothing);
      expect(find.text('เครื่องมือ QA / Diagnostics'), findsNothing);
      final list = find.byType(ListView);
      final handle = find.byKey(const ValueKey('nearby-sheet-handle'));
      final before = tester.getTopLeft(handle).dy;
      await tester.drag(list, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(handle).dy, lessThan(before));
      await tester.drag(list, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(handle).dy, greaterThan(before));
      expect(find.text('ข้อมูลตัวอย่าง'), findsNothing);
      expect(find.text('สมชาย ใจดี'), findsNothing);

      await tester.ensureVisible(find.text('SOS (1)'));
      await tester.tap(find.text('SOS (1)'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('อุปกรณ์ที่เข้าถึงได้ • 0 เครื่อง'), findsOneWidget);
      expect(find.text('Active SOS peer'), findsOneWidget);
      expect(find.text('Active Rescue peer'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('Nearby and Chat share the same peer presence value', () {
    const deviceId = 'stable-canonical-device-id';
    final nearbyPresence = PeerConnectionPresence.offline;
    final nearbyDevice = RelioDevice(
      id: deviceId,
      name: 'Peer',
      status: DeviceStatus.normal,
      signalQuality: 0,
      isConnected: false,
      isDemo: false,
      presence: PeerPresence.stale,
      reportedConnectionPresence: nearbyPresence,
    );
    const chatPreview = RelioChatPreview(
      id: 'local-conversation-id',
      name: 'Peer',
      message: 'History remains visible',
      time: '',
      status: DeviceStatus.normal,
      unread: 0,
      identityKey: deviceId,
      presence: PeerConnectionPresence.offline,
    );

    expect(nearbyDevice.connectionPresence, chatPreview.presence);
    expect(chatPreview.identityKey, nearbyDevice.id);
    expect(chatPreview.message, 'History remains visible');
  });
}

Future<void> _waitFor(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Expected Nearby presence was not reached.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
