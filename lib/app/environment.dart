enum RelioEnvironment { development, test, production }

abstract final class RelioBuildInfo {
  static const versionName = String.fromEnvironment(
    'RELIO_VERSION',
    defaultValue: '0.8.5',
  );
  static const buildNumber = String.fromEnvironment(
    'RELIO_BUILD',
    defaultValue: '11',
  );
  static const environmentName = String.fromEnvironment(
    'RELIO_ENV',
    defaultValue: 'development',
  );

  static RelioEnvironment get environment => switch (environmentName) {
    'test' => RelioEnvironment.test,
    'production' => RelioEnvironment.production,
    _ => RelioEnvironment.development,
  };

  static bool get isTest => environment == RelioEnvironment.test;

  // Production can disable developer diagnostics from one environment gate.
  static bool get developerDiagnosticsEnabled =>
      environment != RelioEnvironment.production;

  static String get appName => isTest ? 'RELIO Test' : 'RELIO';

  static String get environmentLabel => switch (environment) {
    RelioEnvironment.development => 'Development',
    RelioEnvironment.test => 'Test',
    RelioEnvironment.production => 'Production',
  };

  static String get aboutLabel =>
      '$appName • Version $versionName • Build $buildNumber'
      '${isTest ? ' • Environment: TEST' : ''}';

  static String get buildLabel => '$versionName+$buildNumber';
}
