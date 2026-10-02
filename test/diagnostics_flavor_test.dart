import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:relio_mobile/app/environment.dart';
import 'package:relio_mobile/app/router.dart';

void main() {
  test('diagnostic routes are present only in DEV and QA builds', () {
    const expected = bool.fromEnvironment(
      'EXPECT_DIAGNOSTICS',
      defaultValue: true,
    );
    expect(RelioBuildInfo.developerDiagnosticsEnabled, expected);
    final router = createRelioRouter();
    final paths = <String>[];
    void collect(List<RouteBase> routes) {
      for (final route in routes) {
        if (route is GoRoute) paths.add(route.path);
        if (route is ShellRouteBase) collect(route.routes);
      }
    }

    collect(router.configuration.routes);
    expect(paths.contains('/diagnostics'), expected);
    expect(paths.contains('/developer/nearby'), expected);
    router.dispose();
  });
}
