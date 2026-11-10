import 'dart:async';

import 'package:flutter/foundation.dart';

import '../diagnostics/diagnostics_log_service.dart';
import '../domain/relio_entities.dart';
import '../location/location_service.dart';
import '../location/nearby_location_quality.dart';
import 'nearby_service.dart';

enum NearbyLiveLocationStatus {
  disabled,
  waitingForPeer,
  localOnly,
  paused,
  starting,
  active,
  waitingForFreshFix,
  permissionRequired,
  preciseLocationRequired,
  locationServiceDisabled,
  unavailable,
}

/// ดูแล GPS stream ใน foreground หนึ่งชุด และแชร์เฉพาะพิกัดที่ผ่านเกณฑ์
/// ไปยัง peer ที่ทำ RELIO identity handshake สำเร็จแล้วเท่านั้น/// Owns one foreground GPS stream and shares accepted fixes only with peers
/// whose RELIO identity handshake is complete.
class NearbyLocationSharingCoordinator {
  NearbyLocationSharingCoordinator({
    required this.nearbyService,
    required this.locationService,
    this.freshnessThreshold = const Duration(seconds: 45),
    this.stalenessThreshold = const Duration(seconds: 60),
    this.peerRateLimit = const Duration(seconds: 15),
    this.normalInterval = const Duration(seconds: 10),
    this.sosInterval = const Duration(seconds: 5),
    this.diagnostics,
    bool initiallyEnabled = true,
    bool initiallyForeground = true,
    this.onAcceptedFix,
    this.onLocationForDisplay,
    this.onStateChanged,
    DateTime Function()? nowProvider,
  }) : now = nowProvider ?? DateTime.now,
       _enabled = initiallyEnabled,
       _foreground = initiallyForeground;

  static const normalLiveInterval = Duration(seconds: 10);
  static const sosLiveInterval = Duration(seconds: 5);

  final NearbyService nearbyService;
  final LocationService locationService;
  final Duration freshnessThreshold;
  final Duration stalenessThreshold;
  final Duration peerRateLimit;
  final Duration normalInterval;
  final Duration sosInterval;
  final DiagnosticsLogService? diagnostics;
  final DateTime Function() now;
  final ValueChanged<LocationData>? onAcceptedFix;
  final ValueChanged<LocationData>? onLocationForDisplay;
  final VoidCallback? onStateChanged;

  LocationData? _lastAcquiredLocation;
  DateTime? _lastAcquiredAt;
  DateTime? _lastBroadcastAt;
  final Map<String, LocationData> _lastSharedLocationByEndpoint = {};
  Future<LocationData?>? _inFlightAcquisition;
  StreamSubscription<LocationData>? _positionSubscription;
  Duration? _activeInterval;
  Future<void> _reconcileQueue = Future<void>.value();
  bool _reconcileAgain = false;
  bool _processingPositions = false;
  LocationData? _queuedLatestPosition;
  bool _enabled = true;
  bool _foreground;
  bool _localSosActive = false;
  bool _disposed = false;
  NearbyLiveLocationStatus _status = NearbyLiveLocationStatus.disabled;
  Duration? _requestedInterval;
  DateTime? _lastFixCapturedAt;
  DateTime? _lastPacketSentAt;
  DateTime? _streamRequestedAt;
  DateTime? _streamStartedAt;
  LocationData? _lastDisplayedLocation;
  bool _firstStreamFixLogged = false;

  LocationData? get lastAcquiredLocation => _lastAcquiredLocation;
  DateTime? get lastAcquiredAt => _lastAcquiredAt;
  DateTime? get lastBroadcastAt => _lastBroadcastAt;
  LocationData? get lastAcceptedLocation => _lastAcquiredLocation;
  NearbyLiveLocationStatus get status => _status;
  bool get isEnabled => _enabled;
  bool get isActive =>
      _status == NearbyLiveLocationStatus.active &&
      _positionSubscription != null;
  LocationData? get lastDisplayedLocation => _lastDisplayedLocation;
  Duration? get requestedInterval => _requestedInterval;
  DateTime? get lastFixCapturedAt => _lastFixCapturedAt;
  DateTime? get lastPacketSentAt => _lastPacketSentAt;
  int get activeStreamCount => _positionSubscription == null ? 0 : 1;

  Future<void> setEnabled(bool enabled) {
    _enabled = enabled;
    return _reconcile();
  }

  Future<void> setForeground(bool foreground) {
    _foreground = foreground;
    return _reconcile();
  }

  Future<void> setLocalSosActive(bool active) {
    _localSosActive = active;
    return _reconcile();
  }

  /// เมื่อ handshake สำเร็จ จะเริ่ม stream ที่ดูแลเองสำหรับชุด peer ที่ยืนยันแล้ว  /// A completed handshake starts one managed stream for the verified peer set.
  Future<void> onPeerHandshakeCompleted(String endpointId) async {
    if (!nearbyService.isEndpointVerifiedConnected(endpointId)) return;
    await _reconcile();
    final last = _lastAcquiredLocation;
    final previous = _lastSharedLocationByEndpoint[endpointId];
    if (_shouldListen &&
        last != null &&
        previous == null &&
        NearbyLocationQuality.isEligibleForCurrentSharing(last, now: now())) {
      final sent = await _publishToVerifiedPeers(
        last,
        targetEndpointId: endpointId,
        requireActiveLiveSharing: true,
      );
      if (sent > 0) {
        _lastBroadcastAt = now();
        _lastPacketSentAt = _lastBroadcastAt;
        _setStatus(NearbyLiveLocationStatus.active, interval: _activeInterval);
      }
    }
  }

  Future<void> onAppResumed() => _reconcile();

  Future<void> onPermissionOrReadinessChanged() => _reconcile();

  void onPeerDisconnected(String endpointId) {
    _lastSharedLocationByEndpoint.remove(endpointId);
    if (nearbyService.authenticatedConnectedPeers.isEmpty && _shouldListen) {
      _setStatus(
        _lastAcquiredLocation == null
            ? NearbyLiveLocationStatus.waitingForFreshFix
            : NearbyLiveLocationStatus.localOnly,
        interval: _activeInterval,
      );
    }
    unawaited(_reconcile());
  }

  Future<void> shareLocationWithVerifiedPeers({
    bool forceFresh = false,
    String? targetEndpointId,
  }) async {
    final location = await _acquireLocation(forceFresh: forceFresh);
    if (location == null) return;
    if (targetEndpointId != null &&
        !nearbyService.isEndpointVerifiedConnected(targetEndpointId)) {
      return;
    }
    final sent = await _publishToVerifiedPeers(
      location,
      targetEndpointId: targetEndpointId,
    );
    if (sent > 0) {
      _lastBroadcastAt = now();
      _lastPacketSentAt = _lastBroadcastAt;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _stopStream();
  }

  Future<void> _reconcile() {
    if (_disposed) return Future<void>.value();
    _reconcileAgain = true;
    final next = _reconcileQueue.then((_) async {
      while (_reconcileAgain && !_disposed) {
        _reconcileAgain = false;
        await _reconcileOnce();
      }
    });
    _reconcileQueue = next.catchError((Object _) {});
    return next;
  }

  bool get _shouldListen => !_disposed && _enabled && _foreground;

  Duration get _desiredInterval =>
      _localSosActive ? sosInterval : normalInterval;

  Future<void> _reconcileOnce() async {
    if (!_enabled) {
      await _stopStream();
      _setStatus(NearbyLiveLocationStatus.disabled, interval: null);
      return;
    }
    if (!_foreground) {
      await _stopStream();
      _setStatus(NearbyLiveLocationStatus.paused, interval: null);
      return;
    }
    final interval = _desiredInterval;
    if (_positionSubscription != null && _activeInterval == interval) return;
    await _stopStream();
    if (!_shouldListen) return;

    _setStatus(NearbyLiveLocationStatus.starting, interval: interval);
    _streamRequestedAt = now();
    _streamStartedAt = now();
    _firstStreamFixLogged = false;
    diagnostics?.record(
      'nearby',
      'location_stream_requested',
      fields: {'intervalSeconds': interval.inSeconds},
    );
    try {
      final positions = await locationService.watchPositions(
        interval: interval,
      );
      if (!_shouldListen || _disposed || _desiredInterval != interval) {
        _reconcileAgain = true;
        return;
      }
      _activeInterval = interval;
      _positionSubscription = positions.listen(
        _queuePosition,
        onError: _onPositionError,
        onDone: _onPositionStreamDone,
        cancelOnError: true,
      );
      diagnostics?.record(
        'nearby',
        'location_stream_started',
        fields: {
          'intervalSeconds': interval.inSeconds,
          if (_streamRequestedAt != null)
            'startupElapsedMs': now()
                .difference(_streamRequestedAt!)
                .inMilliseconds,
        },
      );
      _setStatus(
        NearbyLiveLocationStatus.waitingForFreshFix,
        interval: interval,
      );
      unawaited(_seedLastKnownForLocalDisplay());
    } on LocationStreamException catch (error) {
      diagnostics?.record(
        'nearby',
        'location_stream_unavailable',
        reason: error.failure.name,
      );
      _setStatus(_statusForFailure(error.failure), interval: interval);
    } on Object {
      diagnostics?.record(
        'nearby',
        'location_stream_unavailable',
        reason: 'unexpected_error',
      );
      _setStatus(NearbyLiveLocationStatus.unavailable, interval: interval);
    }
  }

  void _queuePosition(LocationData location) {
    _queuedLatestPosition = location;
    if (_processingPositions) return;
    _processingPositions = true;
    unawaited(_drainPositions());
  }

  Future<void> _drainPositions() async {
    try {
      while (_queuedLatestPosition != null && _shouldListen) {
        final location = _queuedLatestPosition!;
        _queuedLatestPosition = null;
        await _processPosition(location);
      }
    } finally {
      _processingPositions = false;
      if (_queuedLatestPosition != null && _shouldListen) {
        _queuePosition(_queuedLatestPosition!);
      }
    }
  }

  Future<void> _processPosition(LocationData location) async {
    if (!_firstStreamFixLogged) {
      _firstStreamFixLogged = true;
      diagnostics?.record(
        'nearby',
        'location_first_stream_fix',
        fields: {
          if (_streamStartedAt != null)
            'elapsedMs': now().difference(_streamStartedAt!).inMilliseconds,
          if (_streamRequestedAt != null)
            'totalElapsedMs': now()
                .difference(_streamRequestedAt!)
                .inMilliseconds,
          'fixAgeMs': now()
              .toUtc()
              .difference(location.capturedAt.toUtc())
              .inMilliseconds,
          'accuracyBand': _accuracyBand(location.accuracyMeters),
        },
      );
    }
    if (NearbyLocationQuality.isEligibleForLocalDisplay(location, now: now())) {
      _presentLocalLocation(location);
    }
    if (!NearbyLocationQuality.isEligibleForCurrentSharing(
      location,
      now: now(),
    )) {
      diagnostics?.record(
        'nearby',
        'location_fix_rejected',
        reason: 'not_eligible_for_sharing',
        fields: {
          'fixAgeMs': now()
              .toUtc()
              .difference(location.capturedAt.toUtc())
              .inMilliseconds,
          'accuracyBand': _accuracyBand(location.accuracyMeters),
        },
      );
      _setStatus(NearbyLiveLocationStatus.waitingForFreshFix);
      return;
    }
    final previous = _lastAcquiredLocation;
    if (previous != null && !location.capturedAt.isAfter(previous.capturedAt)) {
      return;
    }
    if (!_shouldListen) return;

    // Keep the provider timestamp and accuracy exactly as received.
    _lastAcquiredLocation = location;
    _lastAcquiredAt = now();
    _lastFixCapturedAt = location.capturedAt;
    onAcceptedFix?.call(location);
    diagnostics?.record(
      'nearby',
      'location_fix_accepted_for_sharing',
      fields: {
        'fixAgeMs': now()
            .toUtc()
            .difference(location.capturedAt.toUtc())
            .inMilliseconds,
        'accuracyBand': _accuracyBand(location.accuracyMeters),
        'verifiedPeerCount': nearbyService.authenticatedConnectedPeers.length,
      },
    );
    final sent = await _publishToVerifiedPeers(
      location,
      requireActiveLiveSharing: true,
    );
    if (sent > 0) {
      _lastBroadcastAt = now();
      _lastPacketSentAt = _lastBroadcastAt;
      _setStatus(NearbyLiveLocationStatus.active, interval: _activeInterval);
    } else if (_shouldListen) {
      _setStatus(NearbyLiveLocationStatus.localOnly);
    }
  }

  Future<void> _seedLastKnownForLocalDisplay() async {
    try {
      final location = await locationService.getRecentLastKnownForDisplay();
      if (!_shouldListen || location == null || _disposed) return;
      if (!NearbyLocationQuality.isEligibleForLocalDisplay(
        location,
        now: now(),
      )) {
        return;
      }
      final displayed = _lastDisplayedLocation;
      final acquired = _lastAcquiredLocation;
      final newest =
          acquired != null &&
              (displayed == null ||
                  acquired.capturedAt.isAfter(displayed.capturedAt))
          ? acquired
          : displayed;
      if (newest != null && !location.capturedAt.isAfter(newest.capturedAt)) {
        return;
      }
      _presentLocalLocation(location);
      diagnostics?.record(
        'nearby',
        'location_last_known_presented_locally',
        fields: {
          'fixAgeMs': now()
              .toUtc()
              .difference(location.capturedAt.toUtc())
              .inMilliseconds,
          'accuracyBand': _accuracyBand(location.accuracyMeters),
        },
      );
    } on Object {
      // Local map startup must not wait on a cached provider fix.
    }
  }

  void _presentLocalLocation(LocationData location) {
    final current = _lastDisplayedLocation;
    if (current != null && !location.capturedAt.isAfter(current.capturedAt)) {
      return;
    }
    _lastDisplayedLocation = location;
    diagnostics?.record(
      'nearby',
      'location_fix_presented_locally',
      fields: {
        'sourceClass': switch (location.source) {
          'lastKnown' => 'cached',
          'live' || 'current' => 'provider',
          _ => 'other',
        },
        'fixAgeMs': now()
            .toUtc()
            .difference(location.capturedAt.toUtc())
            .inMilliseconds,
        'accuracyBand': _accuracyBand(location.accuracyMeters),
      },
    );
    onLocationForDisplay?.call(location);
  }

  String _accuracyBand(double? accuracy) {
    if (accuracy == null || !accuracy.isFinite || accuracy < 0) {
      return 'unknown';
    }
    if (accuracy <= 25) return '0_25m';
    if (accuracy <= 50) return '26_50m';
    if (accuracy <= 100) return '51_100m';
    return 'over_100m';
  }

  Future<int> _publishToVerifiedPeers(
    LocationData location, {
    String? targetEndpointId,
    bool requireActiveLiveSharing = false,
  }) async {
    var sent = 0;
    final targets = nearbyService.authenticatedConnectedPeers
        .where(
          (peer) =>
              targetEndpointId == null || peer.endpointId == targetEndpointId,
        )
        .toList(growable: false);
    for (final peer in targets) {
      if (requireActiveLiveSharing && !_shouldListen) break;
      final endpointId = peer.endpointId;
      if (!nearbyService.isEndpointVerifiedConnected(endpointId)) continue;
      final previous = _lastSharedLocationByEndpoint[endpointId];
      if (previous != null && _isSameFix(previous, location)) continue;
      try {
        await nearbyService.publishMapLocation(
          location,
          targetEndpointId: endpointId,
        );
        if (!nearbyService.isEndpointVerifiedConnected(endpointId)) continue;
        _lastSharedLocationByEndpoint[endpointId] = location;
        sent++;
      } on Object {
        // A failed peer send must not block other verified peers or SOS traffic.
      }
    }
    return sent;
  }

  void _onPositionError(Object error) {
    _positionSubscription = null;
    _activeInterval = null;
    if (error is LocationStreamException) {
      _setStatus(_statusForFailure(error.failure));
    } else {
      _setStatus(NearbyLiveLocationStatus.unavailable);
    }
  }

  void _onPositionStreamDone() {
    _positionSubscription = null;
    _activeInterval = null;
    if (!_disposed && _shouldListen) {
      if (_status == NearbyLiveLocationStatus.permissionRequired ||
          _status == NearbyLiveLocationStatus.preciseLocationRequired ||
          _status == NearbyLiveLocationStatus.locationServiceDisabled ||
          _status == NearbyLiveLocationStatus.unavailable) {
        return;
      }
      _setStatus(NearbyLiveLocationStatus.waitingForFreshFix);
    }
  }

  Future<void> _stopStream() async {
    _queuedLatestPosition = null;
    final subscription = _positionSubscription;
    _positionSubscription = null;
    _activeInterval = null;
    if (subscription != null) await subscription.cancel();
  }

  void _setStatus(NearbyLiveLocationStatus status, {Duration? interval}) {
    final changed = _status != status || _requestedInterval != interval;
    _status = status;
    _requestedInterval = interval;
    if (changed) onStateChanged?.call();
  }

  NearbyLiveLocationStatus _statusForFailure(LocationFailure failure) =>
      switch (failure) {
        LocationFailure.permissionDenied ||
        LocationFailure.permissionDeniedForever =>
          NearbyLiveLocationStatus.permissionRequired,
        LocationFailure.approximatePermission =>
          NearbyLiveLocationStatus.preciseLocationRequired,
        LocationFailure.serviceDisabled =>
          NearbyLiveLocationStatus.locationServiceDisabled,
        LocationFailure.staleFix ||
        LocationFailure.timeout => NearbyLiveLocationStatus.waitingForFreshFix,
        LocationFailure.invalidFix ||
        LocationFailure.unavailable => NearbyLiveLocationStatus.unavailable,
      };

  Future<LocationData?> _acquireLocation({bool forceFresh = false}) async {
    final currentTime = now();
    if (!forceFresh &&
        _lastAcquiredLocation != null &&
        _lastAcquiredAt != null &&
        currentTime.difference(_lastAcquiredAt!) < freshnessThreshold &&
        NearbyLocationQuality.isEligibleForCurrentSharing(
          _lastAcquiredLocation!,
          now: currentTime,
        )) {
      return _lastAcquiredLocation;
    }
    if (_inFlightAcquisition != null) return _inFlightAcquisition;

    final completer = Completer<LocationData?>();
    _inFlightAcquisition = completer.future;
    try {
      final result = await locationService.getFreshLocation();
      final location = result.location;
      if (location != null &&
          NearbyLocationQuality.isEligibleForCurrentSharing(
            location,
            now: now(),
          )) {
        _lastAcquiredLocation = location;
        _lastAcquiredAt = now();
        completer.complete(location);
        return location;
      }
      completer.complete(null);
      return null;
    } on Object {
      completer.complete(null);
      return null;
    } finally {
      _inFlightAcquisition = null;
    }
  }

  bool _isSameFix(LocationData left, LocationData right) =>
      left.latitude == right.latitude &&
      left.longitude == right.longitude &&
      left.capturedAt.isAtSameMomentAs(right.capturedAt);
}
