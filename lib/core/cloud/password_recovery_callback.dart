import '../../app/environment.dart';

/// แยก callback ตาม package เพื่อไม่ให้ QA รับ session ของ PROD หรือกลับกัน
abstract final class PasswordRecoveryCallback {
  static Uri get redirectUri => forEnvironment(RelioBuildInfo.environment);

  static Uri forEnvironment(RelioEnvironment environment) {
    final suffix = switch (environment) {
      RelioEnvironment.development => '.dev',
      RelioEnvironment.test => '.qa',
      RelioEnvironment.production => '',
    };
    return Uri.parse('com.relio.mobile$suffix://auth-reset/');
  }

  static bool accepts(Uri uri) => acceptsFor(uri, RelioBuildInfo.environment);

  static bool acceptsFor(Uri uri, RelioEnvironment environment) {
    final expected = forEnvironment(environment);
    return uri.scheme == expected.scheme &&
        uri.host == expected.host &&
        uri.path == expected.path &&
        uri.userInfo.isEmpty &&
        !uri.hasPort;
  }
}
