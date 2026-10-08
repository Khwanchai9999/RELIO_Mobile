import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/core/cloud/cloud_error_mapper.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/auth/auth_screens.dart';
import 'package:relio_mobile/features/auth/register_validation.dart';

void main() {
  group('Register email validation', () {
    test('rejects empty and malformed email addresses', () {
      expect(RegisterValidation.emailError('  '), 'กรุณากรอกอีเมล');
      for (final email in [
        'khwanchai',
        'khwanchai@',
        '@gmail.com',
        'khwanchai gmail.com',
      ]) {
        expect(
          RegisterValidation.emailError(email),
          'รูปแบบอีเมลไม่ถูกต้อง',
          reason: email,
        );
      }
    });

    test('accepts normal Gmail and .ac.th addresses', () {
      expect(RegisterValidation.emailError('khwanchai@gmail.com'), isNull);
      expect(RegisterValidation.emailError('student@rmutt.ac.th'), isNull);
    });

    test('trims only outer email whitespace', () {
      const input = '  student@rmutt.ac.th  ';
      expect(RegisterValidation.emailError(input), isNull);
      expect(RegisterValidation.normalizeEmail(input), 'student@rmutt.ac.th');
    });
  });

  group('Register password validation', () {
    test('reports each password requirement independently', () {
      expect(RegisterValidation.isPasswordValid('Abc1!'), isFalse);
      expect(RegisterValidation.isPasswordValid('abcdefg1!'), isFalse);
      expect(RegisterValidation.isPasswordValid('ABCDEFG1!'), isFalse);
      expect(RegisterValidation.isPasswordValid('Abcdefgh!'), isFalse);
      expect(RegisterValidation.isPasswordValid('Abcdefg1'), isFalse);
      expect(RegisterValidation.isPasswordValid(' Abc1234'), isFalse);
      expect(RegisterValidation.isPasswordValid('Abcd123!'), isTrue);
      expect(RegisterValidation.isPasswordValid('Abcd123_'), isTrue);
    });

    test('does not trim the password value', () {
      expect(RegisterValidation.isPasswordValid('Abc123!'), isFalse);
      expect(RegisterValidation.isPasswordValid(' Abc123!'), isTrue);
    });
  });

  group('Confirm password validation', () {
    test('rejects empty and mismatched confirmation', () {
      expect(
        RegisterValidation.confirmationError('Abcd123!', ''),
        'กรุณายืนยันรหัสผ่าน',
      );
      expect(
        RegisterValidation.confirmationError('Abcd123!', 'Abcd123?'),
        'รหัสผ่านและการยืนยันรหัสผ่านไม่ตรงกัน',
      );
    });

    test('accepts a matching valid password', () {
      const password = 'Abcd123!';
      expect(RegisterValidation.isPasswordValid(password), isTrue);
      expect(RegisterValidation.confirmationError(password, password), isNull);
    });
  });

  test('maps only verified duplicate-email Auth codes to a safe message', () {
    for (final code in ['email_exists', 'user_already_exists']) {
      final mapped = CloudErrorMapper.map(
        AuthException('raw backend details', statusCode: '422', code: code),
      );
      expect(mapped.message, 'อีเมลนี้ถูกใช้งานแล้ว');
      expect(mapped.message, isNot(contains('raw backend')));
    }

    final unrelated = CloudErrorMapper.map(
      const AuthException('raw backend details', statusCode: '422'),
    );
    expect(unrelated.message, isNot('อีเมลนี้ถูกใช้งานแล้ว'));
    expect(unrelated.message, isNot(contains('raw backend')));
  });

  test('maps signup server errors separately from connectivity failures', () {
    final offline = CloudErrorMapper.map(
      AuthRetryableFetchException(message: 'private transport detail'),
    );
    expect(offline.code, 'offline');
    expect(offline.message, 'Cloud ไม่พร้อมใช้งาน');
    expect(offline.message, isNot(contains('private')));

    final weakPassword = CloudErrorMapper.map(
      const AuthException('private backend detail', code: 'weak_password'),
    );
    expect(weakPassword.code, 'weakPassword');
    expect(weakPassword.message, 'รหัสผ่านไม่ผ่านข้อกำหนดของระบบ');

    final disabled = CloudErrorMapper.map(
      const AuthException('private backend detail', code: 'signup_disabled'),
    );
    expect(disabled.code, 'signupDisabled');
    expect(disabled.message, 'ขณะนี้ระบบปิดรับสมัครบัญชีใหม่');

    final rateLimited = CloudErrorMapper.map(
      const AuthException(
        'private backend detail',
        code: 'over_email_send_rate_limit',
      ),
    );
    expect(rateLimited.code, 'emailRateLimit');
    expect(
      rateLimited.message,
      'ส่งอีเมลยืนยันถี่เกินไป กรุณารอสักครู่แล้วลองใหม่',
    );

    final invalidEmail = CloudErrorMapper.map(
      const AuthException(
        'private backend detail',
        code: 'email_address_invalid',
      ),
    );
    expect(invalidEmail.code, 'invalidEmail');
    expect(invalidEmail.message, contains('อีเมลนี้ใช้สมัครไม่ได้'));

    final emailDelivery = CloudErrorMapper.map(
      const AuthException(
        'private backend detail',
        code: 'email_address_not_authorized',
      ),
    );
    expect(emailDelivery.code, 'emailDeliveryUnavailable');
    expect(emailDelivery.message, contains('ส่งอีเมลยืนยัน'));
  });

  testWidgets('password checklist updates as the user types', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));

    expect(find.text('อย่างน้อย 8 ตัวอักษร'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(5));

    await tester.enterText(find.byType(TextFormField).at(2), 'Abcd123!');
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsNWidgets(5));
    expect(find.byType(TextFormField).at(3), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText).at(2)).obscureText,
      isTrue,
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText).at(3)).obscureText,
      isTrue,
    );
  });

  testWidgets('valid registration reaches the app permission step', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final cloud = FakeCloudDataSource();
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      cloudDataSource: cloud,
      useMockTransport: true,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await dependencies.dispose();
    });
    await dependencies.initialize();
    await tester.pumpWidget(RelioApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('เข้าสู่ระบบ'));
    await tester.tap(find.text('เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยังไม่มีบัญชี? สร้างบัญชีใหม่'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Demo User');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'demo@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'RelioDemo123!');
    await tester.enterText(find.byType(TextFormField).at(3), 'RelioDemo123!');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('สร้างบัญชี'));
    await tester.tap(find.text('สร้างบัญชี'));
    await tester.pumpAndSettle();

    expect(cloud.currentIdentity?.email, 'demo@example.com');
    expect(find.text('อนุญาตทั้งหมด'), findsOneWidget);
    expect(find.text('อุปกรณ์ใกล้เคียง'), findsOneWidget);
    expect(find.text('การเชื่อมต่อ Cloud ไม่สำเร็จ'), findsNothing);
  });
}
