import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/connectivity/runtime_connectivity.dart';
import 'package:relio_mobile/core/nearby/nearby_readiness.dart';

void main() {
  group('Nearby permission tiers', () {
    final cases = <(int, String, List<String>, bool)>[
      (24, 'legacy-coarse', [NearbyPermissionPolicy.coarse], true),
      (28, 'legacy-coarse', [NearbyPermissionPolicy.coarse], true),
      (29, 'legacy-fine', [NearbyPermissionPolicy.fine], true),
      (30, 'legacy-fine', [NearbyPermissionPolicy.fine], true),
      (
        31,
        'android12-bluetooth-location',
        [
          NearbyPermissionPolicy.fine,
          NearbyPermissionPolicy.scan,
          NearbyPermissionPolicy.connect,
          NearbyPermissionPolicy.advertise,
        ],
        true,
      ),
      (
        32,
        'android12L-bluetooth-location',
        [
          NearbyPermissionPolicy.fine,
          NearbyPermissionPolicy.scan,
          NearbyPermissionPolicy.connect,
          NearbyPermissionPolicy.advertise,
        ],
        true,
      ),
      (
        33,
        'modern-nearby',
        [
          NearbyPermissionPolicy.scan,
          NearbyPermissionPolicy.connect,
          NearbyPermissionPolicy.advertise,
          NearbyPermissionPolicy.wifi,
        ],
        false,
      ),
      (
        34,
        'modern-nearby',
        [
          NearbyPermissionPolicy.scan,
          NearbyPermissionPolicy.connect,
          NearbyPermissionPolicy.advertise,
          NearbyPermissionPolicy.wifi,
        ],
        false,
      ),
      (
        35,
        'modern-nearby',
        [
          NearbyPermissionPolicy.scan,
          NearbyPermissionPolicy.connect,
          NearbyPermissionPolicy.advertise,
          NearbyPermissionPolicy.wifi,
        ],
        false,
      ),
      (
        36,
        'modern-nearby',
        [
          NearbyPermissionPolicy.scan,
          NearbyPermissionPolicy.connect,
          NearbyPermissionPolicy.advertise,
          NearbyPermissionPolicy.wifi,
        ],
        false,
      ),
      (
        37,
        'future-local-network',
        [
          NearbyPermissionPolicy.scan,
          NearbyPermissionPolicy.connect,
          NearbyPermissionPolicy.advertise,
          NearbyPermissionPolicy.wifi,
        ],
        false,
      ),
    ];

    for (final (sdk, tier, permissions, locationRequired) in cases) {
      test('API $sdk selects only its Nearby permissions', () {
        final policy = NearbyPermissionPolicy(sdk);
        expect(policy.tier, tier);
        expect(policy.requiredPermissions, permissions);
        expect(policy.locationRequired, locationRequired);
        expect(
          policy.requestPermissions,
          isNot(contains(NearbyPermissionPolicy.localNetwork)),
        );
      });
    }
  });

  test('modern radios work with GPS off; missing scan permission blocks', () {
    final granted = {
      for (final permission in const NearbyPermissionPolicy(
        35,
      ).requiredPermissions)
        permission: true,
    };
    final modern = NearbyReadiness(
      policy: const NearbyPermissionPolicy(35),
      permissions: granted,
      bluetoothAvailable: true,
      bluetoothEnabled: true,
      wifiAvailable: true,
      wifiEnabled: true,
      locationEnabled: false,
      playServicesStatus: 'available',
    );
    expect(modern.ready, isTrue);
    expect(modern.policy.locationRequired, isFalse);

    final blocked = NearbyReadiness(
      policy: const NearbyPermissionPolicy(35),
      permissions: {...granted, NearbyPermissionPolicy.scan: false},
      bluetoothAvailable: true,
      bluetoothEnabled: true,
      playServicesStatus: 'available',
    );
    expect(blocked.ready, isFalse);
    expect(blocked.missingPermissions, contains(NearbyPermissionPolicy.scan));
  });

  test('API 29 Location off blocks only at the legacy tier', () {
    final readiness = RuntimeConnectivitySnapshot(
      androidSdk: 29,
      permissions: const {NearbyPermissionPolicy.fine: true},
      bluetoothAvailable: true,
      bluetoothEnabled: true,
      locationEnabled: false,
      playServicesStatus: 'available',
    ).nearbyReadiness;
    expect(readiness.ready, isFalse);
    expect(readiness.blockers, contains(NearbyBlocker.locationRequiredButOff));
  });

  test('API 37 local network permission is isolated behind target 37', () {
    const currentTarget = NearbyPermissionPolicy(37, targetSdk: 36);
    const futureTarget = NearbyPermissionPolicy(37, targetSdk: 37);
    expect(currentTarget.localNetworkRequired, isFalse);
    expect(futureTarget.localNetworkRequired, isTrue);
    expect(
      futureTarget.requiredPermissions,
      contains(NearbyPermissionPolicy.localNetwork),
    );
  });

  test('Wi-Fi off degrades P2P_CLUSTER without claiming readiness failure', () {
    final permissions = {
      for (final permission in const NearbyPermissionPolicy(
        35,
      ).requiredPermissions)
        permission: true,
    };
    final readiness = NearbyReadiness(
      policy: const NearbyPermissionPolicy(35),
      permissions: permissions,
      bluetoothAvailable: true,
      bluetoothEnabled: true,
      wifiAvailable: true,
      wifiEnabled: false,
      playServicesStatus: 'available',
    );
    expect(readiness.ready, isTrue);
    expect(readiness.wifiDegraded, isTrue);
  });

  test('Google Play Services failures and unsupported SDKs are explicit', () {
    const missingServices = NearbyReadiness(
      policy: NearbyPermissionPolicy(35),
      playServicesStatus: 'missing',
    );
    const oldSdk = NearbyReadiness(policy: NearbyPermissionPolicy(23));
    expect(
      missingServices.blockers,
      contains(NearbyBlocker.playServicesUnavailable),
    );
    expect(oldSdk.blockers, contains(NearbyBlocker.platformUnsupported));
  });
}
