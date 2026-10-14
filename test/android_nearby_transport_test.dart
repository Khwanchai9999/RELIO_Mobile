import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:relio_mobile/core/nearby/android_nearby_transport.dart';
import 'package:relio_mobile/core/nearby/bluetooth_classic_transport.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nearby_connections');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'QA compatibility wrapper forwards idle reset to native primary',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      final NearbyTransport transport = CompatibilityNearbyTransport(
        primary: AndroidNearbyTransport(),
        compatibility: MockNearbyTransport(),
      );
      addTearDown(transport.dispose);
      await transport.startAdvertising(displayName: 'RELIO');
      await transport.startDiscovery();
      await transport.stopDiscovery();
      await transport.stopAdvertising();
      expect(transport, isA<NearbyIdleSessionRecovery>());
      await (transport as NearbyIdleSessionRecovery).clearIdleEndpoints();
      expect(
        calls.where((method) => method == 'stopAllEndpoints'),
        hasLength(1),
      );
    },
  );

  test(
    'idle recovery clears all native endpoint traces before restarting',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      final transport = AndroidNearbyTransport();
      addTearDown(transport.dispose);
      await transport.startAdvertising(displayName: 'RELIO');
      await transport.startDiscovery();
      await expectLater(transport.clearIdleEndpoints(), throwsStateError);
      await transport.requestConnection('peer');
      await transport.stopDiscovery();
      await transport.stopAdvertising();
      await expectLater(transport.clearIdleEndpoints(), throwsStateError);
      expect(calls.where((method) => method == 'stopAllEndpoints'), isEmpty);
      await transport.disconnect('peer');
      await transport.clearIdleEndpoints();
      await transport.startAdvertising(displayName: 'RELIO');
      await transport.startDiscovery();
      final clearIndex = calls.indexOf('stopAllEndpoints');
      expect(clearIndex, greaterThan(calls.indexOf('disconnectFromEndpoint')));
      expect(calls.lastIndexOf('startAdvertising'), greaterThan(clearIndex));
      expect(calls.lastIndexOf('startDiscovery'), greaterThan(clearIndex));
    },
  );

  for (final local in [true, false]) {
    test(
      'native pending request is released after ${local ? 'local' : 'remote'} disconnect',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
        final transport = AndroidNearbyTransport();
        addTearDown(transport.dispose);
        await transport.startAdvertising(displayName: 'RELIO');
        await transport.requestConnection('peer');
        await nativeEvent({
          'method': 'dis.onConnectionInitiated',
          'endpointId': 'peer',
          'endpointName': 'RELIO peer',
          'authenticationToken': 'QA',
          'isIncomingConnection': false,
        });
        if (local) {
          await transport.disconnect('peer');
        } else {
          await nativeEvent({
            'method': 'dis.onDisconnected',
            'endpointId': 'peer',
          });
        }
        await transport.acceptConnection('peer');
        expect(
          calls.where((call) => call.method == 'acceptConnection'),
          isEmpty,
        );
        await transport.requestConnection('peer');
        expect(
          calls.where((call) => call.method == 'requestConnection'),
          hasLength(2),
        );
        await nativeEvent({
          'method': 'dis.onConnectionInitiated',
          'endpointId': 'peer',
          'endpointName': 'RELIO peer',
          'authenticationToken': 'QA',
          'isIncomingConnection': false,
        });
        await transport.acceptConnection('peer');
        expect(
          calls.where((call) => call.method == 'acceptConnection'),
          hasLength(1),
        );
      },
    );
  }

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

  for (final successFirst in [false, true]) {
    test(
      'incoming URI file copies only after SUCCESS, successFirst=$successFirst',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'relio-native-file-',
        );
        addTearDown(() => root.delete(recursive: true));
        const paths = MethodChannel('plugins.flutter.io/path_provider');
        messenger.setMockMethodCallHandler(paths, (_) async => root.path);
        addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
        var copies = 0;
        final completeBytes = List<int>.generate(14679, (i) => i % 256);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'copyFileAndDeleteOriginal') {
            copies++;
            await File(
              call.arguments['destinationFilepath'] as String,
            ).writeAsBytes(completeBytes);
          }
          return true;
        });
        final transport = await receivingTransport();
        addTearDown(transport.dispose);
        final files = <NearbyFilePayloadEvent>[];
        final subscription = transport.incomingFilePayloads.listen(files.add);
        addTearDown(subscription.cancel);
        final file = {
          'method': 'onPayloadReceived',
          'endpointId': 'peer',
          'payloadId': 91,
          'type': PayloadType.FILE.index,
          'uri': 'content://qa/video',
        };
        final success = {
          'method': 'onPayloadTransferUpdate',
          'endpointId': 'peer',
          'payloadId': 91,
          'status': PayloadStatus.SUCCESS.index,
          'bytesTransferred': 14679,
          'totalBytes': 14679,
        };
        if (successFirst) {
          await nativeEvent(success);
          expect(copies, 0);
          await nativeEvent(file);
        } else {
          await nativeEvent(file);
          await nativeEvent({
            ...success,
            'status': PayloadStatus.IN_PROGRESS.index,
            'bytesTransferred': 3960,
          });
          expect(
            copies,
            0,
            reason:
                'The Samsung failure copied 3960 of 14679 bytes before completion',
          );
          expect(files, isEmpty);
          await nativeEvent(success);
        }
        await waitForNativeFile(() => files.length == 1);
        expect(await File(files.single.filePath).readAsBytes(), completeBytes);
        await nativeEvent(file);
        await nativeEvent(success);
        expect(copies, 1);
        expect(files, hasLength(1));
      },
    );
  }

  test(
    'incoming direct path is not exposed before file transfer SUCCESS',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => true);
      final transport = await receivingTransport();
      addTearDown(transport.dispose);
      final files = <NearbyFilePayloadEvent>[];
      final subscription = transport.incomingFilePayloads.listen(files.add);
      addTearDown(subscription.cancel);
      await nativeEvent({
        'method': 'onPayloadReceived',
        'endpointId': 'peer',
        'payloadId': 92,
        'type': PayloadType.FILE.index,
        'filePath': '/qa/partial.mp4',
      });
      expect(files, isEmpty);
      await nativeEvent({
        'method': 'onPayloadTransferUpdate',
        'endpointId': 'peer',
        'payloadId': 92,
        'status': PayloadStatus.SUCCESS.index,
      });
      expect(files.single.filePath, '/qa/partial.mp4');
    },
  );

  test(
    'failed native file never copies or emits even after a duplicate callback',
    () async {
      var copies = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'copyFileAndDeleteOriginal') copies++;
        return true;
      });
      final transport = await receivingTransport();
      addTearDown(transport.dispose);
      final files = <NearbyFilePayloadEvent>[];
      final subscription = transport.incomingFilePayloads.listen(files.add);
      addTearDown(subscription.cancel);
      final file = {
        'method': 'onPayloadReceived',
        'endpointId': 'peer',
        'payloadId': 93,
        'type': PayloadType.FILE.index,
        'uri': 'content://qa/failed',
      };
      await nativeEvent(file);
      await nativeEvent({
        'method': 'onPayloadTransferUpdate',
        'endpointId': 'peer',
        'payloadId': 93,
        'status': PayloadStatus.FAILURE.index,
      });
      await nativeEvent(file);
      expect(copies, 0);
      expect(files, isEmpty);
    },
  );
}

Future<void> nativeEvent(Map<String, Object> event) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(
    'nearby_connections/events',
    const StandardMethodCodec().encodeSuccessEnvelope(event),
    (_) {},
  );
  await Future<void>.delayed(Duration.zero);
}

Future<AndroidNearbyTransport> receivingTransport() async {
  final transport = AndroidNearbyTransport();
  await transport.startAdvertising(displayName: 'RELIO QA');
  await nativeEvent({
    'method': 'ad.onConnectionInitiated',
    'endpointId': 'peer',
    'endpointName': 'RELIO QA peer',
    'authenticationToken': 'QA',
    'isIncomingConnection': true,
  });
  await transport.acceptConnection('peer');
  return transport;
}

Future<void> waitForNativeFile(bool Function() ready) async {
  for (var count = 0; count < 100 && !ready(); count++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue);
}
