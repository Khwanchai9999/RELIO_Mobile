import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/device/battery_info_service.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/nearby/nearby_screen.dart';

import 'support/nearby_pair.dart';

Future<void> _firstPair(HandshakePair pair) async {
  await pair.serviceA.connect('endpoint-b');
  await waitFor(
    () =>
        pair.serviceA.pendingConnectionRequests.containsKey('endpoint-b') &&
        pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
  );
  expect(pair.transportA.acceptCalls, isEmpty);
  expect(pair.transportB.acceptCalls, isEmpty);
  await pair.serviceA.acceptConnectionRequest('endpoint-b');
  expect(
    pair.serviceA.peerStates['endpoint-b'],
    isNot(NearbyConnectionState.connected),
  );
  await pair.serviceB.acceptConnectionRequest('endpoint-a');
  await _waitConnected(pair);
}

Future<void> _waitConnected(HandshakePair pair) => waitFor(
  () =>
      pair.serviceA.peerStates['endpoint-b'] ==
          NearbyConnectionState.connected &&
      pair.serviceB.peerStates['endpoint-a'] ==
          NearbyConnectionState.connected &&
      pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
      pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'both native accepts are required; trusted reconnect survives 10 cycles',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await _firstPair(pair);

      for (var cycle = 0; cycle < 10; cycle++) {
        final acceptsA = pair.transportA.acceptCalls.length;
        final acceptsB = pair.transportB.acceptCalls.length;
        await pair.serviceA.disconnect('endpoint-b');
        await waitFor(
          () =>
              pair.serviceA.peerStates['endpoint-b'] ==
                  NearbyConnectionState.disconnected &&
              pair.serviceB.peerStates['endpoint-a'] ==
                  NearbyConnectionState.disconnected,
        );
        expect(pair.serviceA.deviceIdForEndpoint('endpoint-b'), isNull);
        expect(pair.serviceB.deviceIdForEndpoint('endpoint-a'), isNull);
        pair.transportA.discoverPeer();
        pair.transportB.discoverPeer();
        await _waitConnected(pair);
        expect(pair.transportA.acceptCalls.length, acceptsA + 1);
        expect(pair.transportB.acceptCalls.length, acceptsB + 1);
        expect(pair.serviceA.pendingConnectionRequests, isEmpty);
        expect(pair.serviceB.pendingConnectionRequests, isEmpty);
      }
    },
  );

  test(
    'failed native request clears pending state and next request works',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      pair.transportA.failNextRequest = true;
      await pair.serviceA.connect('endpoint-b');
      expect(
        pair.serviceA.peerStates['endpoint-b'],
        NearbyConnectionState.failed,
      );
      expect(pair.serviceA.pendingConnectionRequests, isEmpty);
      await _firstPair(pair);
    },
  );

  test('native failure clears approvals and permits retry', () async {
    final pair = await HandshakePair.create(requireBothNativeAccepts: true);
    addTearDown(pair.close);
    await pair.serviceA.connect('endpoint-b');
    await waitFor(
      () =>
          pair.serviceA.pendingConnectionRequests.containsKey('endpoint-b') &&
          pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
    );
    pair.transportA.failConnection();
    await waitFor(
      () =>
          pair.serviceA.peerStates['endpoint-b'] ==
              NearbyConnectionState.failed &&
          pair.serviceB.peerStates['endpoint-a'] ==
              NearbyConnectionState.failed,
    );
    expect(pair.serviceA.pendingConnectionRequests, isEmpty);
    expect(pair.serviceB.pendingConnectionRequests, isEmpty);
    await _firstPair(pair);
  });

  test('trust survives service recreation without a new prompt', () async {
    final pair = await HandshakePair.create(requireBothNativeAccepts: true);
    addTearDown(pair.close);
    await _firstPair(pair);
    await pair.serviceA.disconnect('endpoint-b');
    await waitFor(
      () =>
          pair.serviceB.peerStates['endpoint-a'] ==
          NearbyConnectionState.disconnected,
    );
    await pair.restartServices();
    await _waitConnected(pair);
    expect(pair.serviceA.pendingConnectionRequests, isEmpty);
    expect(pair.serviceB.pendingConnectionRequests, isEmpty);
  });

  test('trusted identity reconnects after endpoint IDs change', () async {
    final pair = await HandshakePair.create(requireBothNativeAccepts: true);
    addTearDown(pair.close);
    await _firstPair(pair);
    await pair.serviceA.disconnect('endpoint-b');
    await waitFor(
      () =>
          pair.serviceB.peerStates['endpoint-a'] ==
          NearbyConnectionState.disconnected,
    );
    pair.transportA.changeEndpointIds(
      local: 'endpoint-b-new',
      remote: 'endpoint-a-new',
    );
    pair.transportB.changeEndpointIds(
      local: 'endpoint-a-new',
      remote: 'endpoint-b-new',
    );
    pair.transportA.discoverPeer();
    pair.transportB.discoverPeer();
    await waitFor(
      () =>
          pair.serviceA.deviceIdForEndpoint('endpoint-b-new') == 'device-b' &&
          pair.serviceB.deviceIdForEndpoint('endpoint-a-new') == 'device-a',
    );
    pair.serviceA.endpointToDeviceId['endpoint-b'] = 'device-b';
    pair.serviceB.endpointToDeviceId['endpoint-a'] = 'device-a';
    pair.transportA.repeatDisconnectedCallback('endpoint-b');
    pair.transportB.repeatDisconnectedCallback('endpoint-a');
    await Future<void>.delayed(Duration.zero);
    expect(pair.serviceA.deviceToEndpointId['device-b'], 'endpoint-b-new');
    expect(pair.serviceB.deviceToEndpointId['device-a'], 'endpoint-a-new');
    expect(pair.serviceA.pendingConnectionRequests, isEmpty);
    expect(pair.serviceB.pendingConnectionRequests, isEmpty);
  });

  test('account and profile changes preserve device trust', () async {
    String? account;
    final pair = await HandshakePair.create(
      requireBothNativeAccepts: true,
      currentUserIdProviderA: () => account,
    );
    addTearDown(pair.close);
    await _firstPair(pair);
    await pair.serviceA.disconnect('endpoint-b');
    await waitFor(
      () =>
          pair.serviceB.peerStates['endpoint-a'] ==
          NearbyConnectionState.disconnected,
    );
    account = 'account-after-profile-change';
    await pair.identityA.setDisplayName('RELIO updated');
    pair.transportA.discoverPeer();
    pair.transportB.discoverPeer();
    await _waitConnected(pair);
    expect(pair.serviceA.pendingConnectionRequests, isEmpty);
    expect(pair.serviceB.pendingConnectionRequests, isEmpty);
    expect(
      (await pair.repositoriesB.nearbyDevices.getDevice(
        'device-a',
      ))?.displayName,
      'RELIO updated',
    );
  });

  test('duplicate disconnect callbacks permit a later reconnect', () async {
    final pair = await HandshakePair.create(requireBothNativeAccepts: true);
    addTearDown(pair.close);
    await _firstPair(pair);
    await pair.serviceA.disconnect('endpoint-b');
    pair.transportA.repeatDisconnectedCallback();
    pair.transportA.repeatDisconnectedCallback();
    pair.transportB.repeatDisconnectedCallback();
    pair.transportB.repeatDisconnectedCallback();
    await waitFor(
      () =>
          pair.serviceA.peerStates['endpoint-b'] ==
              NearbyConnectionState.disconnected &&
          pair.serviceB.peerStates['endpoint-a'] ==
              NearbyConnectionState.disconnected,
    );
    pair.transportA.discoverPeer();
    pair.transportB.discoverPeer();
    await _waitConnected(pair);
  });

  test(
    'one-sided trust removal disconnects and requires consent again',
    () async {
      final pair = await HandshakePair.create(requireBothNativeAccepts: true);
      addTearDown(pair.close);
      await _firstPair(pair);
      final conversationsBefore = await pair.repositoriesA.conversations
          .listConversations();
      await pair.serviceA.removeTrustedPeer('device-b');
      await waitFor(
        () =>
            pair.serviceA.peerStates['endpoint-b'] ==
                NearbyConnectionState.disconnected &&
            pair.serviceB.peerStates['endpoint-a'] ==
                NearbyConnectionState.disconnected,
      );
      final saved = await pair.repositoriesA.nearbyDevices.getDevice(
        'device-b',
      );
      expect(saved?.isTrusted, isFalse);
      expect(saved?.autoReconnectEnabled, isFalse);
      expect(saved?.publicIdentityFingerprint, isNull);
      expect(
        await pair.repositoriesA.conversations.listConversations(),
        hasLength(conversationsBefore.length),
      );
      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () => pair.serviceA.pendingConnectionRequests.containsKey('endpoint-b'),
      );
      expect(
        pair.serviceA.peerStates['endpoint-b'],
        isNot(NearbyConnectionState.connected),
      );
    },
  );

  test('stale discovery epoch is excluded from current peer list', () async {
    final pair = await HandshakePair.create();
    addTearDown(pair.close);
    expect(visibleNearbyPeers(pair.serviceA), hasLength(1));
    await pair.serviceA.startDiscovery();
    pair.transportA.discoverPeer();
    await waitFor(() => visibleNearbyPeers(pair.serviceA).isNotEmpty);
    await pair.serviceA.stopDiscovery();
    expect(visibleNearbyPeers(pair.serviceA), isEmpty);
  });

  test('battery visibility follows fresh verified telemetry', () {
    final now = DateTime.utc(2026, 10, 14, 10);
    RelioNearbyDevice peer(DateTime updatedAt) => RelioNearbyDevice(
      deviceId: 'device-b',
      displayName: 'Peer',
      status: DeviceStatus.normal,
      lastSeenAt: updatedAt,
      batteryLevel: 2,
      batteryUpdatedAt: updatedAt,
    );
    expect(
      isFreshNearbyBattery(
        peer(now.subtract(const Duration(minutes: 3))),
        connected: true,
        now: now,
      ),
      isFalse,
    );
    expect(
      isFreshNearbyBattery(peer(now), connected: false, now: now),
      isFalse,
    );
    expect(isFreshNearbyBattery(peer(now), connected: true, now: now), isTrue);
  });

  test(
    'new deviceStatus restores battery visibility after stale telemetry',
    () async {
      final battery = FakeBatteryInfoService(
        BatterySnapshot(
          level: 2,
          isCharging: false,
          updatedAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 3),
          ),
        ),
      );
      final pair = await HandshakePair.create(
        requireBothNativeAccepts: true,
        batteryInfoA: battery,
      );
      addTearDown(() async {
        await pair.close();
        await battery.dispose();
      });
      await _firstPair(pair);
      final stale = await pair.repositoriesB.nearbyDevices.getDevice(
        'device-a',
      );
      expect(stale?.batteryLevel, 2);
      expect(isFreshNearbyBattery(stale!, connected: true), isFalse);
      pair.serviceA.startBatteryMetadataUpdates();
      battery.emit(
        BatterySnapshot(
          level: 80,
          isCharging: true,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await waitFor(() async {
        final fresh = await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        );
        return fresh?.batteryLevel == 80 &&
            isFreshNearbyBattery(fresh!, connected: true);
      });
    },
  );
}
