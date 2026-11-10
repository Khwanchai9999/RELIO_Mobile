import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/diagnostics/diagnostics_log_service.dart';
import 'package:relio_mobile/core/domain/relio_entities.dart';
import 'package:relio_mobile/core/location/location_service.dart';
import 'package:relio_mobile/core/nearby/nearby_location_sharing_coordinator.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/developer/internal_tools_screen.dart';
import 'package:relio_mobile/features/nearby/nearby_map_canvas.dart';
import 'package:relio_mobile/features/nearby/nearby_screen.dart';

import 'support/nearby_pair.dart';

void main() {
  group('NearbyLocationSharingCoordinator', () {
    late AppDatabase database;
    late HandshakePair pair;
    late FakeLocationService locationService;
    late NearbyLocationSharingCoordinator coordinator;
    late DateTime currentTime;

    late LocationData validLocation;

    setUp(() async {
      validLocation = LocationData(
        latitude: 13.7563,
        longitude: 100.5018,
        accuracyMeters: 10.0,
        capturedAt: DateTime.now().toUtc(),
        source: 'test',
      );
      database = AppDatabase.memory();
      pair = await HandshakePair.create();
      currentTime = validLocation.capturedAt;
      locationService = FakeLocationService(
        LocationResult.success(validLocation),
      );
      coordinator = NearbyLocationSharingCoordinator(
        nearbyService: pair.serviceA,
        locationService: locationService,
        freshnessThreshold: const Duration(seconds: 45),
        stalenessThreshold: const Duration(seconds: 60),
        peerRateLimit: const Duration(seconds: 15),
        nowProvider: () => currentTime,
      );
    });

    tearDown(() async {
      await coordinator.dispose();
      await pair.close();
      await database.close();
    });

    test(
      'Trigger A/B/C: verified handshake triggers location sharing to verified peer',
      () async {
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
        );
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );

        expect(pair.serviceA.isEndpointVerifiedConnected('endpoint-b'), isTrue);

        await coordinator.onPeerHandshakeCompleted('endpoint-b');
        expect(
          locationService.requestedPositionInterval,
          const Duration(seconds: 10),
        );

        await waitFor(() async {
          final device = await pair.repositoriesB.nearbyDevices.getDevice(
            'device-a',
          );
          return device?.peerLatitude != null;
        });

        final peerOnB = await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        );
        expect(peerOnB?.peerLatitude, closeTo(13.7563, 0.0001));
        expect(peerOnB?.peerLongitude, closeTo(100.5018, 0.0001));
        expect(peerOnB?.peerLocationAccuracy, 10.0);
      },
    );

    test('No sharing to unverified or pending endpoints', () async {
      expect(
        pair.serviceA.isEndpointVerifiedConnected('unverified-endpoint'),
        isFalse,
      );

      await coordinator.onPeerHandshakeCompleted('unverified-endpoint');

      expect(coordinator.lastAcquiredLocation, isNull);
      expect(pair.serviceA.lastSentPacket, isNull);
    });

    test(
      'local GPS starts without a peer and updates only the local marker',
      () async {
        await coordinator.onAppResumed();
        await waitFor(() => coordinator.lastAcquiredLocation != null);

        expect(coordinator.activeStreamCount, 1);
        expect(coordinator.status, NearbyLiveLocationStatus.localOnly);
        expect(
          coordinator.lastAcquiredLocation?.latitude,
          validLocation.latitude,
        );
        expect(pair.serviceA.lastSentPacket, isNull);
      },
    );

    test(
      'location diagnostics show acquisition stages without coordinates',
      () async {
        final lines = <String>[];
        final diagnostics = DiagnosticsLogService(qaLogcatSink: lines.add);
        final instrumented = NearbyLocationSharingCoordinator(
          nearbyService: pair.serviceA,
          locationService: locationService,
          diagnostics: diagnostics,
          nowProvider: () => currentTime,
        );
        addTearDown(instrumented.dispose);

        await instrumented.onAppResumed();
        await waitFor(
          () => instrumented.status == NearbyLiveLocationStatus.localOnly,
        );
        await diagnostics.flush();

        final events = lines.map((line) => jsonDecode(line) as Map).toList();
        final names = events.map((event) => event['event']).toSet();
        expect(names, contains('location_stream_requested'));
        expect(names, contains('location_stream_started'));
        expect(names, contains('location_first_stream_fix'));
        expect(names, contains('location_fix_presented_locally'));
        expect(names, contains('location_fix_accepted_for_sharing'));
        expect(lines.join('\n'), isNot(contains('13.7563')));
        expect(lines.join('\n'), isNot(contains('100.5018')));
        for (final event in events) {
          expect(
            event.keys.any((key) => '$key'.toLowerCase().contains('token')),
            isFalse,
          );
          expect(
            event.keys.any((key) => '$key'.toLowerCase().contains('message')),
            isFalse,
          );
          expect(
            event.keys.any((key) => '$key'.toLowerCase().contains('latitude')),
            isFalse,
          );
          expect(
            event.keys.any((key) => '$key'.toLowerCase().contains('longitude')),
            isFalse,
          );
        }
      },
    );

    test(
      'recent cached fix is displayed locally but never becomes shareable',
      () async {
        final cached = LocationData(
          latitude: validLocation.latitude,
          longitude: validLocation.longitude,
          accuracyMeters: 85,
          capturedAt: currentTime.subtract(const Duration(minutes: 3)),
          source: 'lastKnown',
        );
        final localOnlyService = FakeLocationService(
          LocationResult.success(validLocation),
          lastKnown: LocationResult.success(cached),
        );
        final displayed = <LocationData>[];
        final localOnlyCoordinator = NearbyLocationSharingCoordinator(
          nearbyService: pair.serviceA,
          locationService: localOnlyService,
          onLocationForDisplay: displayed.add,
          nowProvider: () => currentTime,
        );
        addTearDown(localOnlyCoordinator.dispose);

        await localOnlyCoordinator.onAppResumed();
        await waitFor(() => displayed.isNotEmpty);

        expect(displayed.single.capturedAt, cached.capturedAt);
        expect(localOnlyCoordinator.lastAcquiredLocation, isNull);
        expect(pair.serviceA.lastSentPacket, isNull);
        expect(
          localOnlyCoordinator.status,
          NearbyLiveLocationStatus.waitingForFreshFix,
        );
      },
    );

    test(
      'live sharing starts only after saved authorization is enabled',
      () async {
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );
        await waitFor(
          () => pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
        );

        final optInCoordinator = NearbyLocationSharingCoordinator(
          nearbyService: pair.serviceA,
          locationService: locationService,
          initiallyEnabled: false,
        );
        addTearDown(optInCoordinator.dispose);

        await optInCoordinator.onPeerHandshakeCompleted('endpoint-b');
        expect(locationService.requestedPositionInterval, isNull);
        expect(optInCoordinator.activeStreamCount, 0);

        await optInCoordinator.setEnabled(true);
        await waitFor(() => optInCoordinator.isActive);
        await waitFor(
          () =>
              locationService.requestedPositionInterval ==
              const Duration(seconds: 10),
        );
        await waitFor(() async {
          final device = await pair.repositoriesB.nearbyDevices.getDevice(
            'device-a',
          );
          return device?.peerLatitude == validLocation.latitude;
        });
        expect(optInCoordinator.activeStreamCount, 1);
      },
    );

    test(
      'Gracefully handles permission denied or service disabled without error',
      () async {
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );

        locationService.lastKnownResult = const LocationResult.failure(
          LocationFailure.permissionDenied,
        );

        // Should complete gracefully without throwing
        await coordinator.onPeerHandshakeCompleted('endpoint-b');

        expect(coordinator.lastAcquiredLocation, isNull);
        expect(coordinator.lastBroadcastAt, isNull);
        expect(coordinator.status, NearbyLiveLocationStatus.permissionRequired);
      },
    );

    test(
      'one managed position stream serves repeated handshakes without new GPS streams',
      () async {
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );

        int locationCallCount = 0;
        final countingLocationService = _CountingLocationService(
          LocationResult.success(validLocation),
          onCall: () => locationCallCount++,
        );

        final testCoordinator = NearbyLocationSharingCoordinator(
          nearbyService: pair.serviceA,
          locationService: countingLocationService,
          freshnessThreshold: const Duration(seconds: 45),
          peerRateLimit: const Duration(seconds: 5),
          nowProvider: () => currentTime,
        );
        addTearDown(testCoordinator.dispose);

        // First trigger
        await testCoordinator.onPeerHandshakeCompleted('endpoint-b');
        expect(locationCallCount, 1);

        // A continuing stream remains open; a handshake does not create another.
        currentTime = currentTime.add(const Duration(seconds: 20));
        await testCoordinator.onPeerHandshakeCompleted('endpoint-b');
        expect(locationCallCount, 1);

        // Stream lifecycle, rather than cold location requests, owns updates.
        currentTime = currentTime.add(const Duration(seconds: 30));
        await testCoordinator.onPeerHandshakeCompleted('endpoint-b');
        expect(locationCallCount, 1);
      },
    );

    test('a repeated identical provider fix is not retransmitted', () async {
      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
      );

      await coordinator.onPeerHandshakeCompleted('endpoint-b');
      await waitFor(() => coordinator.lastBroadcastAt != null);
      final firstBroadcastTime = coordinator.lastBroadcastAt;
      expect(firstBroadcastTime, isNotNull);

      currentTime = currentTime.add(const Duration(seconds: 5));
      locationService.emitPosition(validLocation);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await coordinator.onPeerHandshakeCompleted('endpoint-b');

      expect(coordinator.lastBroadcastAt, firstBroadcastTime);
    });

    test(
      'disconnect removes peer cache and reconnect receives the latest fresh fix',
      () async {
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );
        await waitFor(
          () => pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
        );

        await coordinator.onPeerHandshakeCompleted('endpoint-b');
        await waitFor(() => coordinator.lastBroadcastAt != null);
        await waitFor(() async {
          final device = await pair.repositoriesB.nearbyDevices.getDevice(
            'device-a',
          );
          final capturedAt = device?.peerLocationCapturedAt;
          return capturedAt != null &&
              capturedAt.difference(validLocation.capturedAt).abs() <=
                  const Duration(seconds: 1) &&
              device?.peerLatitude == validLocation.latitude;
        });
        final firstBroadcast = coordinator.lastBroadcastAt;

        // Stop the real endpoint, then clear its stream cache.
        await pair.serviceA.disconnect('endpoint-b');
        await waitFor(
          () => !pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );
        coordinator.onPeerDisconnected('endpoint-b');

        currentTime = currentTime.add(const Duration(seconds: 2));
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );
        await waitFor(
          () => pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
        );
        await coordinator.onPeerHandshakeCompleted('endpoint-b');
        await waitFor(() async {
          final device = await pair.repositoriesB.nearbyDevices.getDevice(
            'device-a',
          );
          final capturedAt = device?.peerLocationCapturedAt;
          return capturedAt != null &&
              capturedAt.difference(validLocation.capturedAt).abs() <=
                  const Duration(seconds: 1) &&
              device?.peerLatitude == validLocation.latitude;
        });
        expect(coordinator.lastBroadcastAt, isNotNull);
        expect(coordinator.lastBroadcastAt!.isAfter(firstBroadcast!), isTrue);
      },
    );

    test(
      'foreground lifecycle owns one stream and resumes sharing after pause',
      () async {
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );

        // Initial share
        await coordinator.onPeerHandshakeCompleted('endpoint-b');
        await waitFor(() => coordinator.lastBroadcastAt != null);
        expect(coordinator.lastBroadcastAt, currentTime);

        await coordinator.setForeground(false);
        expect(coordinator.activeStreamCount, 0);
        expect(coordinator.status, NearbyLiveLocationStatus.paused);

        currentTime = currentTime.add(const Duration(seconds: 30));
        locationService.lastKnownResult = LocationResult.success(
          LocationData(
            latitude: validLocation.latitude,
            longitude: validLocation.longitude,
            accuracyMeters: validLocation.accuracyMeters,
            capturedAt: validLocation.capturedAt.add(
              const Duration(seconds: 30),
            ),
            source: 'live',
          ),
        );
        await coordinator.setForeground(true);
        await waitFor(() => coordinator.isActive);
        await waitFor(() => coordinator.lastBroadcastAt == currentTime);
        expect(coordinator.activeStreamCount, 1);
      },
    );

    test(
      'Trigger E: Permission or readiness changed broadcasts when stale',
      () async {
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );

        await coordinator.onPermissionOrReadinessChanged();
        await waitFor(() => coordinator.isActive);
        expect(coordinator.lastBroadcastAt, isNotNull);
      },
    );

    test(
      'SOS requests five-second live interval and keeps one stream',
      () async {
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );
        await coordinator.onPeerHandshakeCompleted('endpoint-b');
        expect(coordinator.activeStreamCount, 1);

        await coordinator.setLocalSosActive(true);

        expect(
          locationService.requestedPositionInterval,
          const Duration(seconds: 5),
        );
        expect(coordinator.requestedInterval, const Duration(seconds: 5));
        expect(coordinator.activeStreamCount, 1);
      },
    );

    test(
      'new stationary fixes preserve timestamp and accuracy metadata',
      () async {
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );
        await coordinator.onPeerHandshakeCompleted('endpoint-b');
        await waitFor(() => coordinator.lastPacketSentAt != null);
        final firstSent = coordinator.lastPacketSentAt;
        currentTime = currentTime.add(const Duration(seconds: 10));
        final nextFix = LocationData(
          latitude: validLocation.latitude,
          longitude: validLocation.longitude,
          accuracyMeters: 7.5,
          capturedAt: validLocation.capturedAt.add(const Duration(seconds: 10)),
          source: 'live',
        );

        locationService.emitPosition(nextFix);
        await waitFor(
          () => coordinator.lastPacketSentAt?.isAfter(firstSent!) ?? false,
        );

        expect(
          coordinator.lastAcceptedLocation?.capturedAt,
          nextFix.capturedAt,
        );
        expect(coordinator.lastAcceptedLocation?.accuracyMeters, 7.5);
        expect(
          coordinator.lastAcquiredLocation?.latitude,
          validLocation.latitude,
        );
      },
    );

    test(
      'stale stream fix is not rebroadcast and permission errors stop stream',
      () async {
        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
        );
        await coordinator.onPeerHandshakeCompleted('endpoint-b');
        final firstSent = coordinator.lastPacketSentAt;
        currentTime = currentTime.add(const Duration(minutes: 3));
        locationService.emitPosition(validLocation);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(coordinator.lastPacketSentAt, firstSent);
        expect(coordinator.status, NearbyLiveLocationStatus.waitingForFreshFix);

        locationService.emitError(
          const LocationStreamException(LocationFailure.permissionDenied),
        );
        await waitFor(
          () =>
              coordinator.status == NearbyLiveLocationStatus.permissionRequired,
        );
        expect(coordinator.activeStreamCount, 0);
      },
    );

    test('disabling live sharing immediately cancels the stream', () async {
      await pair.serviceA.connect('endpoint-b');
      await waitFor(
        () => pair.serviceA.isEndpointVerifiedConnected('endpoint-b'),
      );
      await coordinator.onPeerHandshakeCompleted('endpoint-b');
      expect(coordinator.activeStreamCount, 1);

      await coordinator.setEnabled(false);

      expect(coordinator.activeStreamCount, 0);
      expect(coordinator.status, NearbyLiveLocationStatus.disabled);
    });
  });

  group('Location packet validation and monotonic persistence', () {
    test(
      'Invalid coordinates (out of range or NaN) are rejected on receive',
      () async {
        final pair = await HandshakePair.create();
        addTearDown(pair.close);

        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
        );

        // Send packet with latitude > 90 (invalid)

        await pair.serviceA.publishMapLocation(
          LocationData(
            latitude: 120.0, // invalid point
            longitude: 100.0,
            capturedAt: DateTime.now().toUtc(),
            accuracyMeters: 10,
            source: 'test',
          ),
        );

        // Invalid point is not sent or accepted
        final peer = await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        );
        expect(peer?.peerLatitude, isNull);
        expect(peer?.peerLongitude, isNull);
      },
    );

    test(
      'Monotonic timestamp: stale location packet cannot regress newer location',
      () async {
        final pair = await HandshakePair.create();
        addTearDown(pair.close);

        await pair.serviceA.connect('endpoint-b');
        await waitFor(
          () => pair.serviceB.deviceIdForEndpoint('endpoint-a') == 'device-a',
        );

        final newerCapturedAt = DateTime.now().toUtc();
        final newerLocation = LocationData(
          latitude: 13.75,
          longitude: 100.50,
          accuracyMeters: 5.0,
          capturedAt: newerCapturedAt,
          source: 'test',
        );
        await pair.serviceA.publishMapLocation(newerLocation);

        await waitFor(() async {
          final d = await pair.repositoriesB.nearbyDevices.getDevice(
            'device-a',
          );
          return d?.peerLatitude != null;
        });

        final deviceBefore = await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        );
        expect(deviceBefore?.peerLatitude, closeTo(13.75, 0.001));

        // Attempt to publish an older location
        final olderLocation = LocationData(
          latitude: 12.00,
          longitude: 99.00,
          accuracyMeters: 10.0,
          capturedAt: newerCapturedAt.subtract(
            const Duration(minutes: 20),
          ), // older!
          source: 'test',
        );
        await pair.serviceA.publishMapLocation(olderLocation);

        // Ensure older location did NOT overwrite newer location
        final deviceAfter = await pair.repositoriesB.nearbyDevices.getDevice(
          'device-a',
        );
        expect(deviceAfter?.peerLatitude, closeTo(13.75, 0.001));
        expect(deviceAfter?.peerLongitude, closeTo(100.50, 0.001));
      },
    );
  });

  group('NearbyScreen Location UX (One Map Button, Zero Manual Sharing)', () {
    test(
      'developer override gates one foreground stream without duplication',
      () async {
        final database = AppDatabase.memory();
        final location = LocationData(
          latitude: 13.7563,
          longitude: 100.5018,
          accuracyMeters: 10,
          capturedAt: DateTime.now().toUtc(),
          source: 'test',
        );
        final locationService = FakeLocationService(
          LocationResult.success(location),
        );
        final dependencies = RelioDependencies(
          database: database,
          transport: MockNearbyTransport(autoAcknowledge: false),
          locationService: locationService,
          androidPlatformOverride: false,
        );
        addTearDown(() async {
          await dependencies.dispose();
          await database.close();
        });
        await dependencies.initialize();

        expect(
          dependencies.nearbyService.developerLocationSharingOverrideEnabled,
          isTrue,
        );
        await dependencies.nearbyService.setLiveLocationConsent(true);
        dependencies.nearbyService.updateLifecycleContext(
          lifecycleState: 'resumed',
          route: '/nearby',
        );
        await waitFor(() => locationService.positionStreamRequests == 1);
        await waitFor(
          () =>
              dependencies
                  .nearbyService
                  .locationCoordinator!
                  .lastAcquiredLocation !=
              null,
        );
        expect(
          dependencies.nearbyService.locationCoordinator!.status,
          NearbyLiveLocationStatus.localOnly,
        );

        await dependencies.nearbyService.setDeveloperLocationSharingOverride(
          false,
        );
        expect(
          dependencies.nearbyService.locationCoordinator!.activeStreamCount,
          0,
        );
        expect(
          await dependencies.repositories.settings.getBool(
            'nearby_live_location_dev_override',
            defaultValue: true,
          ),
          isFalse,
        );

        await dependencies.nearbyService.setDeveloperLocationSharingOverride(
          true,
        );
        await waitFor(() => locationService.positionStreamRequests == 2);
        await dependencies.nearbyService.setDeveloperLocationSharingOverride(
          true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(locationService.positionStreamRequests, 2);
        expect(
          dependencies.nearbyService.locationCoordinator!.activeStreamCount,
          1,
        );
      },
    );

    testWidgets('technical location override is in Developer Options', (
      tester,
    ) async {
      final database = AppDatabase.memory();
      final dependencies = RelioDependencies(
        database: database,
        transport: MockNearbyTransport(autoAcknowledge: false),
        androidPlatformOverride: false,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await dependencies.dispose();
        await database.close();
      });
      await dependencies.initialize();
      await dependencies.internalExperience.setDeveloperMode(true);

      await tester.pumpWidget(
        MaterialApp(
          home: RelioDependencyScope(
            dependencies: dependencies,
            child: const InternalToolsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('เครื่องมือทดลองและจำลอง'));
      await tester.pumpAndSettle();
      final override = find.byKey(
        const ValueKey('developer-live-location-override'),
      );
      expect(override, findsOneWidget);
      expect(tester.widget<SwitchListTile>(override).value, isTrue);
      await tester.tap(override);
      await tester.pumpAndSettle();
      expect(
        dependencies.nearbyService.developerLocationSharingOverrideEnabled,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('nearby-live-location-toggle')),
        findsNothing,
      );
    });

    testWidgets(
      'first-use disclosure records consent without a Nearby toggle',
      (tester) async {
        final database = AppDatabase.memory();
        final locationService = FakeLocationService(
          LocationResult.success(
            LocationData(
              latitude: 13.7563,
              longitude: 100.5018,
              accuracyMeters: 10,
              capturedAt: DateTime.now(),
              source: 'test',
            ),
          ),
        );
        final dependencies = RelioDependencies(
          database: database,
          transport: MockNearbyTransport(autoAcknowledge: false),
          locationService: locationService,
          androidPlatformOverride: false,
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await dependencies.dispose();
        });
        await dependencies.initialize();
        expect(dependencies.nearbyService.liveLocationSharingEnabled, isFalse);
        expect(dependencies.nearbyService.liveLocationSharingConsent, isNull);
        expect(
          dependencies.nearbyService.developerLocationSharingOverrideEnabled,
          isTrue,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: RelioDependencyScope(
              dependencies: dependencies,
              child: const NearbyScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('แชร์ตำแหน่งสดบน Nearby?'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('nearby-live-location-toggle')),
          findsNothing,
        );
        expect(locationService.freshLocationCalls, 0);

        await tester.tap(find.text('ไม่อนุญาต'));
        await tester.pumpAndSettle();
        expect(dependencies.nearbyService.liveLocationSharingEnabled, isFalse);
        expect(dependencies.nearbyService.liveLocationSharingConsent, isFalse);
        expect(
          await dependencies.repositories.settings.getBool(
            'nearby_live_location_enabled',
            defaultValue: true,
          ),
          isFalse,
        );
        expect(locationService.freshLocationCalls, 0);
      },
    );

    testWidgets(
      'Map has exactly ONE location FAB (Locate) and ZERO manual share buttons',
      (tester) async {
        final database = AppDatabase.memory();
        final dependencies = RelioDependencies(
          database: database,
          transport: MockNearbyTransport(autoAcknowledge: false),
          locationService: FakeLocationService(
            LocationResult.success(
              LocationData(
                latitude: 13.7563,
                longitude: 100.5018,
                capturedAt: DateTime.now(),
                source: 'test',
              ),
            ),
          ),
        );

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await dependencies.dispose();
          await database.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: RelioDependencyScope(
              dependencies: dependencies,
              child: const NearbyScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // 1. Exactly one Locate FAB
        expect(find.byTooltip('ไปยังตำแหน่งของฉัน'), findsOneWidget);
        expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);

        // 2. Zero manual share buttons
        expect(
          find.byTooltip('แชร์ตำแหน่งล่าสุดกับ peer ที่เชื่อมต่อ'),
          findsNothing,
        );
        expect(find.byIcon(Icons.share_location_rounded), findsNothing);

        // 3. Exactly one FloatingActionButton on the entire NearbyScreen
        expect(find.byType(FloatingActionButton), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Locate centers camera locally and NEVER broadcasts to peers',
      (tester) async {
        final database = AppDatabase.memory();
        final location = LocationData(
          latitude: 13.7563,
          longitude: 100.5018,
          accuracyMeters: 10,
          capturedAt: DateTime.now(),
          source: 'test',
        );
        final dependencies = RelioDependencies(
          database: database,
          transport: MockNearbyTransport(autoAcknowledge: false),
          locationService: FakeLocationService(
            LocationResult.success(location),
          ),
        );

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await dependencies.dispose();
          await database.close();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: RelioDependencyScope(
              dependencies: dependencies,
              child: const NearbyScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        var canvas = tester.widget<NearbyMapCanvas>(
          find.byType(NearbyMapCanvas),
        );
        expect(canvas.locationFocusRequest, 0);

        // Tap Locate button
        await tester.tap(find.byTooltip('ไปยังตำแหน่งของฉัน'));
        await tester.pump();

        canvas = tester.widget<NearbyMapCanvas>(find.byType(NearbyMapCanvas));
        // Camera focus requested locally
        expect(canvas.locationFocusRequest, 1);
        expect(canvas.myLocation?.latitude, 13.7563);
        expect(
          (dependencies.locationService as FakeLocationService)
              .freshLocationCalls,
          1,
        );

        // Purely local camera control: no packet sent over Nearby transport!
        expect(dependencies.nearbyService.lastSentPacket, isNull);
      },
    );
  });
}

class _CountingLocationService implements LocationService {
  _CountingLocationService(this.result, {required this.onCall});

  final LocationResult result;
  final VoidCallback onCall;

  @override
  Future<LocationResult> getFreshLocation({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    onCall();
    return result;
  }

  @override
  Future<LocationResult> getCurrentIfPermitted({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    onCall();
    return result;
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<LocationResult> getCurrentOrLastKnown({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    onCall();
    return result;
  }

  @override
  Future<LocationData?> getRecentLastKnownForDisplay({
    Duration maxAge = const Duration(minutes: 5),
  }) async => result.location;

  @override
  Future<Stream<LocationData>> watchPositions({
    required Duration interval,
  }) async {
    onCall();
    return Stream<LocationData>.multi((controller) {
      final location = result.location;
      if (location != null) controller.add(location);
    });
  }
}
