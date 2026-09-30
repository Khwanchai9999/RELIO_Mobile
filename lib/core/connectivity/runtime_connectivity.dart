import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RuntimeConnectivitySnapshot {
  const RuntimeConnectivitySnapshot({
    this.hasInternetRoute,
    this.internetValidated,
    this.wifiEnabled,
    this.bluetoothEnabled,
    this.nearbyPermissionsGranted,
    this.locationEnabled,
    this.androidSdk,
  });

  final bool? hasInternetRoute;
  final bool? internetValidated;
  final bool? wifiEnabled;
  final bool? bluetoothEnabled;
  final bool? nearbyPermissionsGranted;
  final bool? locationEnabled;
  final int? androidSdk;

  factory RuntimeConnectivitySnapshot.fromPlatform(Object? value) {
    if (value is! Map) return const RuntimeConnectivitySnapshot();
    return RuntimeConnectivitySnapshot(
      hasInternetRoute: value['hasInternetRoute'] as bool?,
      internetValidated: value['internetValidated'] as bool?,
      wifiEnabled: value['wifiEnabled'] as bool?,
      bluetoothEnabled: value['bluetoothEnabled'] as bool?,
      nearbyPermissionsGranted: value['nearbyPermissionsGranted'] as bool?,
      locationEnabled: value['locationEnabled'] as bool?,
      androidSdk: (value['androidSdk'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RuntimeConnectivitySnapshot &&
      other.hasInternetRoute == hasInternetRoute &&
      other.internetValidated == internetValidated &&
      other.wifiEnabled == wifiEnabled &&
      other.bluetoothEnabled == bluetoothEnabled &&
      other.nearbyPermissionsGranted == nearbyPermissionsGranted &&
      other.locationEnabled == locationEnabled &&
      other.androidSdk == androidSdk;

  @override
  int get hashCode => Object.hash(
    hasInternetRoute,
    internetValidated,
    wifiEnabled,
    bluetoothEnabled,
    nearbyPermissionsGranted,
    locationEnabled,
    androidSdk,
  );
}

abstract interface class RuntimeConnectivitySource {
  Future<RuntimeConnectivitySnapshot> read();

  Stream<RuntimeConnectivitySnapshot> get changes;
}

class MethodChannelRuntimeConnectivitySource
    implements RuntimeConnectivitySource {
  static const _methodChannel = MethodChannel('relio/runtime_connectivity');
  static const _eventChannel = EventChannel(
    'relio/runtime_connectivity/events',
  );

  Stream<RuntimeConnectivitySnapshot>? _changes;

  @override
  Future<RuntimeConnectivitySnapshot> read() async {
    try {
      final value = await _methodChannel.invokeMethod<Object?>('readStatus');
      return RuntimeConnectivitySnapshot.fromPlatform(value);
    } on MissingPluginException {
      return const RuntimeConnectivitySnapshot();
    } on PlatformException {
      return const RuntimeConnectivitySnapshot();
    }
  }

  @override
  Stream<RuntimeConnectivitySnapshot> get changes => _changes ??= _eventChannel
      .receiveBroadcastStream()
      .map(RuntimeConnectivitySnapshot.fromPlatform)
      .distinct();
}

class UnsupportedRuntimeConnectivitySource
    implements RuntimeConnectivitySource {
  const UnsupportedRuntimeConnectivitySource();

  @override
  Future<RuntimeConnectivitySnapshot> read() async =>
      const RuntimeConnectivitySnapshot();

  @override
  Stream<RuntimeConnectivitySnapshot> get changes => const Stream.empty();
}

enum InternetReachability { checking, online, offline, limited, unknown }

class InternetStatus {
  const InternetStatus({
    this.reachability = InternetReachability.unknown,
    this.runtime = const RuntimeConnectivitySnapshot(),
    this.lastCheckedAt,
  });

  final InternetReachability reachability;
  final RuntimeConnectivitySnapshot runtime;
  final DateTime? lastCheckedAt;

  bool get nearbyReady =>
      runtime.bluetoothEnabled == true &&
      runtime.nearbyPermissionsGranted == true &&
      (runtime.androidSdk == null ||
          runtime.androidSdk! > 30 ||
          runtime.locationEnabled == true);
}

abstract interface class InternetReachabilityProbe {
  Future<int> reachableEndpointCount();
}

class HttpsInternetReachabilityProbe implements InternetReachabilityProbe {
  HttpsInternetReachabilityProbe({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  static final endpoints = [
    Uri.parse('https://relio-17dc0.web.app/qa/latest.json'),
    Uri.parse('https://www.gstatic.com/generate_204'),
  ];

  final HttpClient Function() _clientFactory;

  @override
  Future<int> reachableEndpointCount() async {
    final results = await Future.wait(endpoints.map(_isReachable));
    return results.where((reachable) => reachable).length;
  }

  Future<bool> _isReachable(Uri endpoint) async {
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .openUrl('HEAD', endpoint)
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 400;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

class ConnectivityStatusService extends ChangeNotifier {
  ConnectivityStatusService({
    RuntimeConnectivitySource? source,
    InternetReachabilityProbe? probe,
    DateTime Function()? clock,
    this.probeCooldown = const Duration(seconds: 20),
  }) : _source =
           source ??
           (Platform.isAndroid
               ? MethodChannelRuntimeConnectivitySource()
               : const UnsupportedRuntimeConnectivitySource()),
       _probe = probe ?? HttpsInternetReachabilityProbe(),
       _clock = clock ?? DateTime.now;

  final RuntimeConnectivitySource _source;
  final InternetReachabilityProbe _probe;
  final DateTime Function() _clock;
  final Duration probeCooldown;
  final _changes = StreamController<InternetStatus>.broadcast();
  StreamSubscription<RuntimeConnectivitySnapshot>? _runtimeSubscription;
  Timer? _refreshDebounce;
  Future<InternetStatus>? _refreshOperation;
  InternetStatus _status = const InternetStatus();
  DateTime? _lastProbeAt;
  bool _initialized = false;
  bool _disposed = false;

  InternetStatus get status => _status;

  Stream<InternetStatus> get changes => _changes.stream;

  Future<RuntimeConnectivitySnapshot> readRuntimeSnapshot() => _source.read();

  Future<InternetStatus> initialize() async {
    if (_initialized) return _status;
    _initialized = true;
    _runtimeSubscription = _source.changes.listen(_onRuntimeChanged);
    _setStatus(
      InternetStatus(
        reachability: InternetReachability.checking,
        runtime: await _source.read(),
      ),
    );
    return refresh(initial: true);
  }

  Future<InternetStatus> refresh({bool initial = false}) async {
    if (_disposed) return _status;
    final inFlight = _refreshOperation;
    if (inFlight != null) return inFlight;
    final next = _refresh(initial: initial);
    _refreshOperation = next;
    try {
      return await next;
    } finally {
      if (identical(_refreshOperation, next)) _refreshOperation = null;
    }
  }

  Future<InternetStatus> _refresh({required bool initial}) async {
    final runtime = await _source.read();
    if (runtime.hasInternetRoute == false) {
      final offline = InternetStatus(
        reachability: InternetReachability.offline,
        runtime: runtime,
        lastCheckedAt: _clock(),
      );
      _setStatus(offline);
      return offline;
    }

    if (runtime.hasInternetRoute == null) {
      final unknown = InternetStatus(
        reachability: InternetReachability.unknown,
        runtime: runtime,
        lastCheckedAt: _clock(),
      );
      _setStatus(unknown);
      return unknown;
    }

    final now = _clock();
    final lastProbe = _lastProbeAt;
    if (!initial &&
        lastProbe != null &&
        now.difference(lastProbe) < probeCooldown) {
      _setStatus(
        InternetStatus(
          reachability: _status.reachability,
          runtime: runtime,
          lastCheckedAt: _status.lastCheckedAt,
        ),
      );
      return _status;
    }

    _setStatus(
      InternetStatus(
        reachability: InternetReachability.checking,
        runtime: runtime,
        lastCheckedAt: _status.lastCheckedAt,
      ),
    );
    _lastProbeAt = now;
    final reachable = await _probe.reachableEndpointCount();
    final state = reachable > 0
        ? InternetReachability.online
        : runtime.hasInternetRoute == true
        ? InternetReachability.limited
        : InternetReachability.unknown;
    final result = InternetStatus(
      reachability: state,
      runtime: runtime,
      lastCheckedAt: _clock(),
    );
    _setStatus(result);
    return result;
  }

  void _onRuntimeChanged(RuntimeConnectivitySnapshot runtime) {
    if (_disposed) return;
    if (runtime.hasInternetRoute == false) {
      _refreshDebounce?.cancel();
      _setStatus(
        InternetStatus(
          reachability: InternetReachability.offline,
          runtime: runtime,
          lastCheckedAt: _clock(),
        ),
      );
      return;
    }
    _setStatus(
      InternetStatus(
        reachability: _status.reachability,
        runtime: runtime,
        lastCheckedAt: _status.lastCheckedAt,
      ),
    );
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(refresh());
    });
  }

  void _setStatus(InternetStatus next) {
    if (_status.reachability == next.reachability &&
        _status.runtime == next.runtime &&
        _status.lastCheckedAt == next.lastCheckedAt) {
      return;
    }
    _status = next;
    _changes.add(next);
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _refreshDebounce?.cancel();
    await _runtimeSubscription?.cancel();
    await _changes.close();
    super.dispose();
  }
}
