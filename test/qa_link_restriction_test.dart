import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';

import 'support/nearby_pair.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'QA direct-link restriction disconnects verified pair and can restore',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);

      await pair.serviceA.startAdvertising();
      await pair.serviceB.startAdvertising();
      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () =>
            pair.serviceA.peerStates['endpoint-b'] ==
                NearbyConnectionState.connected &&
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b',
      );

      await pair.serviceA.setQaDirectLinkRestriction('device-b');
      expect(pair.serviceA.qaRestrictedDeviceId, 'device-b');
      expect(pair.serviceA.diagnosticRole, NearbyDiagnosticRole.auto);
      await waitFor(
        () =>
            pair.serviceA.peerStates['endpoint-b'] ==
            NearbyConnectionState.disconnected,
      );

      pair.transportA.discoverPeer();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        pair.serviceA.peerStates['endpoint-b'],
        NearbyConnectionState.disconnected,
      );

      final discoveryStartsBeforeClear = pair.transportA.startDiscoveryCalls;
      await pair.serviceA.setQaDirectLinkRestriction(null);
      expect(pair.serviceA.qaRestrictedDeviceId, isNull);
      expect(
        pair.transportA.startDiscoveryCalls,
        greaterThan(discoveryStartsBeforeClear),
      );

      // A native endpointFound callback after the refreshed discovery epoch
      // must resume the verified saved-peer session without a manual Connect.
      pair.transportA.discoverPeer();
      pair.transportB.discoverPeer();
      await waitFor(
        () =>
            pair.serviceA.peerStates['endpoint-b'] ==
                NearbyConnectionState.connected &&
            pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b',
      );
      expect(
        pair.transportA.requestCalls + pair.transportB.requestCalls,
        greaterThan(1),
      );
    },
    skip: !RelioBuildInfo.isTest,
  );

  test(
    'QA restriction rejects empty identifiers without changing state',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);

      await expectLater(
        pair.serviceA.setQaDirectLinkRestriction(' '),
        throwsArgumentError,
      );
      expect(pair.serviceA.qaRestrictedDeviceId, isNull);
    },
    skip: !RelioBuildInfo.isTest,
  );

  test('non-TEST builds cannot activate the QA restriction', () async {
    final pair = await HandshakePair.create();
    addTearDown(pair.close);

    if (RelioBuildInfo.isTest) {
      await pair.serviceA.setQaDirectLinkRestriction(null);
    } else {
      await expectLater(
        pair.serviceA.setQaDirectLinkRestriction('device-b'),
        throwsStateError,
      );
      expect(pair.serviceA.qaRestrictedDeviceId, isNull);
    }
  });

  test(
    'restriction does not enroll a new identity into trust',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);
      await pair.serviceA.setQaDirectLinkRestriction('device-b');

      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () =>
            pair.serviceA.peerStates['endpoint-b'] ==
            NearbyConnectionState.disconnected,
      );

      expect(
        await pair.repositoriesA.nearbyDevices.getDevice('device-b'),
        isNull,
      );
      expect(pair.serviceA.deviceIdForEndpoint('endpoint-b'), isNull);
    },
    skip: !RelioBuildInfo.isTest,
  );
}
