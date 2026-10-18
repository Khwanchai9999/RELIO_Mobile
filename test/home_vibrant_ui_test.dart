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
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/home/home_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<({RelioDependencies dependencies, GoRouter router})> pumpHome(
    WidgetTester tester, {
    ThemeMode mode = ThemeMode.light,
    Size size = const Size(393, 900),
    double textScale = 1,
    bool connectedPeer = false,
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
              builder: (_, _) => const _DestinationScreen('nearby'),
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
    'Home shows the editable RELIO brand and real information sections',
    (tester) async {
      await pumpHome(tester);

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == 'RELIO',
        ),
        findsOneWidget,
      );
      expect(find.text('สื่อสารได้ แม้ไม่มีสัญญาณ'), findsOneWidget);
      expect(find.text('สวัสดี 👋'), findsOneWidget);
      expect(find.text('สถานะ'), findsNothing);
      expect(find.text('อุปกรณ์ใกล้เคียง'), findsOneWidget);
      expect(find.text('แอคชันด่วน'), findsOneWidget);
      expect(find.text('ข้อความล่าสุด'), findsOneWidget);
      expect(find.text('DEMO'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home supports Light and Dark themes', (tester) async {
    final result = await pumpHome(tester, mode: ThemeMode.light);
    expect(
      Theme.of(tester.element(find.byType(HomeScreen))).brightness,
      Brightness.light,
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
    expect(
      find.text('ไม่มี Internet แต่ Nearby ยังเชื่อมต่ออยู่'),
      findsOneWidget,
    );
    expect(find.text('Connected QA peer'), findsOneWidget);
    expect(find.text('REAL • เชื่อมต่อแล้ว'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Zero real peers shows a clear Nearby empty state', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.text('ยังไม่มีอุปกรณ์เชื่อมต่อ'), findsOneWidget);
    expect(find.text('เปิด Nearby เพื่อค้นหาอุปกรณ์รอบตัว'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('Quick actions keep their existing route mapping', (
    tester,
  ) async {
    final result = await pumpHome(tester);
    const routes = <String, String>{
      'quick-แชท': '/chats',
      'quick-ตำแหน่ง': '/nearby',
      'quick-ไฟล์ที่แชร์': '/sync',
      'quick-ซิงก์ข้อมูล': '/sync',
    };
    for (final entry in routes.entries) {
      result.router.go('/home');
      await tester.pumpAndSettle();
      await tapKey(tester, entry.key);
      expect(
        result.router.routeInformationProvider.value.uri.path,
        entry.value,
      );
    }
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
    await pumpHome(tester, size: const Size(320, 900));
    const widths = [320.0, 360.0, 393.0, 430.0];
    const scales = [1.0, 1.3, 1.6];
    for (final width in widths) {
      for (final scale in scales) {
        tester.view.physicalSize = Size(width, 900);
        tester.binding.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester.takeException(),
          isNull,
          reason: 'Home overflowed at ${width}dp and text scale $scale',
        );
      }
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
