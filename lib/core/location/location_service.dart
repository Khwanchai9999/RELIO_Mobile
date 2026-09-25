import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../domain/relio_entities.dart';

enum LocationFailure {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  timeout,
  unavailable,
}

class LocationResult {
  const LocationResult.success(this.location) : failure = null, message = null;
  const LocationResult.failure(this.failure, {this.message}) : location = null;

  final LocationData? location;
  final LocationFailure? failure;
  final String? message;

  bool get isSuccess => location != null;
}

abstract interface class LocationService {
  Future<LocationResult> getCurrentOrLastKnown({
    Duration timeout = const Duration(seconds: 5),
  });
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationResult> getCurrentOrLastKnown({
    Duration timeout = const Duration(seconds: 5),
  }) async {
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
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

  LocationData _map(Position position, {required String source}) =>
      LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy.isFinite ? position.accuracy : null,
        capturedAt: position.timestamp,
        source: source,
      );
}

class FakeLocationService implements LocationService {
  FakeLocationService(this.result);

  LocationResult result;

  @override
  Future<LocationResult> getCurrentOrLastKnown({
    Duration timeout = const Duration(seconds: 5),
  }) async => result;
}
