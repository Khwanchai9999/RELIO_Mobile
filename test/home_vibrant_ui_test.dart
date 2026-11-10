import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/app/theme/relio_theme.dart';
import 'package:relio_mobile/core/connectivity/qa_internet_simulator.dart';
import 'package:relio_mobile/core/connectivity/runtime_connectivity.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/nearby/nearby_readiness.dart';
import 'package:relio_mobile/core/nearby/nearby_reachability.dart';
import 'package:relio_mobile/core/nearby/relio_packet.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/flashlight/screen_flashlight_screen.dart';
import 'package:relio_mobile/features/home/home_screen.dart';
import 'package:relio_mobile/features/nearby/nearby_screen.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<({RelioDependencies dependencies, GoRouter router})> pumpHome(
    WidgetTester tester, {
    ThemeMode mode = ThemeMode.light,
    Size size = const Size(393, 900),
    double textScale = 1,
    bool connectedPeer = false,
    bool startChecking = false,
    bool showNearbyScreen = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.binding.platformDispatcher.textScaleFactorTestValue = textScale;

    final offline = QaInternetSimulator.forTesting(
      qaBuild: true,
      bootOffline: true,
    );
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
      internetSimulator: offline,
    );
    await dependencies.initialize();
    // ชื่อ Guest ที่สร้างจริงสุ่มตัวเลข จึงกำหนดชื่อทดสอบคงที่เพื่อให้ Golden ทำซ้ำได้
    await dependencies.identity.setDisplayName('ผู้ใช้ RELIO ทดสอบ');
    if (!startChecking) {
      dependencies.nearbyService.updateReadiness(
        const NearbyReadiness(
          policy: NearbyPermissionPolicy(35),
          permissions: {
            NearbyPermissionPolicy.scan: true,
            NearbyPermissionPolicy.connect: true,
            NearbyPermissionPolicy.advertise: true,
            NearbyPermissionPolicy.wifi: true,
          },
          bluetoothAvailable: true,
          bluetoothEnabled: true,
          wifiAvailable: true,
          wifiEnabled: true,
          locationEnabled: true,
          playServicesStatus: 'available',
          transportAvailable: true,
        ),
      );
    }
    if (connectedPeer) {
      dependencies.nearbyService.discoveredPeers.add(
        const NearbyPeer(
          id: 'qa-endpoint',
          name: 'Connected QA peer',
          deviceId: 'qa-device-identity',
          connected: true,
        ),
      );
      dependencies.nearbyService.peerStates['qa-endpoint'] =
          NearbyConnectionState.connected;
      dependencies.nearbyService.notifyListeners();
    }
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              RelioShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            GoRoute(
              path: '/nearby',
              builder: (_, _) => showNearbyScreen
                  ? const NearbyScreen()
                  : const _DestinationScreen('nearby'),
            ),
            GoRoute(
              path: '/chats',
              builder: (_, _) => const _DestinationScreen('chats'),
            ),
            GoRoute(
              path: '/chat/:id',
              builder: (_, state) =>
                  _DestinationScreen('chat:${state.pathParameters['id']}'),
            ),
            GoRoute(
              path: '/sos',
              builder: (_, _) => const _DestinationScreen('sos'),
            ),
            GoRoute(
              path: '/rescue',
              builder: (_, _) => const _DestinationScreen('rescue'),
            ),
            GoRoute(
              path: '/profile',
              builder: (_, _) => const _DestinationScreen('profile'),
            ),
            GoRoute(
              path: '/settings',
              builder: (_, _) => const _DestinationScreen('settings'),
            ),
            GoRoute(
              path: '/sync',
              builder: (_, _) => const _DestinationScreen('sync'),
            ),
          ],
        ),
        GoRoute(
          path: '/screen-flashlight',
          builder: (_, _) => const ScreenFlashlightScreen(),
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      await dependencies.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      RelioDependencyScope(
        dependencies: dependencies,
        child: MaterialApp.router(
          theme: RelioTheme.light(),
          darkTheme: RelioTheme.dark(),
          themeMode: mode,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return (dependencies: dependencies, router: router);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Home keeps the RELIO header, profile, emergency cards, and connectivity',
    (tester) async {
      await pumpHome(tester);

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/branding/relio_wordmark.png',
        ),
        findsOneWidget,
      );
      expect(find.text('สื่อสารได้ แม้ไม่มีสัญญาณ'), findsNothing);
      expect(find.text('สวัสดี 👋'), findsOneWidget);
      expect(find.text('สถานะ'), findsNothing);
      expect(find.text('สถานะเน็ตและอุปกรณ์ใกล้เคียง'), findsOneWidget);
      expect(find.text('Wi-Fi'), findsOneWidget);
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(find.text('อุปกรณ์\nใกล้เคียง'), findsOneWidget);
      expect(find.text('อุปกรณ์ใกล้เคียง'), findsOneWidget);
      expect(find.text('ซิงก์ข้อมูล'), findsOneWidget);
      expect(find.text('Cloud Sync'), findsNothing);
      expect(find.text('แอคชันด่วน'), findsNothing);
      expect(find.text('ข้อความล่าสุด'), findsNothing);
      expect(find.text('DEMO'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Connectivity panel can scroll fully into view after cards', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(360, 800));

    final profileTop = tester
        .getTopLeft(find.byKey(const ValueKey('home-profile-card')))
        .dy;
    final panel = find.byKey(const ValueKey('home-connectivity-panel'));
    final panelTop = tester.getTopLeft(panel).dy;
    final sosTop = tester
        .getTopLeft(find.byKey(const ValueKey('home-sos-card')))
        .dy;
    final rescueTop = tester
        .getTopLeft(find.byKey(const ValueKey('home-rescue-card')))
        .dy;

    expect(profileTop, lessThan(sosTop));
    expect(sosTop, lessThan(rescueTop));
    expect(rescueTop, lessThan(panelTop));
    await tester.ensureVisible(panel);
    await tester.pumpAndSettle();
    final visiblePanelRect = tester.getRect(panel);
    final navigationTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
    expect(visiblePanelRect.bottom, lessThanOrEqualTo(navigationTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home links Nearby and Cloud tiles to their existing routes', (
    tester,
  ) async {
    final result = await pumpHome(tester, size: const Size(393, 900));
    expect(find.text('แจ้งเหตุไปยังอุปกรณ์ใกล้เคียง'), findsOneWidget);
    expect(find.text('แจ้งเหตุไปยังเพื่อนร่วมทีม'), findsNothing);

    final nearbyTile = find.text('อุปกรณ์ใกล้เคียง');
    await tester.ensureVisible(nearbyTile);
    await tester.tap(nearbyTile);
    await tester.pumpAndSettle();
    expect(result.router.routeInformationProvider.value.uri.path, '/nearby');

    result.router.go('/home');
    await tester.pumpAndSettle();
    final syncTile = find.text('ซิงก์ข้อมูล');
    await tester.ensureVisible(syncTile);
    final syncTapTarget = find.ancestor(
      of: syncTile,
      matching: find.byType(InkWell),
    );
    await tester.tap(syncTapTarget.first);
    await tester.pumpAndSettle();
    expect(result.router.routerDelegate.currentConfiguration.uri.path, '/sync');
    result.router.go('/home');
    await tester.pumpAndSettle();
    expect(result.router.routerDelegate.currentConfiguration.uri.path, '/home');
  });

  testWidgets(
    'Home readiness follows known Nearby state and stays unknown honestly',
    (tester) async {
      final result = await pumpHome(tester, startChecking: true);
      expect(find.text('กำลังตรวจสอบ'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      result.dependencies.nearbyService.updateReadiness(
        const NearbyReadiness(
          policy: NearbyPermissionPolicy(35),
          playServicesStatus: 'unknown',
        ),
      );
      await tester.pump();
      expect(find.text('ต้องตรวจสอบบางอย่าง'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      result.dependencies.nearbyService.updateReadiness(
        const NearbyReadiness(
          policy: NearbyPermissionPolicy(35),
          permissions: {
            NearbyPermissionPolicy.scan: true,
            NearbyPermissionPolicy.connect: true,
            NearbyPermissionPolicy.advertise: true,
            NearbyPermissionPolicy.wifi: true,
          },
          bluetoothAvailable: true,
          bluetoothEnabled: true,
          wifiAvailable: true,
          wifiEnabled: true,
          locationEnabled: true,
          playServicesStatus: 'unknown',
          transportAvailable: true,
        ),
      );
      await tester.pump();
      expect(find.text('กำลังตรวจสอบ'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      result.dependencies.nearbyService.updateReadiness(
        const NearbyReadiness(
          policy: NearbyPermissionPolicy(35),
          permissions: {
            NearbyPermissionPolicy.scan: true,
            NearbyPermissionPolicy.connect: true,
            NearbyPermissionPolicy.advertise: true,
            NearbyPermissionPolicy.wifi: true,
          },
          bluetoothAvailable: true,
          bluetoothEnabled: true,
          wifiAvailable: true,
          wifiEnabled: true,
          locationEnabled: true,
          playServicesStatus: 'available',
          transportAvailable: true,
        ),
      );
      await tester.pump();
      expect(find.text('ระบบพร้อมใช้งาน'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Wi-Fi'), findsOneWidget);
      expect(find.text('Bluetooth'), findsOneWidget);
    },
  );

  testWidgets(
    'greeting keeps representative Thai and English names on one line',
    (tester) async {
      final result = await pumpHome(tester, size: const Size(360, 800));
      const names = [
        'ขวัญชัย',
        'ผู้ใช้ RELIO 2518',
        'ผู้ใช้ RELIO Huawei',
        'Long English display name RELIO',
        'ชื่อภาษาไทยที่ยาวเพื่อทดสอบการแสดงผล',
        'A very long English RELIO name',
      ];
      for (final width in [360.0, 384.0, 393.0]) {
        tester.view.physicalSize = Size(width, 800);
        double? cardHeight;
        for (final name in names) {
          await result.dependencies.identity.setDisplayName(name);
          await tester.pumpAndSettle();
          final nameText = find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == name,
          );
          expect(nameText, findsOneWidget, reason: name);
          expect(tester.widget<Text>(nameText).maxLines, 1, reason: name);
          final currentHeight = tester
              .getSize(find.byKey(const ValueKey('home-profile-card')))
              .height;
          cardHeight ??= currentHeight;
          expect(currentHeight, cardHeight, reason: 'Card height for $name');
          expect(
            tester.getRect(nameText).right,
            lessThanOrEqualTo(
              tester.getRect(find.byTooltip('ไฟฉายหน้าจอ')).left,
            ),
            reason: 'Name must not collide with shortcut for $name',
          );
          expect(
            find.text('ระบบพร้อมใช้งาน'),
            findsOneWidget,
            reason: 'Readiness remains visible for $name',
          );
          expect(tester.takeException(), isNull, reason: name);
        }
      }
    },
  );

  testWidgets('flashlight shortcut opens independently from profile card', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('ไฟฉายหน้าจอ'));
    await tester.pumpAndSettle();
    expect(find.byType(ScreenFlashlightScreen), findsOneWidget);
    expect(find.text('แสงสีขาว'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ScreenFlashlightScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.byTooltip('ไฟฉายหน้าจอ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ออก'));
    await tester.pumpAndSettle();
    expect(find.byType(ScreenFlashlightScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Home supports Light and Dark themes', (tester) async {
    final result = await pumpHome(tester, mode: ThemeMode.light);
    expect(
      Theme.of(tester.element(find.byType(HomeScreen))).brightness,
      Brightness.light,
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/branding/relio_wordmark.png'),
        tester.element(find.byType(HomeScreen)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home-build68-light.png'),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      RelioDependencyScope(
        dependencies: result.dependencies,
        child: MaterialApp.router(
          theme: RelioTheme.light(),
          darkTheme: RelioTheme.dark(),
          themeMode: ThemeMode.dark,
          routerConfig: result.router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(HomeScreen))).brightness,
      Brightness.dark,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/relio_wordmark_dark_final.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dark Home renders its high-contrast wordmark preview', (
    tester,
  ) async {
    await pumpHome(tester, mode: ThemeMode.dark);
    final darkWordmark = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/branding/relio_wordmark_dark_final.png',
    );
    expect(darkWordmark, findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home-build65-dark.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home wordmark fits narrow Android-sized headers', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(320, 740));
    final lightWordmark = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/branding/relio_wordmark.png',
    );
    expect(lightWordmark, findsOneWidget);
    expect(tester.getRect(lightWordmark).width, lessThanOrEqualTo(154));
    expect(find.text('สื่อสารได้ แม้ไม่มีสัญญาณ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Offline Internet is shown separately from connected Nearby', (
    tester,
  ) async {
    final result = await pumpHome(tester, connectedPeer: true);
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      result.dependencies.connectivityStatus.status.reachability,
      InternetReachability.offline,
    );
    expect(find.text('สถานะเน็ตและอุปกรณ์ใกล้เคียง'), findsOneWidget);
    expect(find.text('Connected QA peer'), findsNothing);
    expect(find.text('REAL • เชื่อมต่อแล้ว'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Zero peers keeps the connectivity count and status visible', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('อุปกรณ์\nใกล้เคียง'), findsOneWidget);
    expect(find.text('อุปกรณ์ใกล้เคียง'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home and Nearby count direct and remote identities once', (
    tester,
  ) async {
    final result = await pumpHome(tester, showNearbyScreen: true);
    final service = result.dependencies.nearbyService;
    final wire = result.dependencies.transport as MockNearbyTransport;
    Future<void> waitFor(bool Function() condition) async {
      for (var frame = 0; frame < 50 && !condition(); frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(condition(), isTrue);
    }

    {
      await service.setLiveLocationConsent(false);
      wire.simulatePeer(id: 'B-endpoint', name: 'Direct B');
      await waitFor(() => service.discoveredPeers.isNotEmpty);
      await service.connect('B-endpoint');
      await waitFor(
        () =>
            service.peerStates['B-endpoint'] == NearbyConnectionState.connected,
      );
      wire.simulateIncoming(
        peerId: 'B-endpoint',
        bytes: RelioPacket.hello(
          senderDeviceId: 'B',
          senderUserId: 'B',
          displayName: 'Direct B',
          status: DeviceStatus.normal,
          capabilities: [nearbyReachabilityCapability],
        ).toBytes(),
      );
      await waitFor(() => service.isDeviceConnected('B'));
      wire.simulateIncoming(
        peerId: 'B-endpoint',
        bytes: RelioPacket(
          protocolVersion: 1,
          packetId: 'test-snapshot',
          type: RelioPacketType.reachabilitySnapshot,
          senderDeviceId: 'B',
          senderUserId: 'B',
          createdAt: DateTime.now(),
          payload: {
            'sequence': 1,
            'routes': [
              {
                'path': ['C'],
                'name': 'Remote C',
                'leaseMs': 20000,
              },
              {
                'path': ['X', 'C'],
                'name': 'Remote C',
                'leaseMs': 20000,
              },
            ],
          },
        ).toBytes(),
      );
      await waitFor(() => service.reachablePeerCount == 2);
    }
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    result.router.go('/nearby');
    await tester.pumpAndSettle();
    final listChoice = find.widgetWithText(ChoiceChip, 'รายการ');
    if (listChoice.evaluate().isNotEmpty) {
      await tester.tap(listChoice);
      await tester.pumpAndSettle();
    }
    expect(find.text('อุปกรณ์ที่เข้าถึงได้ • 2 เครื่อง'), findsOneWidget);
    expect(find.byKey(const ValueKey('nearby-remote-C')), findsOneWidget);
    expect(find.text('เข้าถึงผ่านรีเลย์ • 2 ทอด'), findsOneWidget);

    wire.simulateConnectionLoss('B-endpoint');
    await waitFor(() => service.reachablePeerCount == 0);
    await tester.pump();
    expect(find.byKey(const ValueKey('nearby-remote-C')), findsNothing);
    expect(find.text('อุปกรณ์ที่เข้าถึงได้ • 0 เครื่อง'), findsOneWidget);
  });

  testWidgets('SOS and Rescue cards navigate without activating a mode', (
    tester,
  ) async {
    final result = await pumpHome(tester);
    await tapKey(tester, 'home-sos-card');
    expect(result.router.routeInformationProvider.value.uri.path, '/sos');
    expect(find.text('destination:sos'), findsOneWidget);

    result.router.go('/home');
    await tester.pumpAndSettle();
    await tapKey(tester, 'home-rescue-card');
    expect(result.router.routeInformationProvider.value.uri.path, '/rescue');
    expect(find.text('destination:rescue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quick actions and recent messages are absent from Home', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.text('แอคชันด่วน'), findsNothing);
    expect(find.text('ข้อความล่าสุด'), findsNothing);
    expect(find.byKey(const ValueKey('quick-แชท')), findsNothing);
    expect(find.byKey(const ValueKey('quick-ตำแหน่ง')), findsNothing);
    expect(find.byKey(const ValueKey('quick-ไฟล์ที่แชร์')), findsNothing);
    expect(find.byKey(const ValueKey('quick-ซิงก์ข้อมูล')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bottom navigation preserves route and selected tab behavior', (
    tester,
  ) async {
    final result = await pumpHome(tester);
    await tester.tap(find.byIcon(Icons.radar_outlined));
    await tester.pumpAndSettle();
    expect(result.router.routeInformationProvider.value.uri.path, '/nearby');
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();
    expect(result.router.routeInformationProvider.value.uri.path, '/chats');
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Header settings action uses the existing destination', (
    tester,
  ) async {
    final result = await pumpHome(tester);
    await tester.tap(find.byTooltip('ตั้งค่า'));
    await tester.pumpAndSettle();
    expect(result.router.routeInformationProvider.value.uri.path, '/settings');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home has no overflow at supported widths and Thai text scales', (
    tester,
  ) async {
    const sizes = [
      Size(320, 568),
      Size(360, 640),
      Size(360, 800),
      Size(393, 800),
      Size(430, 932),
    ];
    const scales = [1.0, 1.3, 1.6];
    await pumpHome(tester, size: sizes.first);
    for (final size in sizes) {
      for (final scale in scales) {
        tester.view.physicalSize = size;
        tester.binding.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Home overflowed at ${size.width}x${size.height}dp and text scale $scale',
        );
        await tester.ensureVisible(find.text('ซิงก์ข้อมูล'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Connectivity panel overflowed at ${size.width}x${size.height}dp and text scale $scale',
        );
      }
    }
  });

  testWidgets('Stacked emergency cards keep their content compact', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(360, 900));
    for (final width in [360.0, 393.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();

      for (final key in ['home-sos-card', 'home-rescue-card']) {
        final card = find.byKey(ValueKey(key));
        expect(card, findsOneWidget);
        expect(tester.getSize(card).height, lessThan(150));
      }
      expect(tester.takeException(), isNull);
    }
  });
}

class _DestinationScreen extends StatelessWidget {
  const _DestinationScreen(this.name);

  final String name;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('destination:$name')));
}
