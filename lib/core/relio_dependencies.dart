import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'database/app_database.dart';
import 'connectivity/runtime_connectivity.dart';
import 'app_update/app_update_service.dart';
import 'cloud/auth_service.dart';
import 'cloud/cloud_data_source.dart';
import 'cloud/supabase_cloud_data_source.dart';
import 'location/location_service.dart';
import 'media/media_storage_service.dart';
import 'nearby/android_nearby_transport.dart';
import 'nearby/nearby_service.dart';
import 'nearby/nearby_transport.dart';
import 'permissions/permission_service.dart';
import 'repositories/local_repositories.dart';
import 'relay/relay_engine.dart';
import 'relay/relay_repository.dart';
import 'sync/sync_engine.dart';

class RelioDependencies {
  RelioDependencies({
    AppDatabase? database,
    NearbyTransport? transport,
    bool? useMockTransport,
    LocationService? locationService,
    MediaStorageService? mediaStorage,
    CloudDataSource? cloudDataSource,
    AppUpdateService? appUpdateService,
    ConnectivityStatusService? connectivityStatusService,
    PermissionService? permissionService,
    bool? androidPlatformOverride,
  }) : database = database ?? AppDatabase(),
       _isAndroid = androidPlatformOverride ?? Platform.isAndroid,
       useMockTransport = useMockTransport ?? _defaultMockTransport,
       transport =
           transport ??
           ((useMockTransport ?? _defaultMockTransport)
               ? MockNearbyTransport(autoAcknowledge: true)
               : AndroidNearbyTransport()) {
    connectivityStatus =
        connectivityStatusService ?? ConnectivityStatusService();
    this.locationService =
        locationService ??
        (this.transport is! MockNearbyTransport &&
                defaultTargetPlatform == TargetPlatform.android
            ? GeolocatorLocationService()
            : FakeLocationService(
                const LocationResult.failure(LocationFailure.unavailable),
              ));
    mediaStorageService = mediaStorage ?? MediaStorageService();
    this.cloudDataSource = cloudDataSource ?? SupabaseCloudDataSource();
    authService = CloudAuthService(this.cloudDataSource);
    repositories = RelioRepositories(
      this.database,
      ownerUserIdProvider: () => this.cloudDataSource.currentIdentity?.userId,
    );
    identity = RelioDeviceIdentityRepository(this.database);
    this.permissionService =
        permissionService ??
        PermissionService(
          androidSdkReader: () async =>
              (await connectivityStatus.readRuntimeSnapshot()).androidSdk,
        );
    relayRepository = DriftRelayRepository(this.database);
    relayEngine = RelayEngine(
      transport: this.transport,
      identity: identity,
      repository: relayRepository,
      messages: repositories.messages,
      conversations: repositories.conversations,
      sos: repositories.sos,
      connectedPeers: () => nearbyService.connectedPeers,
      deviceIdForEndpoint: (endpointId) =>
          nearbyService.deviceIdForEndpoint(endpointId),
    );
    nearbyService = NearbyService(
      transport: this.transport,
      messages: repositories.messages,
      conversations: repositories.conversations,
      identity: identity,
      nearbyDevices: repositories.nearbyDevices,
      sos: repositories.sos,
      settings: repositories.settings,
      attachments: repositories.attachments,
      mediaStorage: mediaStorageService,
      relayEngine: relayEngine,
    );
    syncEngine = SyncEngine(
      repositories: repositories,
      cloud: this.cloudDataSource,
      identity: identity,
      mediaStorage: mediaStorageService,
    );
    this.appUpdateService = appUpdateService ?? AppUpdateService();
  }

  final AppDatabase database;
  final bool _isAndroid;
  final NearbyTransport transport;
  final bool useMockTransport;
  late final ConnectivityStatusService connectivityStatus;
  late final RelioRepositories repositories;
  late final RelioDeviceIdentityRepository identity;
  late final PermissionService permissionService;
  late final LocationService locationService;
  late final MediaStorageService mediaStorageService;
  late final NearbyService nearbyService;
  late final RelayRepository relayRepository;
  late final RelayEngine relayEngine;
  late final SyncEngine syncEngine;
  late final CloudDataSource cloudDataSource;
  late final AuthService authService;
  late final AppUpdateService appUpdateService;
  Future<void>? _initialization;
  StreamSubscription<InternetStatus>? _readinessSubscription;
  Future<bool>? _nearbySyncOperation;
  bool _nearbySyncAgain = false;
  bool _nearbyForeground = true;
  bool _nearbyRestart = false;
  bool _disposed = false;
  Timer? _nearbyHealthCheck;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<bool> startNearbySessionIfPermitted() {
    if (_disposed || !nearbyService.initialized) return Future.value(false);
    final active = _nearbySyncOperation;
    if (active != null) {
      _nearbySyncAgain = true;
      return active;
    }
    final operation = _drainNearbySession();
    _nearbySyncOperation = operation;
    return operation.whenComplete(() {
      if (identical(_nearbySyncOperation, operation)) {
        _nearbySyncOperation = null;
      }
    });
  }

  Future<bool> _drainNearbySession() async {
    var ready = false;
    do {
      _nearbySyncAgain = false;
      ready = await _syncNearbySession();
    } while (_nearbySyncAgain && !_disposed);
    return ready;
  }

  Future<bool> setNearbyForeground(bool foreground) {
    if (_nearbyForeground != foreground && foreground) _nearbyRestart = true;
    _nearbyForeground = foreground;
    return startNearbySessionIfPermitted();
  }

  Future<bool> _syncNearbySession() async {
    final runtime = await connectivityStatus.readRuntimeSnapshot();
    if (_disposed) return false;
    nearbyService.updateReadiness(runtime.nearbyReadiness);
    final ready = useMockTransport || runtime.nearbyReadiness.ready;
    if (!ready || !_nearbyForeground) {
      await nearbyService.stopSession();
      return false;
    }
    if (_nearbyRestart) {
      _nearbyRestart = false;
      await nearbyService.stopSession();
    }
    await nearbyService.startSession();
    return nearbyService.isAdvertising && nearbyService.isDiscovering;
  }

  Future<void> _initialize() async {
    if (_isAndroid && !useMockTransport) {
      _readinessSubscription = connectivityStatus.changes.listen((_) {
        unawaited(startNearbySessionIfPermitted());
      });
    }
    unawaited(connectivityStatus.initialize());
    await identity.getDeviceId();
    await identity.getDisplayName();
    await repositories.seedPrototypeData();
    await nearbyService.initialize();
    if (_isAndroid && !useMockTransport) {
      await startNearbySessionIfPermitted();
      // ตรวจซ้ำเฉพาะ foreground เพื่อจับสิทธิ์/GMS ที่ไม่ส่ง radio broadcast
      _nearbyHealthCheck = Timer.periodic(const Duration(seconds: 10), (_) {
        if (_nearbyForeground) unawaited(startNearbySessionIfPermitted());
      });
    }
    try {
      await cloudDataSource.initialize();
      await authService.restoreSession();
    } on Object {
      // Cloud is an optional v0.5 destination. Local startup must remain
      // healthy when credentials are absent or the network is unavailable.
    }
    await relayEngine.initialize();
    await syncEngine.initialize();
    // Startup sync runs asynchronously; rendering the local app never waits
    // for Cloud, and SyncEngine will only claim owned queue items.
    unawaited(syncEngine.run());
    // QA update checks use the official tester flow. The service throttles
    // automatic checks and never runs in DEV or PROD.
    unawaited(appUpdateService.checkForUpdate());
  }

  Future<void> dispose() async {
    _disposed = true;
    _nearbyHealthCheck?.cancel();
    await _readinessSubscription?.cancel();
    await _nearbySyncOperation;
    await connectivityStatus.dispose();
    await relayEngine.dispose();
    await nearbyService.close();
    await syncEngine.dispose();
    appUpdateService.dispose();
    await cloudDataSource.dispose();
    await database.close();
  }
}

bool get _defaultMockTransport {
  try {
    WidgetsBinding.instance;
    return false;
  } on Object {
    return true;
  }
}

class RelioDependencyScope extends InheritedWidget {
  const RelioDependencyScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  final RelioDependencies dependencies;

  static RelioDependencies of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RelioDependencyScope>();
    assert(
      scope != null,
      'RelioDependencyScope is missing above this context.',
    );
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(RelioDependencyScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}
