import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'database/app_database.dart';
import '../app/environment.dart';
import 'connectivity/runtime_connectivity.dart';
import 'connectivity/qa_internet_simulator.dart';
import 'app_update/app_update_service.dart';
import 'cloud/auth_service.dart';
import 'cloud/cloud_data_source.dart';
import 'cloud/supabase_cloud_data_source.dart';
import 'diagnostics/diagnostics_log_service.dart';
import 'device/battery_info_service.dart';
import 'location/location_service.dart';
import 'media/media_storage_service.dart';
import 'notifications/local_notification_service.dart';
import 'nearby/android_nearby_transport.dart';
import 'nearby/bluetooth_classic_transport.dart';
import 'nearby/nearby_readiness.dart';
import 'nearby/nearby_service.dart';
import 'nearby/nearby_retry_backoff.dart';
import 'nearby/nearby_transport.dart';
import 'permissions/permission_service.dart';
import 'repositories/local_repositories.dart';
import 'feature_flags/feature_flags.dart';
import 'repositories/profile_avatar_repository.dart';
import 'relay/relay_engine.dart';
import 'relay/relay_repository.dart';
import 'sync/sync_engine.dart';

class RelioDependencies {
  RelioDependencies({
    AppDatabase? database,
    NearbyTransport? transport,
    FeatureFlagController? featureFlags,
    bool? useMockTransport,
    LocationService? locationService,
    BatteryInfoService? batteryInfoService,
    MediaStorageService? mediaStorage,
    ProfileAvatarRepository? profileAvatarRepository,
    LocalNotificationSink? localNotificationSink,
    CloudDataSource? cloudDataSource,
    AppUpdateService? appUpdateService,
    ConnectivityStatusService? connectivityStatusService,
    QaInternetSimulator? internetSimulator,
    PermissionService? permissionService,
    bool? androidPlatformOverride,
    Duration connectionAttemptTimeout = const Duration(seconds: 35),
    Duration incomingApprovalTimeout = const Duration(seconds: 90),
    Duration hardNegotiationTimeout = const Duration(seconds: 90),
  }) : database = database ?? AppDatabase(),
       _isAndroid = androidPlatformOverride ?? Platform.isAndroid,
       useMockTransport = useMockTransport ?? _defaultMockTransport,
       transport =
           transport ??
           ((useMockTransport ?? _defaultMockTransport)
               ? MockNearbyTransport(autoAcknowledge: true)
               : (!RelioBuildInfo.developerDiagnosticsEnabled ||
                     !Platform.isAndroid)
               ? AndroidNearbyTransport()
               : CompatibilityNearbyTransport(
                   primary: AndroidNearbyTransport(),
                   compatibility: BluetoothClassicTransport(),
                 )) {
    this.internetSimulator = internetSimulator ?? QaInternetSimulator();
    connectivityStatus =
        connectivityStatusService ??
        ConnectivityStatusService(internetSimulator: this.internetSimulator);
    diagnostics = DiagnosticsLogService();
    this.locationService =
        locationService ??
        (this.transport is! MockNearbyTransport &&
                defaultTargetPlatform == TargetPlatform.android
            ? GeolocatorLocationService()
            : FakeLocationService(
                const LocationResult.failure(LocationFailure.unavailable),
              ));
    this.batteryInfoService =
        batteryInfoService ?? (_isAndroid ? BatteryPlusInfoService() : null);
    mediaStorageService = mediaStorage ?? MediaStorageService();
    localNotificationService =
        localNotificationSink ??
        (_isAndroid
            ? AndroidLocalNotificationService()
            : const NoopLocalNotificationService());
    this.cloudDataSource =
        cloudDataSource ??
        SupabaseCloudDataSource(internetSimulator: this.internetSimulator);

    repositories = RelioRepositories(
      this.database,
      ownerUserIdProvider: () => this.cloudDataSource.currentIdentity?.userId,
      ownerScopeChanges: this.cloudDataSource.watchAuthState().map<Object?>(
        (state) => state,
      ),
    );
    this.featureFlags =
        featureFlags ?? createFeatureFlagController(repositories.settings);
    repositories.profiles.cloud = this.cloudDataSource;
    authService = CloudAuthService(
      this.cloudDataSource,
      rebind: repositories.profiles.refresh,
    );
    identity = RelioDeviceIdentityRepository(
      this.database,
      profiles: repositories.profiles,
    );
    this.profileAvatarRepository =
        profileAvatarRepository ?? ProfileAvatarRepository(this.database);
    this.profileAvatarRepository.bindProfiles(repositories.profiles);
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
      diagnostics: diagnostics,
      batteryInfo: this.batteryInfoService,
      connectionAttemptTimeout: connectionAttemptTimeout,
      incomingApprovalTimeout: incomingApprovalTimeout,
      hardNegotiationTimeout: hardNegotiationTimeout,
    );
    syncEngine = SyncEngine(
      repositories: repositories,
      cloud: this.cloudDataSource,
      identity: identity,
      mediaStorage: mediaStorageService,
      localNotifications: localNotificationService,
      diagnostics: diagnostics,
      internetSimulator: this.internetSimulator,
      isConversationActive: (conversationId) =>
          nearbyService.isConversationVisible(conversationId),
    );
    this.appUpdateService =
        appUpdateService ??
        AppUpdateService(
          internetAvailable: () => this.internetSimulator.internetAvailable,
        );
  }

  final AppDatabase database;
  final bool _isAndroid;
  final NearbyTransport transport;
  final bool useMockTransport;
  late final ConnectivityStatusService connectivityStatus;
  late final QaInternetSimulator internetSimulator;
  late final DiagnosticsLogService diagnostics;
  late final BatteryInfoService? batteryInfoService;
  late final RelioRepositories repositories;
  late final FeatureFlagController featureFlags;
  late final RelioDeviceIdentityRepository identity;
  late final ProfileAvatarRepository profileAvatarRepository;
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
  Future<void>? _authInitialization;
  Future<void>? _internetSimulatorInitialization;
  bool _authInitialized = false;
  StreamSubscription<InternetStatus>? _readinessSubscription;
  Future<bool>? _nearbySyncOperation;
  bool _nearbyForeground = true;
  bool _nearbyRestart = false;
  bool _nearbySessionSyncDeferred = false;
  bool _backgroundStopDeferred = false;
  bool _nearbyServiceListenerAttached = false;
  bool _disposed = false;
  Timer? _nearbyHealthCheck;
  Timer? _nearbyRetryTimer;
  Timer? _backgroundNegotiationGraceTimer;
  final NearbyRetryBackoff _nearbyRetryBackoff = NearbyRetryBackoff();
  String? _lastNearbyReadinessSignature;

  int get nearbyRetryAttempt => _nearbyRetryBackoff.attempt;

  bool get authInitialized => _authInitialized;

  Future<void> initializeAuth() => _authInitialization ??= _initializeAuth();

  Future<void> _restoreInternetSimulator() =>
      _internetSimulatorInitialization ??= _loadInternetSimulatorState();

  Future<void> _loadInternetSimulatorState() async {
    if (!internetSimulator.available) return;
    final offline = await repositories.settings.getBool(
      'qa_simulated_internet_offline',
      defaultValue: internetSimulator.bootOfflineOverride,
    );
    internetSimulator.restore(offline);
    if (internetSimulator.bootOfflineOverride) {
      await repositories.settings.setBool(
        'qa_simulated_internet_offline',
        offline,
      );
    }
  }

  Future<void> _initializeAuth() async {
    try {
      await featureFlags.initialize();
      await _restoreInternetSimulator();
      await cloudDataSource.initialize();
      await authService.restoreSession();
      unawaited(syncPushRegistration());
    } on Object {
      // Cloud เป็น optional; เมื่อกู้ session ไม่ได้ ให้ startup ไปหน้า Welcome
    } finally {
      _authInitialized = true;
    }
  }

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
    if (changed && nearbyService.hasActiveConnectionAttempts) {
      diagnostics.record(
        'lifecycle',
        'app_lifecycle_changed_during_negotiation',
        operation: 'setNearbyForeground',
        fields: {
          'foreground': foreground,
          'activeConnectionAttempts': nearbyService.activeConnectionAttempts,
          'appLifecycleState': nearbyService.appLifecycleState,
        },
      );
    }
    if (changed && !foreground && nearbyService.hasActiveConnectionAttempts) {
      _backgroundStopDeferred = true;
      // รักษา native negotiation ไว้ระหว่าง lifecycle สั้น ๆ; hard watchdog
      // ของ NearbyService เป็นเจ้าของการตัด stale attempt เพียงจุดเดียว
      _backgroundNegotiationGraceTimer?.cancel();
      _backgroundNegotiationGraceTimer = null;
      diagnostics.record(
        'lifecycle',
        'session_stop_deferred_active_connection',
        operation: 'setNearbyForeground',
        fields: {
          'activeConnectionAttempts': nearbyService.activeConnectionAttempts,
          'hardWatchdogMs': nearbyService.hardNegotiationTimeout.inMilliseconds,
          'appLifecycleState': nearbyService.appLifecycleState,
        },
      );
      return Future.value(true);
    }
    if (changed && foreground) {
      _backgroundNegotiationGraceTimer?.cancel();
      _backgroundNegotiationGraceTimer = null;
      _backgroundStopDeferred = false;
    }
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
    if (nearbyService.hasActiveConnectionAttempts) {
      final mustDefer =
          !ready ||
          !_nearbyForeground ||
          !nearbyService.isAdvertising ||
          !nearbyService.isDiscovering ||
          (_nearbyRestart && !(_nearbyForeground && ready));
      if (mustDefer) {
        if (!_nearbySessionSyncDeferred) {
          diagnostics.record(
            !ready || !_nearbyForeground ? 'lifecycle' : 'nearby',
            !ready || !_nearbyForeground
                ? 'session_stop_deferred_active_connection'
                : 'session_restart_deferred_active_connection',
            operation: 'RelioDependencies._syncNearbySession',
            fields: {
              'activeConnectionAttempts':
                  nearbyService.activeConnectionAttempts,
              'ready': ready,
              'foreground': _nearbyForeground,
              'advertisingActive': nearbyService.isAdvertising,
              'discoveryActive': nearbyService.isDiscovering,
              'appLifecycleState': nearbyService.appLifecycleState,
            },
          );
        }
        _nearbySessionSyncDeferred = true;
        return nearbyService.isAdvertising && nearbyService.isDiscovering;
      }
      if (_nearbyRestart &&
          _nearbyForeground &&
          ready &&
          nearbyService.isAdvertising &&
          nearbyService.isDiscovering) {
        _nearbyRestart = false;
      }
    }
    _nearbySessionSyncDeferred = false;
    if (!ready || !_nearbyForeground) {
      if (_nearbyRetryTimer?.isActive == true) {
        diagnostics.record(
          'nearby',
          'retry_cancelled',
          operation: 'sessionStart',
          fields: {
            'reason': !ready ? 'readiness_unavailable' : 'app_backgrounded',
            'attempt': _nearbyRetryBackoff.attempt,
          },
        );
      }
      _nearbyRetryTimer?.cancel();
      _nearbyRetryTimer = null;
      _nearbyRetryBackoff.reset();
      await nearbyService.stopSession(
        reason: !ready ? 'nearby_readiness_unavailable' : 'app_backgrounded',
        caller: 'RelioDependencies._syncNearbySession',
      );
      return false;
    }
    if (readinessChanged && readiness.ready) {
      if (_nearbyRetryTimer?.isActive == true) {
        diagnostics.record(
          'nearby',
          'retry_cancelled',
          operation: 'sessionStart',
          fields: {
            'reason': 'readiness_changed',
            'attempt': _nearbyRetryBackoff.attempt,
          },
        );
      }
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
      await nearbyService.stopSession(
        reason: 'foreground_or_readiness_restart',
        caller: 'RelioDependencies._syncNearbySession',
      );
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
      diagnostics.record(
        'nearby',
        'retry_scheduled',
        operation: 'sessionStart',
        fields: {
          'attempt': _nearbyRetryBackoff.attempt + 1,
          'delayMs': delay.inMilliseconds,
        },
      );
      _nearbyRetryTimer?.cancel();
      _nearbyRetryTimer = Timer(delay, () {
        if (!_disposed && _nearbyForeground) {
          diagnostics.record(
            'nearby',
            'retry_started',
            operation: 'sessionStart',
            fields: {'attempt': _nearbyRetryBackoff.attempt + 1},
          );
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
    await featureFlags.initialize();
    await _restoreInternetSimulator();
    unawaited(diagnostics.initialize());
    if (_isAndroid && !useMockTransport) {
      _readinessSubscription = connectivityStatus.changes.listen((_) {
        unawaited(startNearbySessionIfPermitted());
        unawaited(syncEngine.run());
      });
    }
    unawaited(connectivityStatus.initialize());
    await identity.getDeviceId();
    await identity.getDisplayName();
    await repositories.seedPrototypeData();
    await nearbyService.initialize();
    nearbyService.addListener(_onNearbyServiceChanged);
    _nearbyServiceListenerAttached = true;
    if (_isAndroid && !useMockTransport) {
      await startNearbySessionIfPermitted();
      // ตรวจซ้ำเฉพาะ foreground เพื่อจับสิทธิ์/GMS ที่ไม่ส่ง radio broadcast
      _nearbyHealthCheck = Timer.periodic(const Duration(seconds: 60), (_) {
        if (_nearbyForeground) unawaited(startNearbySessionIfPermitted());
      });
    }
    await initializeAuth();
    await relayEngine.initialize();
    await syncEngine.initialize();
    // Startup sync runs asynchronously; rendering the local app never waits
    // for Cloud, and SyncEngine will only claim owned queue items.
    unawaited(syncEngine.run());
    // QA update checks use the official tester flow. The service throttles
    // automatic checks and never runs in DEV or PROD.
    unawaited(appUpdateService.checkForUpdate());
  }

  void _onNearbyServiceChanged() {
    if (_disposed || nearbyService.hasActiveConnectionAttempts) return;
    if (_backgroundStopDeferred || _nearbySessionSyncDeferred) {
      _backgroundNegotiationGraceTimer?.cancel();
      _backgroundNegotiationGraceTimer = null;
      _backgroundStopDeferred = false;
      _nearbySessionSyncDeferred = false;
      unawaited(startNearbySessionIfPermitted(force: true));
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _nearbyHealthCheck?.cancel();
    _nearbyRetryTimer?.cancel();
    _backgroundNegotiationGraceTimer?.cancel();
    if (_nearbyServiceListenerAttached) {
      nearbyService.removeListener(_onNearbyServiceChanged);
    }
    await _readinessSubscription?.cancel();
    await _nearbySyncOperation;
    await connectivityStatus.dispose();
    internetSimulator.dispose();
    await relayEngine.dispose();
    await nearbyService.close();
    await syncEngine.dispose();
    appUpdateService.dispose();
    await cloudDataSource.dispose();
    featureFlags.dispose();
    repositories.profiles.dispose();
    await repositories.ownerContext.dispose();
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
