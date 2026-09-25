import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'database/app_database.dart';
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

class RelioDependencies {
  RelioDependencies({
    AppDatabase? database,
    NearbyTransport? transport,
    bool? useMockTransport,
    LocationService? locationService,
    MediaStorageService? mediaStorage,
    CloudDataSource? cloudDataSource,
  }) : database = database ?? AppDatabase(),
       useMockTransport = useMockTransport ?? _defaultMockTransport,
       transport =
           transport ??
           ((useMockTransport ?? _defaultMockTransport)
               ? MockNearbyTransport(autoAcknowledge: true)
               : AndroidNearbyTransport()) {
    repositories = RelioRepositories(this.database);
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
    identity = RelioDeviceIdentityRepository(this.database);
    permissionService = PermissionService();
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
    );
  }

  final AppDatabase database;
  final NearbyTransport transport;
  final bool useMockTransport;
  late final RelioRepositories repositories;
  late final RelioDeviceIdentityRepository identity;
  late final PermissionService permissionService;
  late final LocationService locationService;
  late final MediaStorageService mediaStorageService;
  late final NearbyService nearbyService;
  late final CloudDataSource cloudDataSource;
  late final AuthService authService;
  Future<void>? _initialization;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await identity.getDeviceId();
    await identity.getDisplayName();
    await repositories.seedPrototypeData();
    try {
      await cloudDataSource.initialize();
      await authService.restoreSession();
    } on Object {
      // Cloud is an optional v0.5 destination. Local startup must remain
      // healthy when credentials are absent or the network is unavailable.
    }
    await nearbyService.initialize();
  }

  Future<void> dispose() async {
    await nearbyService.close();
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
