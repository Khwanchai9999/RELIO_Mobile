import '../nearby/nearby_transport.dart';

// รูปแบบการวางเส้นทาง Text แยกโหมดอัตโนมัติ ส่งตรง และโหมดบังคับเฉพาะ QA
enum RelayTextRouteMode { automatic, directOnly, qaForcedRelay }

enum RelayRouteKind { direct, relay, unavailable }

class RelayRoutePlan {
  const RelayRoutePlan({
    required this.mode,
    required this.kind,
    required this.sourceDeviceId,
    required this.destinationDeviceId,
    required this.verifiedAt,
    this.directEndpointId,
    this.middleDeviceId,
    this.forceFirstHop = false,
    this.reason,
  });

  final RelayTextRouteMode mode;
  final RelayRouteKind kind;
  final String sourceDeviceId;
  final String destinationDeviceId;
  final DateTime verifiedAt;
  final String? directEndpointId;

  /// Initial peer used by a relay route; later hops choose their own next peer.
  final String? middleDeviceId;

  /// Keeps a failed direct send from immediately retrying the same direct peer.
  final bool forceFirstHop;
  final String? reason;

  String? get firstHopDeviceId => middleDeviceId;
  bool get ready => kind != RelayRouteKind.unavailable;
}

typedef RelayRouteVerifier =
    Future<bool> Function(String middleDeviceId, String destinationDeviceId);

/// เลือก next hop เดียวต่อครั้ง ไม่ broadcast และให้แต่ละ relay ตัดสิน hop ถัดไป
class RelayRoutePlanner {
  const RelayRoutePlanner();

  Future<RelayRoutePlan> plan({
    required RelayTextRouteMode mode,
    required String sourceDeviceId,
    required String destinationDeviceId,
    required Iterable<NearbyPeer> connectedPeers,
    required RelayRouteVerifier verifyRelay,
    String? forcedMiddleDeviceId,
    bool preferRelay = false,
  }) async {
    // ผู้เรียกส่ง snapshot ที่ผ่าน connection state แล้ว จึงไม่พึ่ง flag ซ้ำ
    // ซึ่งบาง transport อัปเดตช้ากว่า connection callback
    final peers = connectedPeers
        .where((peer) => peer.deviceId != null)
        .toList(growable: false);
    final direct = peers
        .where((peer) => peer.deviceId == destinationDeviceId)
        .firstOrNull;
    final now = DateTime.now().toUtc();

    if (!preferRelay &&
        mode != RelayTextRouteMode.qaForcedRelay &&
        direct != null) {
      return RelayRoutePlan(
        mode: mode,
        kind: RelayRouteKind.direct,
        sourceDeviceId: sourceDeviceId,
        destinationDeviceId: destinationDeviceId,
        directEndpointId: direct.endpointId,
        verifiedAt: now,
      );
    }
    if (mode == RelayTextRouteMode.directOnly) {
      return RelayRoutePlan(
        mode: mode,
        kind: RelayRouteKind.unavailable,
        sourceDeviceId: sourceDeviceId,
        destinationDeviceId: destinationDeviceId,
        verifiedAt: now,
        reason: 'direct_unavailable',
      );
    }

    final candidates =
        peers
            .where(
              (peer) =>
                  peer.deviceId != sourceDeviceId &&
                  peer.deviceId != destinationDeviceId &&
                  peer.capabilities.contains('relay-v1'),
            )
            .toList(growable: false)
          ..sort((a, b) => a.deviceId!.compareTo(b.deviceId!));
    final selected = mode == RelayTextRouteMode.qaForcedRelay
        ? candidates.where((peer) => peer.deviceId == forcedMiddleDeviceId)
        : candidates;
    for (final candidate in selected) {
      if (await verifyRelay(candidate.deviceId!, destinationDeviceId)) {
        return RelayRoutePlan(
          mode: mode,
          kind: RelayRouteKind.relay,
          sourceDeviceId: sourceDeviceId,
          destinationDeviceId: destinationDeviceId,
          middleDeviceId: candidate.deviceId,
          forceFirstHop:
              mode == RelayTextRouteMode.qaForcedRelay || preferRelay,
          verifiedAt: DateTime.now().toUtc(),
        );
      }
    }
    return RelayRoutePlan(
      mode: mode,
      kind: RelayRouteKind.unavailable,
      sourceDeviceId: sourceDeviceId,
      destinationDeviceId: destinationDeviceId,
      verifiedAt: DateTime.now().toUtc(),
      reason: mode == RelayTextRouteMode.qaForcedRelay
          ? 'forced_relay_unavailable'
          : 'relay_unavailable',
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
