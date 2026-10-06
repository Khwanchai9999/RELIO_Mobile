// contains enums and typedefs

// ignore_for_file: constant_identifier_names

import 'package:nearby_connections/src/classes.dart';

/// **P2P_CLUSTER** - best for small payloads and multiplayer games
///
/// **P2P_STAR** - best for medium payloads, higher bandwidth than cluster
///
/// **P2P_POINT_TO_POINT** - single connection, very high bandwidth
enum Strategy { P2P_CLUSTER, P2P_STAR, P2P_POINT_TO_POINT }

enum Status { CONNECTED, REJECTED, ERROR }

enum PayloadStatus { NONE, SUCCESS, FAILURE, IN_PROGRESS, CANCELED }

enum PayloadType { NONE, BYTES, FILE, STREAM }

//
//
//
// Advertising lifecycle callbacks
//
typedef OnConnectionInitiated = void Function(
    String endpointId, ConnectionInfo connectionInfo);
typedef OnConnectionResult = void Function(String endpointId, Status status);
typedef OnRawConnectionResult = void Function(
    String endpointId, NativeConnectionResult result);
typedef OnNativeDiagnosticEvent = void Function(NativeDiagnosticEvent event);
typedef OnDisconnected = void Function(String endpointId);

class NativeConnectionResult {
  factory NativeConnectionResult.fromEventMap(Map<dynamic, dynamic> args) {
    final rawCode = args['rawStatusCode'];
    final code = rawCode is int
        ? rawCode
        : args['statusCode'] is int
            ? args['statusCode'] as int
            : -1;
    final receivedName = args['rawStatusName'];
    final name = receivedName is String && receivedName.isNotEmpty
        ? receivedName
        : 'UNKNOWN_STATUS_$code';
    return NativeConnectionResult(
      rawStatusCode: code,
      rawStatusName: name,
      rawStatusMessage: args['rawStatusMessage'] as String?,
      operation: args['operation'] as String?,
      role: args['role'] as String?,
      elapsedMs: args['elapsedMs'] as int?,
      strategy: args['strategy'] as String?,
      connectionTraceId:
          (args['connectionTraceId'] ?? args['traceId']) as String?,
      androidApi: args['androidApi'] as int?,
      googlePlayServicesVersionName:
          args['googlePlayServicesVersionName'] as String?,
      googlePlayServicesVersionCode:
          args['googlePlayServicesVersionCode'] as int?,
      nearbyLibraryVersion: args['nearbyLibraryVersion'] as String?,
      playServicesNearbyDependencyVersion:
          args['playServicesNearbyDependencyVersion'] as String?,
    );
  }

  const NativeConnectionResult({
    required this.rawStatusCode,
    required this.rawStatusName,
    this.rawStatusMessage,
    this.operation,
    this.role,
    this.elapsedMs,
    this.strategy,
    this.connectionTraceId,
    this.androidApi,
    this.googlePlayServicesVersionName,
    this.googlePlayServicesVersionCode,
    this.nearbyLibraryVersion,
    this.playServicesNearbyDependencyVersion,
  });

  final int rawStatusCode;
  final String rawStatusName;
  final String? rawStatusMessage;
  final String? operation;
  final String? role;
  final int? elapsedMs;
  final String? strategy;
  final String? connectionTraceId;
  final int? androidApi;
  final String? googlePlayServicesVersionName;
  final int? googlePlayServicesVersionCode;
  final String? nearbyLibraryVersion;
  final String? playServicesNearbyDependencyVersion;
}

class NativeDiagnosticEvent {
  const NativeDiagnosticEvent({required this.name, required this.fields});

  final String name;
  final Map<Object?, Object?> fields;
}

//
//
//
// Discovery lifecycle callbacks
//
typedef OnEndpointFound = void Function(
    String endpointId, String endpointName, String serviceId);
typedef OnEndpointLost = void Function(String? endpointId);

//
//
//
/// For Bytes, this contains the bytes data
///
/// For File, this marks the start of transfer
///
/// Uint8List bytes may be null, if [type] is not [PayloadType.BYTES]
typedef OnPayloadReceived = void Function(String endpointId, Payload payload);

/// Called only once for Bytes and repeatedly for File until transfer is complete
typedef OnPayloadTransferUpdate = void Function(
    String endpointId, PayloadTransferUpdate payloadTransferUpdate);
