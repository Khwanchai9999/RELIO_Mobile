import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';

import 'support/nearby_pair.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in NearbyTransportTestMode.values) {
    test(
      '${mode.diagnosticName} completes the two-peer consent flow',
      () async {
        final pair = await HandshakePair.create();
        addTearDown(pair.close);

        await pair.serviceA.configureTransportTestMode(mode);
        await pair.serviceB.configureTransportTestMode(mode);
        await pair.serviceA.startSession();
        await pair.serviceB.startSession();
        pair.transportA.discoverPeer();
        pair.transportB.discoverPeer();
        await Future<void>.delayed(Duration.zero);

        expect(pair.transportA.strategyName, mode.strategyName);
        expect(pair.transportB.strategyName, mode.strategyName);
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () =>
              pair.serviceB.pendingConnectionRequests.containsKey('endpoint-a'),
        );

        if (mode == NearbyTransportTestMode.clusterPauseDiscovery) {
          expect(pair.serviceA.isDiscovering, isFalse);
          expect(pair.serviceA.isAdvertising, isTrue);
        } else {
          expect(pair.serviceA.isDiscovering, isTrue);
        }

        await pair.serviceB.acceptConnectionRequest('endpoint-a');
        await waitFor(
          () =>
              pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
              pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
        );
        if (mode == NearbyTransportTestMode.clusterPauseDiscovery) {
          await waitFor(
            () => pair.serviceA.isDiscovering && pair.serviceB.isDiscovering,
          );
        }
        expect(
          pair.serviceA.peerStates['endpoint-b'],
          NearbyConnectionState.connected,
        );
        expect(
          pair.serviceB.peerStates['endpoint-a'],
          NearbyConnectionState.connected,
        );
      },
    );
  }
}
