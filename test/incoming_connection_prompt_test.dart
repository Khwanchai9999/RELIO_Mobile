import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('incoming request reaches root prompt after Nearby page leaves', (
    tester,
  ) async {
    final database = AppDatabase.memory();
    final transport = MockNearbyTransport();
    final dependencies = RelioDependencies(
      database: database,
      transport: transport,
      useMockTransport: true,
    );
    await dependencies.nearbyService.initialize();
    addTearDown(dependencies.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => IncomingConnectionPromptHost(
          dependencies: dependencies,
          navigatorKey: navigatorKey,
          child: child ?? const SizedBox.shrink(),
        ),
        navigatorKey: navigatorKey,
        home: const _NearbyPage(),
      ),
    );
    await tester.tap(find.text('Leave Nearby'));
    await tester.pumpAndSettle();
    expect(find.text('Elsewhere'), findsOneWidget);

    transport.simulateIncomingConnection(id: 'arriving-peer', name: 'Peer B');
    await tester.pumpAndSettle();
    expect(find.text('คำขอเชื่อมต่อ'), findsOneWidget);
    expect(find.text('Peer B ต้องการเชื่อมต่อกับคุณ'), findsOneWidget);
    expect(find.text('ยอมรับ'), findsOneWidget);
    expect(find.text('ปฏิเสธ'), findsOneWidget);
    await tester.tap(find.text('ปฏิเสธ'));
    await tester.pumpAndSettle();
    expect(transport.rejectedConnections, contains('arriving-peer'));
  });
}

class _NearbyPage extends StatelessWidget {
  const _NearbyPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const _OtherPage()),
        ),
        child: const Text('Leave Nearby'),
      ),
    ),
  );
}

class _OtherPage extends StatelessWidget {
  const _OtherPage();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Elsewhere')));
}
