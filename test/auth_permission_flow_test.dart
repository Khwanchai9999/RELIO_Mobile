import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/permissions/permission_service.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';

Finder findGeneratedName() => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      RegExp(r'^ผู้ใช้ RELIO \d{4}$').hasMatch(widget.data ?? ''),
);

class _FakePermissionService extends PermissionService {
  _FakePermissionService({
    required bool initiallyGranted,
    this.grantOnRequest = false,
  }) : _granted = initiallyGranted,
       super(isAndroid: true, androidSdkReader: () async => 35);

  bool _granted;
  final bool grantOnRequest;
  int readCalls = 0;
  int requestCalls = 0;

  bool get allGranted => _granted;

  NearbyPermissionSnapshot _snapshot() => NearbyPermissionSnapshot(
    androidSdk: 35,
    bluetoothScan: _status,
    bluetoothConnect: _status,
    bluetoothAdvertise: _status,
    nearbyWifiDevices: _status,
    locationWhenInUse: ph.PermissionStatus.granted,
  );

  ph.PermissionStatus get _status =>
      _granted ? ph.PermissionStatus.granted : ph.PermissionStatus.denied;

  @override
  Future<NearbyPermissionSnapshot> readNearbyPermissions() async {
    readCalls++;
    return _snapshot();
  }

  @override
  Future<NearbyPermissionSnapshot> requestNearbyPermissions() async {
    requestCalls++;
    if (grantOnRequest) _granted = true;
    return _snapshot();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<({FakeCloudDataSource cloud, RelioDependencies dependencies})> pumpApp(
    WidgetTester tester, {
    required _FakePermissionService permissions,
    bool createLoginAccount = true,
  }) async {
    final cloud = FakeCloudDataSource();
    if (createLoginAccount) {
      cloud.createTestIdentity(email: 'member@example.com');
    }
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
      cloudDataSource: cloud,
      permissionService: permissions,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await dependencies.dispose();
    });
    await dependencies.initialize();
    await tester.pumpWidget(RelioApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    return (cloud: cloud, dependencies: dependencies);
  }

  Future<void> openLogin(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'เข้าสู่ระบบ').first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> pumpPastHomeTransition(WidgetTester tester) async {
    await tester.pump();
    if (find.text('สวัสดี 👋').evaluate().isNotEmpty) {
      // The Home CHECKING indicator is intentionally continuous.
      await tester.pump(const Duration(milliseconds: 500));
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<void> signIn(
    WidgetTester tester, {
    String password = 'password',
  }) async {
    final email = find.byType(TextFormField).at(0);
    final passwordField = find.byType(TextFormField).at(1);
    await tester.ensureVisible(email);
    await tester.enterText(email, 'member@example.com');
    await tester.ensureVisible(passwordField);
    await tester.enterText(passwordField, password);
    final button = find.widgetWithText(FilledButton, 'เข้าสู่ระบบ').last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await pumpPastHomeTransition(tester);
  }

  testWidgets('login with all required permissions opens Home directly', (
    tester,
  ) async {
    final permissions = _FakePermissionService(initiallyGranted: true);
    await pumpApp(tester, permissions: permissions);
    await openLogin(tester);
    final readsBeforeLogin = permissions.readCalls;

    await signIn(tester);

    expect(findGeneratedName(), findsOneWidget);
    expect(find.text('อนุญาตทั้งหมด'), findsNothing);
    expect(permissions.readCalls, greaterThan(readsBeforeLogin));
    expect(permissions.requestCalls, 0);
  });

  testWidgets('login with a missing required permission opens Permissions', (
    tester,
  ) async {
    final permissions = _FakePermissionService(initiallyGranted: false);
    await pumpApp(tester, permissions: permissions);
    await openLogin(tester);
    await signIn(tester);

    expect(find.text('อนุญาตทั้งหมด'), findsOneWidget);
    expect(findGeneratedName(), findsNothing);
    expect(permissions.requestCalls, 0);
  });

  testWidgets('failed login does not run permission routing', (tester) async {
    final permissions = _FakePermissionService(initiallyGranted: true);
    await pumpApp(tester, permissions: permissions);
    await openLogin(tester);
    final readsBeforeLogin = permissions.readCalls;

    await signIn(tester, password: 'incorrect-password');

    expect(find.text('เข้าสู่ระบบ'), findsWidgets);
    expect(findGeneratedName(), findsNothing);
    expect(permissions.readCalls, readsBeforeLogin);
    expect(permissions.requestCalls, 0);
  });

  testWidgets('successful Register still opens the permission step', (
    tester,
  ) async {
    final permissions = _FakePermissionService(initiallyGranted: false);
    await pumpApp(tester, permissions: permissions, createLoginAccount: false);
    await openLogin(tester);
    await tester.tap(find.text('ยังไม่มีบัญชี? สร้างบัญชีใหม่'));
    await pumpPastHomeTransition(tester);

    final fields = find.byType(TextFormField);
    final registrationValues = [
      'Demo Member',
      'demo@example.com',
      'RelioDemo123!',
      'RelioDemo123!',
    ];
    for (var index = 0; index < registrationValues.length; index++) {
      final field = fields.at(index);
      await tester.ensureVisible(field);
      await tester.enterText(field, registrationValues[index]);
    }
    final consent = find.byType(CheckboxListTile);
    await tester.ensureVisible(consent);
    await tester.tap(consent);
    await pumpPastHomeTransition(tester);
    final createAccount = find.widgetWithText(FilledButton, 'สร้างบัญชี');
    await tester.ensureVisible(createAccount);
    await tester.tap(createAccount);
    await tester.pumpAndSettle();

    expect(find.text('อนุญาตทั้งหมด'), findsOneWidget);
  });

  testWidgets('permission action requests access and opens Home when granted', (
    tester,
  ) async {
    final permissions = _FakePermissionService(
      initiallyGranted: false,
      grantOnRequest: true,
    );
    await pumpApp(tester, permissions: permissions);
    await openLogin(tester);
    await signIn(tester);
    expect(find.text('อนุญาตทั้งหมด'), findsOneWidget);

    final allowButton = find.text('อนุญาตทั้งหมด');
    await tester.ensureVisible(allowButton);
    await tester.tap(allowButton);
    await pumpPastHomeTransition(tester);

    expect(permissions.requestCalls, 1);
    expect(permissions.allGranted, isTrue);
    expect(findGeneratedName(), findsOneWidget);
  });

  testWidgets('denied permission stays on screen and skip remains explicit', (
    tester,
  ) async {
    final permissions = _FakePermissionService(initiallyGranted: false);
    await pumpApp(tester, permissions: permissions);
    await openLogin(tester);
    await signIn(tester);

    final allowButton = find.text('อนุญาตทั้งหมด');
    await tester.ensureVisible(allowButton);
    await tester.tap(allowButton);
    await tester.pumpAndSettle();
    expect(permissions.requestCalls, 1);
    expect(find.text('อนุญาตทั้งหมด'), findsOneWidget);
    expect(
      find.textContaining('ยังไม่ได้รับอนุญาตสิทธิ์ Nearby ที่จำเป็น'),
      findsOneWidget,
    );
    expect(findGeneratedName(), findsNothing);

    final skipButton = find.text('ข้ามขั้นตอนนี้');
    await tester.ensureVisible(skipButton);
    await tester.tap(skipButton);
    await pumpPastHomeTransition(tester);
    expect(findGeneratedName(), findsOneWidget);
  });

  testWidgets('logout keeps granted permissions and next login goes Home', (
    tester,
  ) async {
    final permissions = _FakePermissionService(initiallyGranted: true);
    final fixture = await pumpApp(tester, permissions: permissions);
    await openLogin(tester);
    await signIn(tester);
    expect(fixture.cloud.currentIdentity, isNotNull);

    final profileTab = find.text('โปรไฟล์');
    await tester.ensureVisible(profileTab);
    await tester.tap(profileTab);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
    await tester.scrollUntilVisible(
      find.text('ออกจากระบบ'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ออกจากระบบ'), findsOneWidget);
    final logoutButton = find.text('ออกจากระบบ');
    await tester.ensureVisible(logoutButton);
    await tester.tap(logoutButton);
    await tester.pumpAndSettle();
    expect(find.text('RELIO'), findsOneWidget);
    expect(permissions.allGranted, isTrue);
    expect(permissions.requestCalls, 0);

    await openLogin(tester);
    await signIn(tester);
    expect(findGeneratedName(), findsOneWidget);
    expect(find.text('อนุญาตทั้งหมด'), findsNothing);
    expect(permissions.allGranted, isTrue);
    expect(permissions.requestCalls, 0);
  });
}
