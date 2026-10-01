import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:relio_mobile/core/nearby/android_nearby_transport.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nearby_connections');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('false result remains distinct from PlatformException', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startAdvertising') return false;
      return null;
    });
    final transport = AndroidNearbyTransport();

    await expectLater(
      transport.startAdvertising(displayName: 'RELIO QA'),
      throwsA(
        isA<NearbyTransportException>()
            .having((error) => error.returnedFalse, 'false result', isTrue)
            .having((error) => error.exceptionType, 'type', 'bool')
            .having(
              (error) => error.platformCode,
              'PlatformException code',
              isNull,
            ),
      ),
    );
    await transport.dispose();
  });

  test('PlatformException and Nearby status are preserved exactly', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startAdvertising') {
        throw PlatformException(
          code: 'Failure',
          message: '8033: MISSING_PERMISSION_CHANGE_WIFI_STATE',
          details: {'native': 'missing permission'},
        );
      }
      return null;
    });
    final transport = AndroidNearbyTransport();

    await expectLater(
      transport.startAdvertising(displayName: 'RELIO QA'),
      throwsA(
        isA<NearbyTransportException>()
            .having((error) => error.operation, 'operation', 'startAdvertising')
            .having((error) => error.platformCode, 'platform code', 'Failure')
            .having((error) => error.apiStatusCode, 'Nearby status', 8033)
            .having(
              (error) => error.apiStatusName,
              'Nearby status name',
              'MISSING_PERMISSION_CHANGE_WIFI_STATE',
            )
            .having(
              (error) => error.platformMessage,
              'platform message',
              '8033: MISSING_PERMISSION_CHANGE_WIFI_STATE',
            )
            .having((error) => error.platformDetails, 'platform details', {
              'native': 'missing permission',
            }),
      ),
    );
    await transport.dispose();
  });

  test('false discovery result remains distinguishable', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startDiscovery') return false;
      return null;
    });
    final transport = AndroidNearbyTransport();

    await expectLater(
      transport.startDiscovery(),
      throwsA(
        isA<NearbyTransportException>()
            .having((error) => error.operation, 'operation', 'startDiscovery')
            .having((error) => error.returnedFalse, 'false result', isTrue),
      ),
    );
    await transport.dispose();
  });

  test('advertising and discovery share service ID and P2P_CLUSTER', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final transport = AndroidNearbyTransport();

    await transport.startAdvertising(displayName: 'RELIO QA');
    await transport.startDiscovery();

    final starts = calls.where(
      (call) =>
          call.method == 'startAdvertising' || call.method == 'startDiscovery',
    );
    expect(starts, hasLength(2));
    expect(starts.map((call) => call.arguments['serviceId']).toSet(), {
      relioNearbyServiceId,
    });
    expect(starts.map((call) => call.arguments['strategy']).toSet(), {
      Strategy.P2P_CLUSTER.index,
    });
    await transport.dispose();
  });
}
