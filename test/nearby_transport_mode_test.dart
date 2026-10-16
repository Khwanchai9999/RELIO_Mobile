import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';

import 'support/nearby_pair.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'repeated discovery for one endpoint updates instead of appending',
    () async {
      final pair = await HandshakePair.create();
      addTearDown(pair.close);

      pair.transportA.discoverPeer();
      pair.transportA.discoverPeer();
      await Future<void>.delayed(Duration.zero);

      expect(
        pair.serviceA.discoveredPeers.where((peer) => peer.id == 'endpoint-b'),
        hasLength(1),
      );
    },
  );

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
        if (mode == NearbyTransportTestMode.clusterPauseDiscovery) {
          expect(pair.serviceA.isDiscovering, isFalse);
          expect(pair.serviceA.isAdvertising, isTrue);
        } else {
          expect(pair.serviceA.isDiscovering, isTrue);
        }

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
