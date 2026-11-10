import '../nearby/nearby_reachability.dart';
import '../nearby/nearby_service.dart';
import '../nearby/nearby_transport.dart';
import 'peer_connection_presence.dart';

enum LiveRouteKind { direct, relay, searching, unreachable }

class LiveRoutePresentation {
  const LiveRoutePresentation({
    required this.kind,
    this.nextHopName,
    this.hops,
  });

  final LiveRouteKind kind;
  final String? nextHopName;
  final int? hops;

  String get chatSubtitle => switch (kind) {
    LiveRouteKind.direct => 'เชื่อมต่อโดยตรง',
    LiveRouteKind.relay => _relayLabel(nearby: false),
    LiveRouteKind.searching => 'กำลังค้นหาเส้นทาง…',
    LiveRouteKind.unreachable => 'ออฟไลน์ · ไม่มีเส้นทาง',
  };

  String get nearbySubtitle => switch (kind) {
    LiveRouteKind.direct => 'เชื่อมต่อโดยตรง',
    LiveRouteKind.relay => _relayLabel(nearby: true),
    LiveRouteKind.searching => 'กำลังค้นหาเส้นทาง…',
    LiveRouteKind.unreachable => 'ยังไม่สามารถเชื่อมต่อได้',
  };

  String? get _resolvedName {
    final value = nextHopName?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String _relayLabel({required bool nearby}) {
    final name = _resolvedName;
    final prefix = nearby ? 'เชื่อมต่อผ่าน' : 'ผ่าน';
    return name == null
        ? '$prefixรีเลย์ · ${hops ?? 2} ทอด'
        : '$prefix $name · ${hops ?? 2} ทอด';
  }
}

/// Treats a current, verified multi-hop route as online in chat surfaces.
/// Direct presence still wins; historical sends and expired route leases do not.
PeerConnectionPresence chatReachabilityFor(
  NearbyService nearby,
  String deviceId, {
  String? principal,
}) {
  final directPresence = nearby.presenceForPrincipal(deviceId, principal);
  if (directPresence == PeerConnectionPresence.online) {
    return PeerConnectionPresence.online;
  }
  final route = liveRoutePresentationFor(
    nearby,
    deviceId,
    presence: directPresence,
  );
  return route.kind == LiveRouteKind.relay
      ? PeerConnectionPresence.online
      : directPresence;
}

/// Reads the currently authenticated direct sessions and unexpired reachability
/// leases. This deliberately does not use the last message's route plan.
LiveRoutePresentation liveRoutePresentationFor(
  NearbyService nearby,
  String deviceId, {
  PeerConnectionPresence? presence,
}) {
  final hasVerifiedDirectSession = nearby.authenticatedConnectedPeers.any(
    (peer) => peer.deviceId == deviceId,
  );
  final neighbors = nearby.authenticatedConnectedPeers
      .where(
        (peer) =>
            nearby.deviceToEndpointId[peer.deviceId] == peer.endpointId &&
            nearby.connectionTraceForEndpoint(peer.endpointId) != null &&
            peer.capabilities.contains(nearbyReachabilityCapability),
      )
      .toList(growable: false);
  final nextHopNames = {
    for (final peer in neighbors)
      if (peer.deviceId != null) peer.deviceId!: peer.name,
  };
  final isSearching =
      (presence ?? nearby.presenceForDevice(deviceId)) ==
          PeerConnectionPresence.unknown ||
      nearby.discoveredPeers.any((peer) {
        if (peer.deviceId != deviceId) return false;
        final state = nearby.peerStates[peer.endpointId];
        return state == NearbyConnectionState.connecting ||
            state == NearbyConnectionState.incomingRequest ||
            (state == NearbyConnectionState.connected &&
                !nearby.isEndpointVerifiedConnected(peer.endpointId));
      });
  return liveRoutePresentationFrom(
    deviceId: deviceId,
    activeRoutes: nearby.activeReachabilityRoutes,
    directDeviceIds:
        hasVerifiedDirectSession &&
            (presence == null || presence == PeerConnectionPresence.online)
        ? {deviceId}
        : const {},
    nextHopNames: nextHopNames,
    isSearching: isSearching,
  );
}

LiveRoutePresentation liveRoutePresentationFrom({
  required String deviceId,
  required Iterable<NearbyReachabilityRoute> activeRoutes,
  required Set<String> directDeviceIds,
  required Map<String, String> nextHopNames,
  bool isSearching = false,
}) {
  if (directDeviceIds.contains(deviceId)) {
    return const LiveRoutePresentation(kind: LiveRouteKind.direct);
  }
  final route = NearbyReachabilityTable.best(
    activeRoutes.where((candidate) => candidate.deviceId == deviceId),
  ).firstOrNull;
  if (route != null && route.path.length >= 2) {
    final nextHopId = route.path.first;
    return LiveRoutePresentation(
      kind: LiveRouteKind.relay,
      nextHopName: nextHopNames[nextHopId],
      hops: route.path.length,
    );
  }
  if (isSearching) {
    return const LiveRoutePresentation(kind: LiveRouteKind.searching);
  }
  return const LiveRoutePresentation(kind: LiveRouteKind.unreachable);
}
