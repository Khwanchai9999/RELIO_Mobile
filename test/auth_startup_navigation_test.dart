import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/router.dart';

void main() {
  group('authStartupRedirect', () {
    test('waits on startup until auth restoration completes', () {
      expect(
        authStartupRedirect(
          location: '/startup',
          authReady: false,
          hasSession: false,
        ),
        isNull,
      );
    });

    test('restored session enters the authenticated app', () {
      expect(
        authStartupRedirect(
          location: '/startup',
          authReady: true,
          hasSession: true,
        ),
        '/home',
      );
    });

    test('missing session opens Welcome', () {
      expect(
        authStartupRedirect(
          location: '/startup',
          authReady: true,
          hasSession: false,
        ),
        '/welcome',
      );
    });

    test('does not redirect an in-progress login or normal route', () {
      expect(
        authStartupRedirect(
          location: '/login',
          authReady: true,
          hasSession: true,
        ),
        isNull,
      );
    });
  });
}
