import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/app/router.dart';
import 'package:relio_mobile/core/cloud/auth_service.dart';
import 'package:relio_mobile/core/cloud/cloud_models.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/cloud/password_recovery_callback.dart';
import 'package:relio_mobile/core/cloud/password_recovery_guard.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'recovery guard survives recreation until explicit completion or login',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final original = PasswordRecoveryGuard(preferences);
      expect(original.pending, isFalse);
      await original.setPending(true);
      final restored = PasswordRecoveryGuard(
        await SharedPreferences.getInstance(),
      );
      expect(restored.pending, isTrue);
      await restored.setPending(false);
      expect(
        PasswordRecoveryGuard(await SharedPreferences.getInstance()).pending,
        isFalse,
      );
    },
  );

  test(
    'password reset request does not reveal account or change session',
    () async {
      final source = FakeCloudDataSource();
      addTearDown(source.dispose);
      source.createTestIdentity(email: 'qa@example.invalid');
      final auth = CloudAuthService(source);
      await auth.requestPasswordReset(email: ' qa@example.invalid ');
      await auth.requestPasswordReset(email: 'unknown@example.invalid');
      expect(source.passwordResetRequests, 2);
      expect(auth.identity, isNull);
      expect(auth.state, AuthState.guest);
    },
  );

  test('reset is offline gated and requires a real recovery session', () async {
    final source = FakeCloudDataSource();
    addTearDown(source.dispose);
    final auth = CloudAuthService(source);
    await expectLater(
      auth.completePasswordReset(password: 'NewSecret!123'),
      throwsA(isA<CloudException>()),
    );
    source.offline = true;
    await expectLater(
      auth.requestPasswordReset(email: 'qa@example.invalid'),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', 'offline')),
    );
    expect(source.passwordResetRequests, 0);
  });

  test(
    'recovery pauses authenticated operations and changes only target password',
    () async {
      final source = FakeCloudDataSource();
      addTearDown(source.dispose);
      final a = source.createTestIdentity(email: 'a@example.invalid');
      source.createTestIdentity(email: 'b@example.invalid');
      source.simulatePasswordRecovery(a.email);
      await expectLater(
        source.fetchMyProfile(),
        throwsA(isA<CloudException>()),
      );
      final auth = CloudAuthService(source);
      await auth.completePasswordReset(password: 'NewSecret!123');
      expect(auth.state, AuthState.authenticated);
      expect(auth.identity?.userId, a.userId);
      await auth.signOut();
      await expectLater(
        auth.signIn(email: a.email, password: 'password'),
        throwsA(isA<CloudException>()),
      );
      expect(
        (await auth.signIn(email: a.email, password: 'NewSecret!123')).userId,
        a.userId,
      );
      await auth.signOut();
      await auth.signIn(email: 'b@example.invalid', password: 'password');
    },
  );

  test('callback accepts only exact package and recovery endpoint', () {
    final qa = PasswordRecoveryCallback.forEnvironment(RelioEnvironment.test);
    expect(
      PasswordRecoveryCallback.acceptsFor(
        qa.replace(query: 'code=test'),
        RelioEnvironment.test,
      ),
      isTrue,
    );
    for (final uri in [
      PasswordRecoveryCallback.forEnvironment(RelioEnvironment.production),
      Uri.parse('com.relio.mobile.qa://other/'),
      Uri.parse('com.relio.mobile.qa://auth-reset/extra'),
      Uri.parse('https://auth-reset/'),
    ]) {
      expect(
        PasswordRecoveryCallback.acceptsFor(uri, RelioEnvironment.test),
        isFalse,
      );
    }
  });

  test('recovery route takes priority over restored login', () {
    expect(
      authStartupRedirect(
        location: '/home',
        authReady: true,
        hasSession: true,
        passwordRecovery: true,
      ),
      '/reset-password',
    );
    expect(
      authStartupRedirect(
        location: '/reset-password',
        authReady: true,
        hasSession: true,
        passwordRecovery: true,
      ),
      isNull,
    );
  });

  Future<({RelioDependencies dependencies, FakeCloudDataSource cloud})> pump(
    WidgetTester tester,
  ) async {
    final cloud = FakeCloudDataSource();
    cloud.createTestIdentity(email: 'qa@example.invalid');
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(),
      cloudDataSource: cloud,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await dependencies.dispose();
    });
    await dependencies.initialize();
    await tester.pumpWidget(RelioApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    return (dependencies: dependencies, cloud: cloud);
  }

  testWidgets(
    'forgot password button validates email and displays neutral request result',
    (tester) async {
      final setup = await pump(tester);
      await tester.ensureVisible(find.text('เข้าสู่ระบบ'));
      await tester.tap(find.text('เข้าสู่ระบบ'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ลืมรหัสผ่าน?'));
      await tester.tap(find.text('ลืมรหัสผ่าน?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ขอลิงก์กู้รหัสผ่าน'));
      await tester.pumpAndSettle();
      expect(find.text('กรุณากรอกอีเมล'), findsOneWidget);
      expect(setup.cloud.passwordResetRequests, 0);
      await tester.enterText(find.byType(TextFormField), 'qa@example.invalid');
      await tester.tap(find.text('ขอลิงก์กู้รหัสผ่าน'));
      await tester.pumpAndSettle();
      expect(setup.cloud.passwordResetRequests, 1);
      expect(
        find.textContaining('หากมีบัญชีและระบบส่งอีเมลได้'),
        findsOneWidget,
      );
    },
  );

  testWidgets('verified recovery opens password form and blocks mismatch', (
    tester,
  ) async {
    final setup = await pump(tester);
    setup.cloud.simulatePasswordRecovery('qa@example.invalid');
    await tester.pumpAndSettle();
    expect(find.text('ตั้งรหัสผ่านใหม่'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'NewSecret!123');
    await tester.enterText(find.byType(TextFormField).last, 'Different!123');
    await tester.ensureVisible(find.text('บันทึกรหัสผ่านใหม่'));
    await tester.tap(find.text('บันทึกรหัสผ่านใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('รหัสผ่านและการยืนยันรหัสผ่านไม่ตรงกัน'), findsOneWidget);
    expect(setup.cloud.authState, AuthState.passwordRecovery);
    await tester.enterText(find.byType(TextFormField).last, 'NewSecret!123');
    await tester.ensureVisible(find.text('บันทึกรหัสผ่านใหม่'));
    await tester.tap(find.text('บันทึกรหัสผ่านใหม่'));
    await tester.pumpAndSettle();
    expect(setup.cloud.authState, AuthState.authenticated);
    expect(find.text('ตั้งรหัสผ่านใหม่'), findsNothing);
  });
}
