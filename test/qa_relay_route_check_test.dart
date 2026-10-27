import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';

import 'support/nearby_pair.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QA route check refuses an unconnected destination', () async {
    final pair = await HandshakePair.create();
    addTearDown(pair.close);
    await pair.serviceA.connect('endpoint-b');
    await waitFor(
      () =>
          pair.serviceA.deviceIdForEndpoint('endpoint-b') == 'device-b' &&
          pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a' &&
          pair.serviceA.peerStates['endpoint-b'] ==
              NearbyConnectionState.connected,
    );
    expect(
      await pair.serviceA.checkQaRelayRoute(
        middleDeviceId: 'device-b',
        destinationDeviceId: 'device-c',
      ),
      isFalse,
    );
  });
}
