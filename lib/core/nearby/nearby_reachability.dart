const nearbyReachabilityCapability = 'reachability-v1';
const nearbyReachabilityMaxHops = 3;
const nearbyReachabilityMaxRoutes = 24;
const nearbyReachabilityLease = Duration(seconds: 30);

class NearbyReachablePeer {
  const NearbyReachablePeer(this.deviceId, this.name, this.hops);

  final String deviceId;
  final String name;
  final int hops;
}

class NearbyReachabilityRoute {
  const NearbyReachabilityRoute(this.path, this.name, this.expiresAt);

  final List<String> path;
  final String name;
  final Duration expiresAt;

  String get deviceId => path.last;
  NearbyReachablePeer get peer =>
      NearbyReachablePeer(deviceId, name, path.length);

  static bool validId(Object? value) =>
      value is String && value.isNotEmpty && value.length <= 128;

  static NearbyReachabilityRoute? decode(
    Object? value, {
    required String sender,
    required String local,
    required Duration now,
  }) {
    if (value is! Map) return null;
    final path = value['path'];
    final name = value['name'];
    final lease = value['leaseMs'];
    if (path is! List ||
        path.isEmpty ||
        path.length >= nearbyReachabilityMaxHops ||
        !path.every(validId) ||
        path.toSet().length != path.length ||
        path.contains(local) ||
        path.contains(sender) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        lease is! int ||
        lease <= 1000 ||
        lease > nearbyReachabilityLease.inMilliseconds) {
      return null;
    }
    return NearbyReachabilityRoute(
      [sender, ...path.cast<String>()],
      name,
      now + Duration(milliseconds: lease - 1000),
    );
  }

  Map<String, Object> encode(Duration now) => {
    'path': path,
    'name': name,
    'leaseMs': (expiresAt - now).inMilliseconds,
  };
}

// เก็บ snapshot แยกตาม session เพื่อถอนเส้นทางทั้งชุดเมื่อ next hop หลุด
class NearbyReachabilityTable {
  final _snapshots = <String, (int, List<NearbyReachabilityRoute>)>{};

  void retainSessions(Set<String> sessions) =>
      _snapshots.removeWhere((session, _) => !sessions.contains(session));

  bool replace(
    String session,
    int sequence,
    List<NearbyReachabilityRoute> routes,
  ) {
    if (sequence <= (_snapshots[session]?.$1 ?? 0)) return false;
    _snapshots[session] = (sequence, routes);
    return true;
  }

  Iterable<NearbyReachabilityRoute> active(
    Set<String> sessions,
    Duration now,
  ) sync* {
    for (final session in sessions) {
      for (final route
          in _snapshots[session]?.$2 ?? const <NearbyReachabilityRoute>[]) {
        if (route.expiresAt > now) yield route;
      }
    }
  }

  static List<NearbyReachabilityRoute> best(
    Iterable<NearbyReachabilityRoute> candidates,
  ) {
    final sorted = candidates.toList()
      ..sort((a, b) {
        final hops = a.path.length.compareTo(b.path.length);
        if (hops != 0) return hops;
        final id = a.deviceId.compareTo(b.deviceId);
        if (id != 0) return id;
        return a.path.join('\n').compareTo(b.path.join('\n'));
      });
    final seen = <String>{};
    return sorted.where((route) => seen.add(route.deviceId)).toList();
  }
}
