import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_connections/nearby_connections.dart';

void main() {
  test('native connection status preserves exact Google result and trace', () {
    final result = NativeConnectionResult.fromEventMap({
      'rawStatusCode': 8007,
      'rawStatusName': 'STATUS_RADIO_ERROR',
      'rawStatusMessage': 'native radio status detail',
      'operation': 'acceptConnection',
      'role': 'responder',
      'elapsedMs': 29123,
      'strategy': 'P2P_CLUSTER',
      'endpointAlias': 'endpoint-abc123',
      'connectionTraceId': 'trace-123',
      'androidApi': 35,
      'googlePlayServicesVersionName': '25.40.34',
      'googlePlayServicesVersionCode': 254034000,
      'nearbyLibraryVersion': '4.3.0',
      'playServicesNearbyDependencyVersion': '19.2.0',
      'statusCode': Status.ERROR.index,
    });

    expect(result.rawStatusCode, 8007);
    expect(result.rawStatusName, 'STATUS_RADIO_ERROR');
    expect(result.rawStatusMessage, 'native radio status detail');
    expect(result.operation, 'acceptConnection');
    expect(result.role, 'responder');
    expect(result.elapsedMs, 29123);
    expect(result.strategy, 'P2P_CLUSTER');
    expect(result.connectionTraceId, 'trace-123');
    expect(result.androidApi, 35);
    expect(result.googlePlayServicesVersionCode, 254034000);
    expect(result.nearbyLibraryVersion, '4.3.0');
    expect(result.playServicesNearbyDependencyVersion, '19.2.0');
  });

  test(
    'unknown native status retains its numeric code and stable fallback',
    () {
      final result = NativeConnectionResult.fromEventMap({
        'rawStatusCode': 987654,
        'statusCode': Status.ERROR.index,
      });

      expect(result.rawStatusCode, 987654);
      expect(result.rawStatusName, 'UNKNOWN_STATUS_987654');
    },
  );
}
