import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_service.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';

void main() {
  late AppDatabase database;
  late RelioRepositories repositories;
  late MockNearbyTransport transport;
  late NearbyService service;

  setUp(() async {
    database = AppDatabase.memory();
    repositories = RelioRepositories(database);
    transport = MockNearbyTransport();
    service = NearbyService(
      transport: transport,
      messages: repositories.messages,
      conversations: repositories.conversations,
      identity: RelioDeviceIdentityRepository(database),
      nearbyDevices: repositories.nearbyDevices,
    );
    await service.initialize();
    addTearDown(() async {
      await service.close();
      await database.close();
    });
  });

  test('duplicate in-flight session starts are single-flight', () async {
    transport.startDelay = const Duration(milliseconds: 30);

    await Future.wait([service.startSession(), service.startSession()]);

    expect(transport.advertisingStartCount, 1);
    expect(transport.discoveryStartCount, 1);
    expect(service.isAdvertising, isTrue);
    expect(service.isDiscovering, isTrue);
  });

  test(
    'false advertising result is preserved and discovery is skipped',
    () async {
      transport.advertisingStartFailure = const NearbyTransportException(
        'Android startAdvertising returned false.',
        code: 'start_returned_false',
        operation: 'startAdvertising',
        exceptionType: 'bool',
        returnedFalse: true,
      );

      await service.startSession();

      expect(transport.discoveryStartCount, 0);
      expect(service.lastDiagnostic, contains('exceptionType=bool'));
      expect(service.lastDiagnostic, contains('result=false'));
      expect(service.isAdvertising, isFalse);
    },
  );

  test('hung advertising does not block discovery startup', () async {
    transport.startDelay = const Duration(milliseconds: 40);
    await service.close();
    service = NearbyService(
      transport: transport,
      messages: repositories.messages,
      conversations: repositories.conversations,
      identity: RelioDeviceIdentityRepository(database),
      nearbyDevices: repositories.nearbyDevices,
      advertisingStartWatchdog: const Duration(milliseconds: 1),
    );
    await service.initialize();

    await service.startSession();

    expect(transport.discoveryStartCount, 1);
    expect(service.isDiscovering, isTrue);
  });

  test('already-advertising native status reconciles local state', () async {
    transport.advertisingStartFailure = const NearbyTransportException(
      'Already advertising',
      code: 'STATUS_ALREADY_ADVERTISING',
      apiStatusCode: 8001,
      apiStatusName: 'STATUS_ALREADY_ADVERTISING',
    );

    await service.startSession();

    expect(service.isAdvertising, isTrue);
    expect(service.isDiscovering, isTrue);
    expect(service.lastError, isNull);
  });

  test('already-discovering native status reconciles local state', () async {
    transport.discoveryStartFailure = const NearbyTransportException(
      'Already discovering',
      code: 'STATUS_ALREADY_DISCOVERING',
      apiStatusCode: 8002,
      apiStatusName: 'STATUS_ALREADY_DISCOVERING',
    );

    await service.startSession();

    expect(service.isAdvertising, isTrue);
    expect(service.isDiscovering, isTrue);
    expect(service.lastError, isNull);
  });

  test('out-of-order status stops only session operations for retry', () async {
    transport.advertisingStartFailure = const NearbyTransportException(
      'Out of order',
      code: 'STATUS_OUT_OF_ORDER_API_CALL',
      apiStatusCode: 8009,
      apiStatusName: 'STATUS_OUT_OF_ORDER_API_CALL',
    );

    await service.startSession();

    expect(transport.resetSessionOperationsCount, 1);
    expect(transport.isAdvertising, isFalse);
    expect(transport.isDiscovering, isFalse);
    expect(service.lastDiagnostic, contains('apiStatusCode=8009'));
  });

  test('radio error has a precise user-facing blocker', () async {
    transport.advertisingStartFailure = const NearbyTransportException(
      'Radio failure',
      code: 'STATUS_RADIO_ERROR',
      apiStatusCode: 8007,
      apiStatusName: 'STATUS_RADIO_ERROR',
    );

    await service.startSession();

    expect(service.statusLabel, contains('วิทยุ'));
    expect(service.lastErrorCode, '8007');
  });
}
