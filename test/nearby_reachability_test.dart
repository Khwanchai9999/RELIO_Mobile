import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/nearby_reachability.dart';

void main() {
  test('route leases shrink, expire, and cannot be refreshed by replay', () {
    final table = NearbyReachabilityTable();
    final route = NearbyReachabilityRoute.decode(
      {
        'path': ['C', 'D'],
        'name': 'D',
        'leaseMs': 4000,
      },
      sender: 'B',
      local: 'A',
      now: Duration.zero,
    )!;
    expect(route.peer.hops, 3);
    expect(route.encode(const Duration(seconds: 1))['leaseMs'], 2000);
    expect(table.replace('B-session', 2, [route]), isTrue);
    expect(table.replace('B-session', 1, []), isFalse);
    expect(table.active({'B-session'}, const Duration(seconds: 2)), [route]);
    expect(table.active({'B-session'}, const Duration(seconds: 3)), isEmpty);
    table.retainSessions({});
    expect(table.active({'B-session'}, Duration.zero), isEmpty);
    expect(table.replace('B-new-session', 1, [route]), isTrue);
  });

  test('looped, over-limit and expired paths are rejected', () {
    for (final path in [
      ['A'],
      ['B', 'D'],
      ['C', 'C'],
      ['C', 'D', 'E'],
    ]) {
      expect(
        NearbyReachabilityRoute.decode(
          {'path': path, 'name': 'Peer', 'leaseMs': 5000},
          sender: 'B',
          local: 'A',
          now: Duration.zero,
        ),
        isNull,
      );
    }
    expect(
      NearbyReachabilityRoute.decode(
        {
          'path': ['D'],
          'name': 'D',
          'leaseMs': 1000,
        },
        sender: 'B',
        local: 'A',
        now: Duration.zero,
      ),
      isNull,
    );
  });
}
