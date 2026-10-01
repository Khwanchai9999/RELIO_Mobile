import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'database/app_database.dart';
import '../app/environment.dart';
import 'connectivity/runtime_connectivity.dart';
import 'app_update/app_update_service.dart';
import 'cloud/auth_service.dart';
import 'cloud/cloud_data_source.dart';
import 'cloud/supabase_cloud_data_source.dart';
import 'location/location_service.dart';
import 'media/media_storage_service.dart';
import 'notifications/local_notification_service.dart';
import 'nearby/android_nearby_transport.dart';
import 'nearby/nearby_readiness.dart';
import 'nearby/nearby_service.dart';
import 'nearby/nearby_retry_backoff.dart';
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
    localNotificationService = _isAndroid
        ? AndroidLocalNotificationService()
        : const NoopLocalNotificationService();
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
      currentUserIdProvider: () => this.cloudDataSource.currentIdentity?.userId,
      sos: repositories.sos,
      settings: repositories.settings,
      attachments: repositories.attachments,
      mediaStorage: mediaStorageService,
      localNotifications: localNotificationService,
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
  late final LocalNotificationSink localNotificationService;
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
  bool _nearbyForeground = true;
  bool _nearbyRestart = false;
  bool _disposed = false;
  Timer? _nearbyHealthCheck;
  Timer? _nearbyRetryTimer;
  final NearbyRetryBackoff _nearbyRetryBackoff = NearbyRetryBackoff();
  String? _lastNearbyReadinessSignature;

  int get nearbyRetryAttempt => _nearbyRetryBackoff.attempt;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<bool> syncPushRegistration() async {
    if (!RelioBuildInfo.isTest ||
        cloudDataSource.currentIdentity == null ||
        !cloudDataSource.configuration.isConfigured ||
        !await repositories.settings.getBool(
          'notifications_enabled',
          defaultValue: true,
        ) ||
        !await localNotificationService.notificationsAllowed) {
      return false;
    }
    try {
      final token = await localNotificationService.getFcmToken();
      if (token == null || token.isEmpty) return false;
      await cloudDataSource.upsertPushToken(
        deviceId: await identity.getDeviceId(),
        token: token,
      );
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> removePushRegistration() async {
    if (!RelioBuildInfo.isTest || cloudDataSource.currentIdentity == null) {
      return false;
    }
    try {
      await cloudDataSource.deletePushToken(
        deviceId: await identity.getDeviceId(),
      );
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> startNearbySessionIfPermitted({bool force = false}) {
    if (_disposed || !nearbyService.initialized) return Future.value(false);
    final active = _nearbySyncOperation;
    if (active != null) return active;
    final operation = _syncNearbySession(force: force);
    _nearbySyncOperation = operation;
    return operation.whenComplete(() {
      if (identical(_nearbySyncOperation, operation)) {
        _nearbySyncOperation = null;
      }
    });
  }

  Future<bool> setNearbyForeground(bool foreground) {
    final changed = _nearbyForeground != foreground;
    if (changed && foreground) _nearbyRestart = true;
    _nearbyForeground = foreground;
    final active = _nearbySyncOperation;
    if (active != null && changed) {
      return active.then((_) => startNearbySessionIfPermitted());
    }
    return startNearbySessionIfPermitted();
  }

  Future<bool> _syncNearbySession({required bool force}) async {
    final runtime = await connectivityStatus.readRuntimeSnapshot();
    if (_disposed) return false;
    final readiness = runtime.nearbyReadiness;
    final signature = _readinessSignature(readiness);
    final readinessChanged = _lastNearbyReadinessSignature != signature;
    _lastNearbyReadinessSignature = signature;
    nearbyService.updateDeviceModel(runtime.deviceModel);
    nearbyService.updateReadiness(readiness);
    final ready = useMockTransport || readiness.ready;
    if (!ready || !_nearbyForeground) {
      _nearbyRetryTimer?.cancel();
      _nearbyRetryTimer = null;
      _nearbyRetryBackoff.reset();
      await nearbyService.stopSession();
      return false;
    }
    if (readinessChanged && readiness.ready) {
      _nearbyRetryTimer?.cancel();
      _nearbyRetryTimer = null;
      _nearbyRetryBackoff.reset();
    }
    if (_nearbyRetryTimer?.isActive == true && !force) return false;
    if (force) {
      _nearbyRetryTimer?.cancel();
      _nearbyRetryTimer = null;
    }
    if (nearbyService.isAdvertising && nearbyService.isDiscovering) {
      _nearbyRetryTimer?.cancel();
      _nearbyRetryTimer = null;
      _nearbyRetryBackoff.reset();
      return true;
    }
    if (_nearbyRestart) {
      _nearbyRestart = false;
      await nearbyService.stopSession();
    }
    nearbyService.startRetryAttempt = _nearbyRetryBackoff.attempt + 1;
    await nearbyService.startSession();
    final started = nearbyService.isAdvertising && nearbyService.isDiscovering;
    if (started) {
      _nearbyRetryTimer?.cancel();
      _nearbyRetryTimer = null;
      _nearbyRetryBackoff.reset();
    } else {
      final delay = _nearbyRetryBackoff.registerFailure();
      nearbyService.logRetryScheduled(_nearbyRetryBackoff.attempt, delay);
      _nearbyRetryTimer?.cancel();
      _nearbyRetryTimer = Timer(delay, () {
        if (!_disposed && _nearbyForeground) {
          unawaited(startNearbySessionIfPermitted(force: true));
        }
      });
    }
    return started;
  }

  String _readinessSignature(NearbyReadiness readiness) => [
    readiness.policy.sdkInt,
    readiness.policy.targetSdk,
    readiness.playServicesStatus,
    readiness.transportAvailable,
    readiness.bluetoothAvailable,
    readiness.bluetoothEnabled,
    readiness.wifiAvailable,
    readiness.wifiEnabled,
    readiness.locationEnabled,
    ...readiness.missingPermissions,
    ...readiness.missingManifestPermissions,
    ...readiness.blockers.map((blocker) => blocker.name),
  ].join('/');

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
      _nearbyHealthCheck = Timer.periodic(const Duration(seconds: 60), (_) {
        if (_nearbyForeground) unawaited(startNearbySessionIfPermitted());
      });
    }
    try {
      await cloudDataSource.initialize();
      await authService.restoreSession();
      unawaited(syncPushRegistration());
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
    _nearbyRetryTimer?.cancel();
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
