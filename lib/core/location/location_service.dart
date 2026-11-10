import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/relio_entities.dart';
import 'nearby_location_quality.dart';

enum LocationFailure {
  permissionDenied,
  permissionDeniedForever,
  approximatePermission,
  serviceDisabled,
  timeout,
  staleFix,
  invalidFix,
  unavailable,
}

enum LocationPermissionState { denied, deniedForever, whileInUse, always }

enum LocationPrecisionState { precise, approximate, unknown }

class LocationResult {
  const LocationResult.success(this.location) : failure = null, message = null;
  const LocationResult.failure(this.failure, {this.message}) : location = null;

  final LocationData? location;
  final LocationFailure? failure;
  final String? message;

  bool get isSuccess => location != null;
}

abstract interface class LocationPlatform {
  Future<bool> isServiceEnabled();
  Future<LocationPermissionState> checkPermission();
  Future<LocationPrecisionState> getPrecision();
  Future<LocationPermissionState> requestPermission();
  Future<LocationData> getCurrent({required Duration timeout});
  Stream<LocationData> watchPositions({required Duration interval});
  Future<LocationData?> getLastKnown();
  Future<bool> openAppSettings();
}

class LocationStreamException implements Exception {
  const LocationStreamException(this.failure);

  final LocationFailure failure;
}

// สัญญากลางสำหรับการขอตำแหน่งและ stream จากแพลตฟอร์ม
// แยกข้อมูลตำแหน่งที่ขอโดยผู้ใช้ออกจาก cache และห้ามสร้างประวัติเบื้องหลัง
abstract interface class LocationService {
  /// Requests one fresh foreground fix without prompting or tracking in background.
  Future<LocationResult> getFreshLocation({
    Duration timeout = const Duration(seconds: 25),
  });

  Future<LocationResult> getCurrentIfPermitted({
    Duration timeout = const Duration(seconds: 25),
  });

  Future<LocationResult> getCurrentOrLastKnown({
    Duration timeout = const Duration(seconds: 5),
  });

  /// Opens one foreground stream after checking existing permission; it never
  /// prompts for permission or enables background location.
  Future<Stream<LocationData>> watchPositions({required Duration interval});

  /// Reads a recent cached fix for local map display only. It never requests a
  /// fresh fix or sends the result to Nearby peers.
  Future<LocationData?> getRecentLastKnownForDisplay({
    Duration maxAge = NearbyLocationQuality.maxLocalDisplayAge,
  });

  Future<bool> openAppSettings();
}

class GeolocatorLocationService implements LocationService {
  GeolocatorLocationService({LocationPlatform? platform})
    : _platform = platform ?? const _GeolocatorLocationPlatform();

  final LocationPlatform _platform;

  @override
  Future<bool> openAppSettings() => _platform.openAppSettings();

  @override
  Future<LocationResult> getFreshLocation({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    try {
      if (!await _platform.isServiceEnabled()) {
        return const LocationResult.failure(LocationFailure.serviceDisabled);
      }
      final permission = await _platform.checkPermission();
      if (permission != LocationPermissionState.whileInUse &&
          permission != LocationPermissionState.always) {
        return LocationResult.failure(
          permission == LocationPermissionState.deniedForever
              ? LocationFailure.permissionDeniedForever
              : LocationFailure.permissionDenied,
        );
      }
      if (await _platform.getPrecision() ==
          LocationPrecisionState.approximate) {
        return const LocationResult.failure(
          LocationFailure.approximatePermission,
        );
      }

      final location = await _platform.getCurrent(timeout: timeout);
      if (!NearbyLocationQuality.isEligibleForCurrentSharing(
        location,
        now: DateTime.now(),
      )) {
        return const LocationResult.failure(LocationFailure.staleFix);
      }
      return LocationResult.success(location);
    } on TimeoutException {
      return const LocationResult.failure(LocationFailure.timeout);
    } on Object catch (error) {
      return LocationResult.failure(
        LocationFailure.unavailable,
        message: '$error',
      );
    }
  }

  @override
  Future<LocationResult> getCurrentIfPermitted({
    Duration timeout = const Duration(seconds: 25),
  }) => getFreshLocation(timeout: timeout);

  @override
  Future<LocationResult> getCurrentOrLastKnown({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // คง fallback เดิมให้ SOS/Chat ส่วน Nearby ใช้ getFreshLocation เพื่อขอค่าที่สดกว่า    // Keep the legacy fallback for SOS/chat callers; Nearby uses getFreshLocation.
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult.failure(LocationFailure.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const LocationResult.failure(LocationFailure.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationResult.failure(
        LocationFailure.permissionDeniedForever,
      );
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(timeout);
      return LocationResult.success(_map(position, source: 'current'));
    } on TimeoutException {
      final fallback = await _lastKnown();
      return fallback ?? const LocationResult.failure(LocationFailure.timeout);
    } on Object catch (error) {
      final fallback = await _lastKnown();
      return fallback ??
          LocationResult.failure(
            LocationFailure.unavailable,
            message: '$error',
          );
    }
  }

  @override
  Future<Stream<LocationData>> watchPositions({
    required Duration interval,
  }) async {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval');
    }
    if (!await _platform.isServiceEnabled()) {
      throw const LocationStreamException(LocationFailure.serviceDisabled);
    }
    final permission = await _platform.checkPermission();
    if (permission != LocationPermissionState.whileInUse &&
        permission != LocationPermissionState.always) {
      throw LocationStreamException(
        permission == LocationPermissionState.deniedForever
            ? LocationFailure.permissionDeniedForever
            : LocationFailure.permissionDenied,
      );
    }
    if (await _platform.getPrecision() == LocationPrecisionState.approximate) {
      throw const LocationStreamException(
        LocationFailure.approximatePermission,
      );
    }
    return _platform.watchPositions(interval: interval);
  }

  @override
  Future<LocationData?> getRecentLastKnownForDisplay({
    Duration maxAge = NearbyLocationQuality.maxLocalDisplayAge,
  }) async {
    try {
      if (!await _platform.isServiceEnabled()) return null;
      final permission = await _platform.checkPermission();
      if (permission != LocationPermissionState.whileInUse &&
          permission != LocationPermissionState.always) {
        return null;
      }
      final location = await _platform.getLastKnown();
      if (location == null ||
          !NearbyLocationQuality.isEligibleForLocalDisplay(
            location,
            now: DateTime.now(),
            maxAge: maxAge,
          )) {
        return null;
      }
      return location;
    } on Object {
      // ความล้มเหลวของตำแหน่งที่ cache ไว้ต้องไม่ขวางการเริ่ม Nearby      // Cached-location failure must not block Nearby startup.
      return null;
    }
  }

  Future<LocationResult?> _lastKnown() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      return position == null
          ? null
          : LocationResult.success(_map(position, source: 'lastKnown'));
    } on Object {
      return null;
    }
  }

  static LocationData _map(Position position, {required String source}) =>
      LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy.isFinite ? position.accuracy : null,
        capturedAt: position.timestamp,
        source: source,
      );
}

class _GeolocatorLocationPlatform implements LocationPlatform {
  const _GeolocatorLocationPlatform();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermissionState> checkPermission() async =>
      _mapPermission(await Geolocator.checkPermission());

  @override
  Future<LocationPrecisionState> getPrecision() async {
    final status = await Geolocator.getLocationAccuracy();
    return switch (status) {
      LocationAccuracyStatus.precise => LocationPrecisionState.precise,
      LocationAccuracyStatus.reduced => LocationPrecisionState.approximate,
      LocationAccuracyStatus.unknown => LocationPrecisionState.unknown,
    };
  }

  @override
  Future<LocationPermissionState> requestPermission() async =>
      _mapPermission(await Geolocator.requestPermission());

  @override
  Future<LocationData> getCurrent({required Duration timeout}) async {
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            intervalDuration: const Duration(seconds: 1),
            timeLimit: timeout,
          )
        : LocationSettings(accuracy: LocationAccuracy.best, timeLimit: timeout);
    final position = await Geolocator.getCurrentPosition(
      locationSettings: settings,
    );
    return GeolocatorLocationService._map(position, source: 'current');
  }

  @override
  Stream<LocationData> watchPositions({required Duration interval}) {
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            intervalDuration: interval,
            distanceFilter: 0,
          )
        : LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0);
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (position) => GeolocatorLocationService._map(position, source: 'live'),
    );
  }

  @override
  Future<LocationData?> getLastKnown() async {
    final position = await Geolocator.getLastKnownPosition();
    return position == null
        ? null
        : GeolocatorLocationService._map(position, source: 'lastKnown');
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}

LocationPermissionState _mapPermission(LocationPermission permission) =>
    switch (permission) {
      LocationPermission.denied => LocationPermissionState.denied,
      LocationPermission.deniedForever => LocationPermissionState.deniedForever,
      LocationPermission.whileInUse => LocationPermissionState.whileInUse,
      LocationPermission.always => LocationPermissionState.always,
      LocationPermission.unableToDetermine => LocationPermissionState.denied,
    };

class FakeLocationService implements LocationService {
  FakeLocationService(this.result, {LocationResult? lastKnown})
    : lastKnownResult = lastKnown ?? result;

  LocationResult result;
  LocationResult lastKnownResult;
  bool openedSettings = false;
  int freshLocationCalls = 0;
  int positionStreamRequests = 0;
  Duration? requestedPositionInterval;
  final StreamController<LocationData> _positionEvents =
      StreamController<LocationData>.broadcast();

  void emitPosition(LocationData location) => _positionEvents.add(location);
  void emitError(Object error) => _positionEvents.addError(error);

  @override
  Future<bool> openAppSettings() async {
    openedSettings = true;
    return true;
  }

  @override
  Future<LocationResult> getFreshLocation({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    freshLocationCalls += 1;
    return lastKnownResult;
  }

  @override
  Future<LocationResult> getCurrentIfPermitted({
    Duration timeout = const Duration(seconds: 25),
  }) async => lastKnownResult;

  @override
  Future<LocationResult> getCurrentOrLastKnown({
    Duration timeout = const Duration(seconds: 5),
  }) async => result;

  @override
  Future<Stream<LocationData>> watchPositions({
    required Duration interval,
  }) async {
    positionStreamRequests++;
    requestedPositionInterval = interval;
    final failure = lastKnownResult.failure;
    if (failure != null) throw LocationStreamException(failure);
    final initial = lastKnownResult.location;
    return Stream<LocationData>.multi((controller) {
      if (initial != null) controller.add(initial);
      final subscription = _positionEvents.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<LocationData?> getRecentLastKnownForDisplay({
    Duration maxAge = NearbyLocationQuality.maxLocalDisplayAge,
  }) async {
    final location = lastKnownResult.location;
    if (location == null ||
        !NearbyLocationQuality.isEligibleForLocalDisplay(
          location,
          now: DateTime.now(),
          maxAge: maxAge,
        )) {
      return null;
    }
    return location;
  }
}

class TestLocationPlatform implements LocationPlatform {
  bool serviceEnabled = true;
  LocationPermissionState permission = LocationPermissionState.whileInUse;
  LocationPrecisionState precision = LocationPrecisionState.precise;
  LocationData? fix;
  LocationData? lastKnown;
  Object? error;
  bool settingsOpened = false;
  int requests = 0;
  int permissionRequests = 0;
  Duration? requestedPositionInterval;
  final StreamController<LocationData> positionEvents =
      StreamController<LocationData>.broadcast();

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionState> checkPermission() async => permission;

  @override
  Future<LocationPrecisionState> getPrecision() async => precision;

  @override
  Future<LocationPermissionState> requestPermission() async {
    permissionRequests += 1;
    return permission;
  }

  @override
  Future<LocationData?> getLastKnown() async => lastKnown;

  @override
  Future<LocationData> getCurrent({required Duration timeout}) async {
    requests += 1;
    final failure = error;
    if (failure != null) throw failure;
    final result = fix;
    if (result == null) throw TimeoutException('No fresh position.');
    return result;
  }

  @override
  Stream<LocationData> watchPositions({required Duration interval}) {
    requestedPositionInterval = interval;
    return positionEvents.stream;
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened = true;
    return true;
  }
}
