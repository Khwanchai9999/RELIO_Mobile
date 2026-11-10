import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relay/relay_route_planner.dart';

void main() {
  const planner = RelayRoutePlanner();

  test('two devices use direct route and never ask for a relay', () async {
    var checks = 0;
    final plan = await planner.plan(
      mode: RelayTextRouteMode.automatic,
      sourceDeviceId: 'a',
      destinationDeviceId: 'c',
      connectedPeers: const [
        NearbyPeer(
          id: 'endpoint-c',
          name: 'C',
          connected: true,
          deviceId: 'c',
          capabilities: ['relay-v1'],
        ),
      ],
      verifyRelay: (_, _) async {
        checks++;
        return true;
      },
    );

    expect(plan.kind, RelayRouteKind.direct);
    expect(plan.directEndpointId, 'endpoint-c');
    expect(checks, 0);
  });

  test(
    'automatic route selects a connected peer that verifies a path to destination',
    () async {
      final checked = <String>[];
      final plan = await planner.plan(
        mode: RelayTextRouteMode.automatic,
        sourceDeviceId: 'a',
        destinationDeviceId: 'c',
        connectedPeers: const [
          NearbyPeer(
            id: 'endpoint-d',
            name: 'D',
            connected: true,
            deviceId: 'd',
            capabilities: ['relay-v1'],
          ),
          NearbyPeer(
            id: 'endpoint-b',
            name: 'B',
            connected: true,
            deviceId: 'b',
            capabilities: ['relay-v1'],
          ),
        ],
        verifyRelay: (middle, _) async {
          checked.add(middle);
          return middle == 'd';
        },
      );

      expect(plan.kind, RelayRouteKind.relay);
      expect(plan.firstHopDeviceId, 'd');
      expect(checked, ['b', 'd']);
    },
  );

  test(
    'automatic fallback can prefer relay after a failed direct send',
    () async {
      final plan = await planner.plan(
        mode: RelayTextRouteMode.automatic,
        sourceDeviceId: 'a',
        destinationDeviceId: 'c',
        connectedPeers: const [
          NearbyPeer(
            id: 'endpoint-c',
            name: 'C',
            connected: true,
            deviceId: 'c',
            capabilities: ['relay-v1'],
          ),
          NearbyPeer(
            id: 'endpoint-b',
            name: 'B',
            connected: true,
            deviceId: 'b',
            capabilities: ['relay-v1'],
          ),
        ],
        preferRelay: true,
        verifyRelay: (middle, destination) async =>
            middle == 'b' && destination == 'c',
      );

      expect(plan.kind, RelayRouteKind.relay);
      expect(plan.middleDeviceId, 'b');
    },
  );

  test('direct-only remains unavailable instead of falling back', () async {
    var checks = 0;
    final plan = await planner.plan(
      mode: RelayTextRouteMode.directOnly,
      sourceDeviceId: 'a',
      destinationDeviceId: 'c',
      connectedPeers: const [
        NearbyPeer(
          id: 'endpoint-b',
          name: 'B',
          connected: true,
          deviceId: 'b',
          capabilities: ['relay-v1'],
        ),
      ],
      verifyRelay: (_, _) async {
        checks++;
        return true;
      },
    );

    expect(plan.kind, RelayRouteKind.unavailable);
    expect(plan.reason, 'direct_unavailable');
    expect(checks, 0);
  });

  test(
    'forced QA route ignores direct and uses only selected middle',
    () async {
      final checked = <String>[];
      final plan = await planner.plan(
        mode: RelayTextRouteMode.qaForcedRelay,
        sourceDeviceId: 'a',
        destinationDeviceId: 'c',
        forcedMiddleDeviceId: 'd',
        connectedPeers: const [
          NearbyPeer(
            id: 'endpoint-c',
            name: 'C',
            connected: true,
            deviceId: 'c',
            capabilities: ['relay-v1'],
          ),
          NearbyPeer(
            id: 'endpoint-b',
            name: 'B',
            connected: true,
            deviceId: 'b',
            capabilities: ['relay-v1'],
          ),
          NearbyPeer(
            id: 'endpoint-d',
            name: 'D',
            connected: true,
            deviceId: 'd',
            capabilities: ['relay-v1'],
          ),
        ],
        verifyRelay: (middle, _) async {
          checked.add(middle);
          return true;
        },
      );

      expect(plan.kind, RelayRouteKind.relay);
      expect(plan.middleDeviceId, 'd');
      expect(checked, ['d']);
    },
  );

  test('invalid candidates are excluded without route checks', () async {
    var checks = 0;
    final plan = await planner.plan(
      mode: RelayTextRouteMode.automatic,
      sourceDeviceId: 'a',
      destinationDeviceId: 'c',
      connectedPeers: const [
        NearbyPeer(
          id: 'endpoint-candidate',
          name: 'No relay',
          connected: true,
          deviceId: 'x',
        ),
        NearbyPeer(
          id: 'endpoint-anonymous',
          name: 'Anonymous',
          connected: true,
        ),
      ],
      verifyRelay: (_, _) async {
        checks++;
        return true;
      },
    );

    expect(plan.kind, RelayRouteKind.unavailable);
    expect(checks, 0);
  });
}
