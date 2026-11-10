import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'database/app_database.dart';
import 'domain/relio_entities.dart';
import '../app/environment.dart';
import 'connectivity/runtime_connectivity.dart';
import 'connectivity/qa_internet_simulator.dart';
import 'emergency/emergency_runtime_service.dart';
import 'app_update/app_update_service.dart';
import 'cloud/auth_service.dart';
import 'cloud/cloud_data_source.dart';
import 'cloud/cloud_models.dart';
import 'cloud/supabase_cloud_data_source.dart';
import 'diagnostics/diagnostics_log_service.dart';
import 'developer/internal_experience_controller.dart';
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
    EmergencyRuntimeService? emergencyRuntimeService,
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
    this.emergencyRuntimeService =
        emergencyRuntimeService ?? AndroidEmergencyRuntimeService();
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

    _cloudAuthSubscription = this.cloudDataSource.watchAuthState().listen((
      state,
    ) {
      _ownerScopeChanges.add(state);
      final identity = this.cloudDataSource.currentIdentity;
      final guestIdentity = _isGuestCloudIdentity(identity);
      if (state == AuthState.authenticated &&
          _guestModeExited &&
          !guestIdentity) {
        unawaited(_clearGuestExitHold());
      }
      if (state == AuthState.authenticated &&
          _guestModeSelected &&
          !guestIdentity) {
        _guestModeSelected = false;
        unawaited(
          repositories.settings.setValue('selected_user_mode', 'account'),
        );
      }
      if (state == AuthState.guest &&
          this.internetSimulator.internetAvailable &&
          _authInitialized &&
          _offlineAuthenticatedUserId != null &&
          !_authRestoreTransientFailure) {
        unawaited(_clearOfflineAuthenticatedPrincipal());
      }
    });
    this.internetSimulator.addListener(_handleInternetSimulatorChanged);

    repositories = RelioRepositories(
      this.database,
      ownerUserIdProvider: _activeOwnerUserId,
      ownerScopeChanges: _ownerScopeChanges.stream,
    );
    internalExperience = InternalExperienceController(
      repositories.settings,
      onDemoEnabled: repositories.seedPrototypeData,
    );
    this.featureFlags =
        featureFlags ?? createFeatureFlagController(repositories.settings);
    repositories.profiles.cloud = this.cloudDataSource;
    authService = CloudAuthService(
      this.cloudDataSource,
      rebind: repositories.profiles.refresh,
      onAuthenticated: _rememberOfflineAuthenticatedPrincipal,
      onRestored: _restoreAuthenticatedPrincipal,
      onSignOut: _clearOfflineAuthenticatedPrincipal,
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
      connectedPeers: () => nearbyService.authenticatedConnectedPeers,
      receiptPeers: () => nearbyService.authenticatedConnectedPeers,
      deviceIdForEndpoint: (endpointId) =>
          nearbyService.deviceIdForEndpoint(endpointId),
      nextHopHasRoute: (nextHop, destination, maxHops) =>
          nearbyService.checkQaRelayRoute(
            middleDeviceId: nextHop,
            destinationDeviceId: destination,
            maxHops: maxHops,
          ),
      diagnostics: diagnostics,
      forwardingAllowed: () =>
          !RelioBuildInfo.isTest ||
          _nearbyForeground ||
          _backgroundRelayEnabled,
      relayParticipationAllowed: getRelayParticipationConsent,
      secureRelayEnabled: () => false,
      qaPlaintextTextAllowed: () => nearbyService.qaPlaintextTextEnabled,
      qaTextForwardingPaused: () => qaTextForwardingPaused,
      verifyRelayedOrigin: (envelope, packet) =>
          nearbyService.verifyRelayedOrigin(envelope, packet),
      receiveRelayedSos: (endpointId, packet) =>
          nearbyService.receiveRelayedSos(endpointId, packet),
      receiveRelayedRescue: (endpointId, packet) =>
          nearbyService.receiveRelayedRescue(endpointId, packet),
    );
    nearbyService = NearbyService(
      transport: this.transport,
      messages: repositories.messages,
      conversations: repositories.conversations,
      identity: identity,
      nearbyDevices: repositories.nearbyDevices,
      currentUserIdProvider: _activeOwnerUserId,
      sos: repositories.sos,
      settings: repositories.settings,
      attachments: repositories.attachments,
      mediaStorage: mediaStorageService,
      profileAvatar: this.profileAvatarRepository,
      localNotifications: localNotificationService,
      relayEngine: relayEngine,
      reachabilityRelayAllowed: getRelayParticipationConsent,
      backgroundRelayAllowed: () => _backgroundRelayEnabled,
      diagnostics: diagnostics,
      readRuntimeSnapshot: connectivityStatus.readRuntimeSnapshot,
      batteryInfo: this.batteryInfoService,
      locationService: this.locationService,
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
      isGuestBackupSession: () => isGuestCloudBackupSession,
      privateBackupEnabled: automaticPrivateBackupEnabled,
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
  late final InternalExperienceController internalExperience;
  late final FeatureFlagController featureFlags;
  late final RelioDeviceIdentityRepository identity;
  late final ProfileAvatarRepository profileAvatarRepository;
  late final PermissionService permissionService;
  late final EmergencyRuntimeService emergencyRuntimeService;
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
  Completer<void>? _localSeedReady;
  Future<void>? _authInitialization;
  Future<void>? _internetSimulatorInitialization;
  bool _authInitialized = false;
  StreamSubscription<InternetStatus>? _readinessSubscription;
  final StreamController<Object?> _ownerScopeChanges =
      StreamController<Object?>.broadcast(sync: true);
  final StreamController<void> _localAuthChanges =
      StreamController<void>.broadcast(sync: true);
  late final StreamSubscription<AuthState> _cloudAuthSubscription;
  StreamSubscription<RelioSosEvent?>? _localSosLocationSubscription;
  String? _offlineAuthenticatedUserId;
  Future<void>? _onlineAuthResume;
  Future<bool>? _nearbySyncOperation;
  bool _nearbyForeground = true;
  bool _emergencyRuntimeActive = false;
  bool _backgroundRelayEnabled = false;
  EmergencyMode? _runtimeServiceMode;
  bool _qaTextForwardingPaused = false;
  bool get qaTextForwardingPaused =>
      RelioBuildInfo.isTest && _qaTextForwardingPaused;

  Future<void> setQaTextForwardingPaused(bool paused) async {
    if (!RelioBuildInfo.isTest) throw StateError('QA-only forwarding control');
    await repositories.settings.setBool('qa_text_forwarding_paused', paused);
    _qaTextForwardingPaused = paused;
    diagnostics.record(
      'relay',
      paused ? 'qa_text_forwarding_paused' : 'qa_text_forwarding_resumed',
    );
    if (!paused) await relayEngine.forwardPending();
  }

  bool _nearbyRestart = false;
  bool _nearbySessionSyncDeferred = false;
  bool _backgroundStopDeferred = false;
  bool _nearbyServiceListenerAttached = false;
  bool _disposed = false;
  bool _guestModeExited = false;
  bool _guestModeSelected = false;
  String? _guestCloudUserId;
  String? _guestCloudPrincipalId;
  bool _guestCloudBindingValid = false;
  bool _authRestoreTransientFailure = false;
  Future<void>? _guestExitRestore;
  Future<CloudIdentity?>? _guestCloudOperation;
  Timer? _nearbyHealthCheck;
  Timer? _nearbyRetryTimer;
  Timer? _backgroundNegotiationGraceTimer;
  final NearbyRetryBackoff _nearbyRetryBackoff = NearbyRetryBackoff();
  String? _lastNearbyReadinessSignature;

  int get nearbyRetryAttempt => _nearbyRetryBackoff.attempt;

  Future<bool> startEmergencyRuntime(EmergencyMode mode) async {
    if (mode == EmergencyMode.nearbyRelay) {
      return setBackgroundRelayEnabled(true);
    }
    try {
      final started = await emergencyRuntimeService.start(mode);
      _emergencyRuntimeActive = started;
      _runtimeServiceMode = started ? mode : null;
      if (started && !_nearbyForeground) {
        await startNearbySessionIfPermitted();
      }
      return started;
    } on Object {
      _emergencyRuntimeActive = false;
      return false;
    }
  }

  Future<void> stopEmergencyRuntime() async {
    try {
      await emergencyRuntimeService.stop(mode: _runtimeServiceMode);
    } on Object {
      // ความล้มเหลวของ native service ไม่ควรทำให้การปิด SOS/Rescue ค้าง
    }
    _emergencyRuntimeActive = false;
    _runtimeServiceMode = null;
    final deviceId = await identity.getDeviceId();
    final activeSos = await repositories.sos.readActive(
      ownerDeviceId: deviceId,
    );
    final rescueEnabled = await repositories.settings.getBool(
      'rescue_mode',
      defaultValue: false,
    );
    final nextMode = activeSos != null
        ? EmergencyMode.sos
        : rescueEnabled
        ? EmergencyMode.rescue
        : _backgroundRelayEnabled
        ? EmergencyMode.nearbyRelay
        : null;
    if (nextMode != null) {
      try {
        _emergencyRuntimeActive = await emergencyRuntimeService.start(nextMode);
        _runtimeServiceMode = _emergencyRuntimeActive ? nextMode : null;
      } on Object {
        _emergencyRuntimeActive = false;
      }
    }
    if (!_nearbyForeground) {
      if (_emergencyRuntimeActive) {
        await startNearbySessionIfPermitted();
      } else {
        await nearbyService.stopSession(
          reason: 'emergency_runtime_stopped_in_background',
          caller: 'RelioDependencies.stopEmergencyRuntime',
        );
      }
    }
  }

  bool get backgroundRelayEnabled => _backgroundRelayEnabled;

  Future<String> _relayConsentSettingKey() async {
    final deviceId = await identity.getDeviceId();
    final profile = await identity.profiles.current();
    return 'relay_consent_v1:$deviceId:${profile.principalId}';
  }

  Future<bool> getRelayParticipationConsent() async => repositories.settings
      .getBool(await _relayConsentSettingKey(), defaultValue: false);

  Future<void> setRelayParticipationConsent(bool allowed) async {
    await repositories.settings.setBool(
      await _relayConsentSettingKey(),
      allowed,
    );
    nearbyService.refreshReachabilityConsent();
    if (allowed) await relayEngine.forwardPending();
  }

  Future<bool> setBackgroundRelayEnabled(bool enabled) async {
    if (!_isAndroid || useMockTransport) return false;
    if (enabled) {
      _backgroundRelayEnabled = true;
      await repositories.settings.setBool('background_relay_enabled', true);
      if (_runtimeServiceMode == EmergencyMode.sos ||
          _runtimeServiceMode == EmergencyMode.rescue) {
        await startNearbySessionIfPermitted(force: true);
        return true;
      }
      try {
        final started = await emergencyRuntimeService.start(
          EmergencyMode.nearbyRelay,
        );
        if (!started) {
          _backgroundRelayEnabled = false;
          await repositories.settings.setBool(
            'background_relay_enabled',
            false,
          );
          return false;
        }
        _backgroundRelayEnabled = true;
        _emergencyRuntimeActive = true;
        _runtimeServiceMode = EmergencyMode.nearbyRelay;
        await startNearbySessionIfPermitted(force: true);
        return true;
      } on Object {
        _backgroundRelayEnabled = false;
        await repositories.settings.setBool('background_relay_enabled', false);
        return false;
      }
    }
    _backgroundRelayEnabled = false;
    await repositories.settings.setBool('background_relay_enabled', false);
    if (_runtimeServiceMode == EmergencyMode.nearbyRelay) {
      try {
        await emergencyRuntimeService.stop(mode: EmergencyMode.nearbyRelay);
      } on Object {
        // เก็บ preference เป็นปิดไว้ แล้วให้ session reconciliation จัดการต่อ
      }
      _runtimeServiceMode = null;
      _emergencyRuntimeActive = await emergencyRuntimeService.isRunning();
    }
    if (!_nearbyForeground && !_emergencyRuntimeActive) {
      await nearbyService.stopSession(
        reason: 'background_relay_disabled',
        caller: 'RelioDependencies.setBackgroundRelayEnabled',
      );
    }
    return true;
  }

  Future<void> _restoreEmergencyRuntimeFromLocalState() async {
    if (!_isAndroid ||
        (useMockTransport &&
            emergencyRuntimeService is AndroidEmergencyRuntimeService)) {
      return;
    }
    try {
      _backgroundRelayEnabled = await repositories.settings.getBool(
        'background_relay_enabled',
        defaultValue: false,
      );
      final deviceId = await identity.getDeviceId();
      final activeSos = await repositories.sos.readActive(
        ownerDeviceId: deviceId,
      );
      final rescueEnabled = await repositories.settings.getBool(
        'rescue_mode',
        defaultValue: false,
      );
      final mode = activeSos != null
          ? EmergencyMode.sos
          : rescueEnabled
          ? EmergencyMode.rescue
          : null;
      if (mode == null) {
        if (_backgroundRelayEnabled) {
          _emergencyRuntimeActive = await emergencyRuntimeService.isRunning(
            mode: EmergencyMode.nearbyRelay,
          );
          if (!_emergencyRuntimeActive) {
            _emergencyRuntimeActive = await emergencyRuntimeService.start(
              EmergencyMode.nearbyRelay,
            );
          }
          _runtimeServiceMode = _emergencyRuntimeActive
              ? EmergencyMode.nearbyRelay
              : null;
        } else if (await emergencyRuntimeService.isRunning()) {
          await emergencyRuntimeService.stop();
        }
        return;
      }

      // SQLite เป็นแหล่งจริงของ SOS/Rescue; การ restore นี้เริ่ม runtime เท่านั้น
      // ไม่ส่ง SOS ซ้ำหรือสร้างเหตุการณ์ฉุกเฉินใหม่
      await startEmergencyRuntime(mode);
    } on Object catch (error) {
      diagnostics.record(
        'emergency',
        'startup_runtime_restore_failed',
        fields: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  bool get authInitialized => _authInitialized;
  bool get hasAuthenticatedPrincipal =>
      (cloudDataSource.currentIdentity != null &&
          !_isGuestCloudIdentity(cloudDataSource.currentIdentity)) ||
      _offlineAuthenticatedUserId != null;
  bool get isGuestApplicationMode => _guestModeSelected && !_guestModeExited;
  bool get isGuestCloudSession =>
      _isGuestCloudIdentity(cloudDataSource.currentIdentity);
  bool get isGuestCloudBackupSession =>
      _guestModeSelected &&
      !_guestModeExited &&
      _guestCloudBindingValid &&
      cloudDataSource.currentIdentity?.userId == _guestCloudUserId;
  bool get hasSelectedUserSession =>
      hasAuthenticatedPrincipal || (_guestModeSelected && !_guestModeExited);
  bool get hasOfflineAuthenticatedPrincipal =>
      _offlineAuthenticatedUserId != null &&
      cloudDataSource.currentIdentity == null;
  Stream<void> get localAuthChanges => _localAuthChanges.stream;

  Future<void> _restoreGuestExitHold() => _guestExitRestore ??= () async {
    _guestModeExited = await repositories.settings.getBool(
      'guest_mode_exited',
      defaultValue: false,
    );
    final selectedMode = await repositories.settings.getValue(
      'selected_user_mode',
    );
    _guestModeSelected = selectedMode == 'guest' && !_guestModeExited;
    _guestCloudUserId = await repositories.settings.getValue(
      RelioSettingsRepository.guestCloudUserIdKey,
    );
    _guestCloudPrincipalId = await repositories.settings.getValue(
      RelioSettingsRepository.guestCloudPrincipalIdKey,
    );
    final guestPrincipal = await repositories.profiles.guestPrincipal();
    _guestCloudBindingValid =
        _guestCloudUserId?.isNotEmpty == true &&
        _guestCloudPrincipalId == guestPrincipal;
  }();

  bool _isGuestCloudIdentity(CloudIdentity? identity) =>
      identity != null &&
      (identity.isAnonymous ||
          (_guestModeSelected &&
              !_guestModeExited &&
              _guestCloudBindingValid &&
              identity.userId == _guestCloudUserId));

  String? _activeOwnerUserId() {
    final cloudIdentity = cloudDataSource.currentIdentity;
    if (_isGuestCloudIdentity(cloudIdentity)) return null;
    return cloudIdentity?.userId ?? _offlineAuthenticatedUserId;
  }

  Future<void> _restoreAuthenticatedPrincipal(String userId) async {
    await _restoreGuestExitHold();
    if (_guestModeSelected &&
        _guestCloudBindingValid &&
        userId == _guestCloudUserId) {
      return;
    }
    await _rememberOfflineAuthenticatedPrincipal(userId);
  }

  // เคารพค่าที่บันทึกไว้ก่อนเสมอ หากยังไม่มีค่าจึงใช้ Guest ปิดและ Member เปิดเป็นค่าเริ่มต้น
  Future<bool> automaticPrivateBackupEnabled({required bool guestMode}) async {
    final stored = await repositories.settings.getNullableBool(
      RelioSettingsRepository.automaticPrivateBackupKey,
    );
    return stored ?? !guestMode;
  }

  Future<CloudIdentity?> ensureGuestCloudIdentity({
    bool forEmailUpgrade = false,
  }) {
    final active = _guestCloudOperation;
    if (active != null) return active;
    final operation = _ensureGuestCloudIdentity(
      forEmailUpgrade: forEmailUpgrade,
    );
    _guestCloudOperation = operation;
    return operation.whenComplete(() {
      if (identical(_guestCloudOperation, operation)) {
        _guestCloudOperation = null;
      }
    });
  }

  Future<CloudIdentity?> _ensureGuestCloudIdentity({
    required bool forEmailUpgrade,
  }) async {
    await _restoreGuestExitHold();
    if (!_guestModeSelected || _guestModeExited) return null;
    if (!forEmailUpgrade &&
        !await automaticPrivateBackupEnabled(guestMode: true)) {
      return null;
    }
    if (!internetSimulator.internetAvailable ||
        !cloudDataSource.configuration.isConfigured) {
      return null;
    }

    await cloudDataSource.initialize();
    final guestPrincipal = await repositories.profiles.guestPrincipal();
    final savedUserId = await repositories.settings.getValue(
      RelioSettingsRepository.guestCloudUserIdKey,
    );
    final savedPrincipalId = await repositories.settings.getValue(
      RelioSettingsRepository.guestCloudPrincipalIdKey,
    );
    if ((savedUserId == null) != (savedPrincipalId == null) ||
        (savedPrincipalId != null && savedPrincipalId != guestPrincipal)) {
      throw const CloudException(
        'ข้อมูลผูกบัญชี Guest ไม่ตรงกับเครื่องนี้ จึงหยุด Cloud ไว้เพื่อรักษาข้อมูล',
        code: 'guestBindingMismatch',
      );
    }

    var identity = cloudDataSource.currentIdentity;
    if (identity == null) {
      if (savedUserId != null) {
        throw const CloudException(
          'เซสชัน Guest บน Cloud หายไป ข้อมูลสำรองเดิมยังคงอยู่แต่สร้างบัญชีใหม่แทนไม่ได้',
          code: 'guestSessionLost',
        );
      }
      identity = await authService.signInAnonymously();
    } else if (identity.isAnonymous && savedUserId == null) {
      throw const CloudException(
        'พบ Cloud Guest session ที่ยังไม่ผูกกับข้อมูล Guest ในเครื่อง จึงไม่เชื่อมข้อมูลโดยคาดเดา',
        code: 'guestBindingMissing',
      );
    }
    if (identity.isAnonymous == false &&
        !(savedUserId == identity.userId &&
            savedPrincipalId == guestPrincipal)) {
      return null;
    }
    final bound = await repositories.settings.bindGuestCloudIdentity(
      guestUserId: identity.userId,
      guestPrincipalId: guestPrincipal,
    );
    if (!bound) {
      throw const CloudException(
        'บัญชี Cloud นี้ผูกกับข้อมูล Guest ชุดอื่น จึงไม่เริ่มซิงก์',
        code: 'guestBindingMismatch',
      );
    }
    _guestCloudUserId = identity.userId;
    _guestCloudPrincipalId = guestPrincipal;
    _guestCloudBindingValid = true;
    _ownerScopeChanges.add(null);
    _localAuthChanges.add(null);
    return identity;
  }

  Future<void> _maybeStartGuestCloudBackup() async {
    if (!_authInitialized ||
        _disposed ||
        !_guestModeSelected ||
        _guestModeExited ||
        !internetSimulator.internetAvailable ||
        !await automaticPrivateBackupEnabled(guestMode: true)) {
      return;
    }
    try {
      final runtime = await connectivityStatus.readRuntimeSnapshot().timeout(
        const Duration(seconds: 2),
      );
      if (runtime.hasInternetRoute == false ||
          runtime.internetValidated == false) {
        return;
      }
      await ensureGuestCloudIdentity();
      if (cloudDataSource.currentIdentity?.isAnonymous == true ||
          (_guestCloudBindingValid &&
              cloudDataSource.currentIdentity?.userId == _guestCloudUserId)) {
        unawaited(syncEngine.run());
      }
    } on Object catch (error) {
      final code = error is CloudException ? error.code : 'guest_auth_failed';
      diagnostics.record(
        'cloud',
        'guest_backup_auth_blocked',
        fields: {'reason': code},
      );
    }
  }

  Future<void> _clearGuestExitHold() async {
    _guestModeExited = false;
    await repositories.settings.setBool('guest_mode_exited', false);
  }

  Future<bool> exitGuestMode() async {
    if (hasAuthenticatedPrincipal) return false;
    await _restoreGuestExitHold();
    final activeOperation = _nearbySyncOperation;
    if (activeOperation != null) await activeOperation;
    if (nearbyService.hasActiveConnectionAttempts ||
        nearbyService.connectedPeers.isNotEmpty) {
      return false;
    }

    _guestModeExited = true;
    _guestModeSelected = false;
    try {
      await repositories.settings.setValue('selected_user_mode', 'welcome');
      await repositories.settings.setBool('guest_mode_exited', true);
      await nearbyService.stopSession(
        reason: 'guest_mode_exit',
        caller: 'RelioDependencies.exitGuestMode',
      );
      // ถ้ามี peer เข้ามาระหว่างหยุด discovery ให้ยกเลิกการออกและรักษา session ไว้
      if (nearbyService.hasActiveConnectionAttempts ||
          nearbyService.connectedPeers.isNotEmpty) {
        _guestModeSelected = true;
        await repositories.settings.setValue('selected_user_mode', 'guest');
        await _clearGuestExitHold();
        return false;
      }
      _localAuthChanges.add(null);
      return true;
    } on Object {
      _guestModeSelected = true;
      await repositories.settings.setValue('selected_user_mode', 'guest');
      await _clearGuestExitHold();
      rethrow;
    }
  }

  Future<void> resumeGuestMode() async {
    if (hasAuthenticatedPrincipal) return;
    await _restoreGuestExitHold();
    await repositories.settings.setValue('selected_user_mode', 'guest');
    _guestModeSelected = true;
    final wasExited = _guestModeExited;
    if (wasExited) await _clearGuestExitHold();
    _localAuthChanges.add(null);
    if (wasExited && _nearbyForeground) {
      await startNearbySessionIfPermitted(force: true);
    }
    if (_authInitialized) unawaited(_maybeStartGuestCloudBackup());
  }

  Future<void> _rememberOfflineAuthenticatedPrincipal(String userId) async {
    final previousOwner = _activeOwnerUserId();
    await database.transaction(() async {
      await repositories.settings.setValue(
        'offline_authenticated_principal',
        userId,
      );
      await repositories.settings.setValue('selected_user_mode', 'account');
    });
    _offlineAuthenticatedUserId = userId;
    _guestModeSelected = false;
    if (previousOwner == userId) {
      _ownerScopeChanges.add(userId);
      _localAuthChanges.add(null);
      return;
    }
    _ownerScopeChanges.add(userId);
    _localAuthChanges.add(null);
  }

  Future<void> _restoreOfflineAuthenticatedPrincipal() async {
    final principal = (await repositories.settings.getValue(
      'offline_authenticated_principal',
    ))?.trim();
    if (principal == null || principal.isEmpty || principal.length > 128) {
      await repositories.settings.remove('offline_authenticated_principal');
      return;
    }
    if (_guestModeSelected && !_guestModeExited) {
      _offlineAuthenticatedUserId = null;
      _ownerScopeChanges.add(null);
      _localAuthChanges.add(null);
      return;
    }
    _offlineAuthenticatedUserId = principal;
    _ownerScopeChanges.add(principal);
    _localAuthChanges.add(null);
  }

  Future<void> _clearOfflineAuthenticatedPrincipal() async {
    if (_guestModeSelected && !_guestModeExited) {
      _offlineAuthenticatedUserId = null;
      _ownerScopeChanges.add(null);
      _localAuthChanges.add(null);
      return;
    }
    final selectedMode = await repositories.settings.getValue(
      'selected_user_mode',
    );
    final hadAuthenticatedMode =
        _offlineAuthenticatedUserId != null ||
        cloudDataSource.currentIdentity != null ||
        selectedMode == 'account';
    await repositories.settings.remove('offline_authenticated_principal');
    if (hadAuthenticatedMode) {
      await repositories.settings.setValue('selected_user_mode', 'welcome');
      _guestModeSelected = false;
    }
    if (_offlineAuthenticatedUserId == null) return;
    _offlineAuthenticatedUserId = null;
    if (cloudDataSource.currentIdentity != null) return;
    _ownerScopeChanges.add(null);
    _localAuthChanges.add(null);
  }

  void _handleInternetSimulatorChanged() {
    if (!internetSimulator.internetAvailable || _disposed) return;
    unawaited(_resumeOnlineAuth());
  }

  Future<void> _resumeOnlineAuth() async {
    final pending = _onlineAuthResume;
    if (pending != null) return pending;
    final operation = _performOnlineAuthResume();
    _onlineAuthResume = operation;
    try {
      await operation;
    } finally {
      if (identical(_onlineAuthResume, operation)) _onlineAuthResume = null;
    }
  }

  Future<void> _performOnlineAuthResume() async {
    if (!_authInitialized) await initializeAuth();
    if (_disposed || !internetSimulator.internetAvailable) return;
    try {
      await cloudDataSource.initialize();
      final restored = await authService.restoreSession();
      if (restored == null) await _clearOfflineAuthenticatedPrincipal();
      if (restored != null) unawaited(syncEngine.run());
      if (_guestModeSelected) await _maybeStartGuestCloudBackup();
    } on Object catch (error) {
      if (_isTerminalAuthRestoreFailure(error)) {
        await _clearOfflineAuthenticatedPrincipal();
      } else if (_isTransientAuthRestoreFailure(error)) {
        await _restoreOfflineAuthenticatedPrincipal();
        _authRestoreTransientFailure = true;
      }
    }
  }

  bool _isTransientAuthRestoreFailure(Object error) =>
      error is TimeoutException ||
      error is SocketException ||
      (error is CloudException &&
          const {
            'offline',
            'network',
            'timeout',
            'server',
            'rateLimit',
            'initialization',
          }.contains(error.code));

  bool _isTerminalAuthRestoreFailure(Object error) =>
      error is CloudException &&
      const {'sessionExpired', 'auth', 'unauthenticated'}.contains(error.code);

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
      await _restoreGuestExitHold();
      await featureFlags.initialize();
      await _restoreInternetSimulator();
      final runtime = await connectivityStatus.readRuntimeSnapshot().timeout(
        const Duration(seconds: 2),
      );
      if (!internetSimulator.internetAvailable ||
          runtime.hasInternetRoute == false ||
          runtime.internetValidated == false) {
        final seedReady = _localSeedReady;
        if (seedReady != null) await seedReady.future;
        await _restoreOfflineAuthenticatedPrincipal();
        return;
      }
      await cloudDataSource.initialize();
      final restored = await authService.restoreSession();
      if (restored == null) await _clearOfflineAuthenticatedPrincipal();
      _authRestoreTransientFailure = false;
      unawaited(syncPushRegistration());
    } on Object catch (error) {
      if (_isTransientAuthRestoreFailure(error)) {
        _authRestoreTransientFailure = true;
        await _restoreOfflineAuthenticatedPrincipal();
      } else if (_isTerminalAuthRestoreFailure(error)) {
        await _clearOfflineAuthenticatedPrincipal();
      }
    } finally {
      _authInitialized = true;
      if (_guestModeSelected && internetSimulator.internetAvailable) {
        unawaited(_maybeStartGuestCloudBackup());
      }
    }
  }

  Future<void> initialize() {
    if (_initialization != null) return _initialization!;
    _localSeedReady ??= Completer<void>();
    return _initialization = _initialize();
  }

  Future<bool> syncPushRegistration() async {
    if (!RelioBuildInfo.isTest ||
        cloudDataSource.currentIdentity == null ||
        isGuestCloudSession ||
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
    if (!RelioBuildInfo.isTest ||
        cloudDataSource.currentIdentity == null ||
        isGuestCloudSession) {
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

  Future<bool> startNearbySessionIfPermitted({bool force = false}) async {
    if (_disposed || !nearbyService.initialized) return false;
    await _restoreGuestExitHold();
    if (_guestModeExited && !hasAuthenticatedPrincipal) return false;
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
    if (foreground) {
      unawaited(
        emergencyRuntimeService
            .isRunning()
            .then((running) {
              _emergencyRuntimeActive = running;
              if (running) unawaited(startNearbySessionIfPermitted());
            })
            .catchError((Object _) {
              _emergencyRuntimeActive = false;
            }),
      );
    }
    final changed = _nearbyForeground != foreground;
    if (changed && foreground) _nearbyRestart = true;
    _nearbyForeground = foreground;
    if (changed) {
      diagnostics.record(
        'lifecycle',
        foreground ? 'APP_FOREGROUND' : 'APP_BACKGROUND',
        operation: 'setNearbyForeground',
        fields: {
          'appLifecycleState': nearbyService.appLifecycleState,
          'nearbyConnected': nearbyService.connectedPeers.isNotEmpty,
        },
      );
      if (foreground) {
        unawaited(
          nearbyService.locationCoordinator?.onPermissionOrReadinessChanged(),
        );
      }
    }
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
          (!_nearbyForeground && !_emergencyRuntimeActive) ||
          !nearbyService.isAdvertising ||
          !nearbyService.isDiscovering ||
          (_nearbyRestart && !(_nearbyForeground && ready));
      if (mustDefer) {
        if (!_nearbySessionSyncDeferred) {
          diagnostics.record(
            !ready || (!_nearbyForeground && !_emergencyRuntimeActive)
                ? 'lifecycle'
                : 'nearby',
            !ready || (!_nearbyForeground && !_emergencyRuntimeActive)
                ? 'session_stop_deferred_active_connection'
                : 'session_restart_deferred_active_connection',
            operation: 'RelioDependencies._syncNearbySession',
            fields: {
              'activeConnectionAttempts':
                  nearbyService.activeConnectionAttempts,
              'ready': ready,
              'foreground': _nearbyForeground,
              'emergencyRuntimeActive': _emergencyRuntimeActive,
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
    if (!ready || (!_nearbyForeground && !_emergencyRuntimeActive)) {
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
    if (!_nearbyForeground &&
        _emergencyRuntimeActive &&
        nearbyService.isAdvertising &&
        nearbyService.isDiscovering) {
      _nearbyRestart = false;
      return true;
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
        if (!_disposed && (_nearbyForeground || _emergencyRuntimeActive)) {
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
    try {
      await internalExperience.initialize();
      await featureFlags.initialize();
      await _restoreInternetSimulator();
      await _restoreGuestExitHold();
      unawaited(diagnostics.initialize());
      if (RelioBuildInfo.isTest && _isAndroid && !useMockTransport) {
        unawaited(_recordDuplicateConversationMetadata());
      }
      if (RelioBuildInfo.isTest) {
        _qaTextForwardingPaused = await repositories.settings.getBool(
          'qa_text_forwarding_paused',
          defaultValue: false,
        );
      }
      _readinessSubscription = connectivityStatus.changes.listen((_) {
        if (_isAndroid && !useMockTransport) {
          unawaited(startNearbySessionIfPermitted());
        }
        unawaited(_resumeOnlineAuth());
        unawaited(syncEngine.run());
      });
      unawaited(connectivityStatus.initialize());
      await identity.getDeviceId();
      await identity.getDisplayName();
    } finally {
      final seedReady = _localSeedReady;
      if (seedReady != null && !seedReady.isCompleted) seedReady.complete();
    }
    await nearbyService.initialize();
    nearbyService.addListener(_onNearbyServiceChanged);
    _nearbyServiceListenerAttached = true;
    await _watchLocalSosForLocationCadence();
    await _restoreEmergencyRuntimeFromLocalState();
    if (_isAndroid && !useMockTransport) {
      await startNearbySessionIfPermitted();
      // ตรวจซ้ำเฉพาะ foreground เพื่อจับสิทธิ์/GMS ที่ไม่ส่ง radio broadcast
      _nearbyHealthCheck = Timer.periodic(const Duration(seconds: 60), (_) {
        if (_nearbyForeground || _emergencyRuntimeActive) {
          unawaited(startNearbySessionIfPermitted());
        }
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

  Future<void> _recordDuplicateConversationMetadata() async {
    try {
      final rows = await database.customSelect('''
        SELECT c.id AS cid, c.display_name AS name,
          c.participant_id AS device, cp.local_principal AS local,
          cp.remote_principal AS remote, cp.remote_device_id AS remote_device,
          cp.state AS principal_state, cs.owner_user_id AS scope,
          (SELECT COUNT(*) FROM messages m WHERE m.conversation_id=c.id)
            AS message_count
        FROM conversations c
        LEFT JOIN conversation_principals cp ON cp.conversation_id=c.id
        LEFT JOIN conversation_scopes cs ON cs.conversation_id=c.id
        WHERE c.display_name IN (
          SELECT display_name FROM conversations
          GROUP BY display_name HAVING COUNT(*)>1
        )
        ORDER BY c.display_name, c.created_at LIMIT 30
      ''').get();
      String alias(Object? value) => value is String && value.isNotEmpty
          ? DiagnosticsLogService.peerAlias(value)
          : 'none';
      diagnostics.record(
        'identity',
        'duplicate_conversation_audit',
        fields: {'rowCount': rows.length},
      );
      for (final row in rows) {
        final data = row.data;
        diagnostics.record(
          'identity',
          'duplicate_conversation_metadata',
          fields: {
            'nameAlias': alias(data['name']),
            'conversationAlias': alias(data['cid']),
            'deviceAlias': alias(data['device']),
            'localAlias': alias(data['local']),
            'remoteAlias': alias(data['remote']),
            'remoteDeviceAlias': alias(data['remote_device']),
            'scopeAlias': alias(data['scope']),
            'principalState': data['principal_state'] ?? 'none',
            'messageCount': data['message_count'] ?? 0,
          },
        );
      }
    } on Object {
      diagnostics.record('identity', 'duplicate_conversation_audit_failed');
    }
  }

  Future<void> _watchLocalSosForLocationCadence() async {
    final deviceId = await identity.getDeviceId();
    final active = await repositories.sos.readActive(ownerDeviceId: deviceId);
    await nearbyService.setLocalSosActive(active != null);
    _localSosLocationSubscription = repositories.sos
        .watchActive(ownerDeviceId: deviceId)
        .listen((event) {
          unawaited(nearbyService.setLocalSosActive(event != null));
        });
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
    internetSimulator.removeListener(_handleInternetSimulatorChanged);
    await _cloudAuthSubscription.cancel();
    _nearbyHealthCheck?.cancel();
    _nearbyRetryTimer?.cancel();
    _backgroundNegotiationGraceTimer?.cancel();
    if (_nearbyServiceListenerAttached) {
      nearbyService.removeListener(_onNearbyServiceChanged);
    }
    await _readinessSubscription?.cancel();
    await _localSosLocationSubscription?.cancel();
    await _nearbySyncOperation;
    await connectivityStatus.dispose();
    internetSimulator.dispose();
    await relayEngine.dispose();
    await nearbyService.close();
    await syncEngine.dispose();
    appUpdateService.dispose();
    await cloudDataSource.dispose();
    await _ownerScopeChanges.close();
    await _localAuthChanges.close();
    featureFlags.dispose();
    internalExperience.dispose();
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
