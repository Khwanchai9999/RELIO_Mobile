import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/feature_flags/feature_flags.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';

void main() {
  late AppDatabase database;
  late RelioSettingsRepository settings;

  setUp(() {
    database = AppDatabase.memory();
    settings = RelioSettingsRepository(database);
  });

  tearDown(() => database.close());

  FeatureFlagController controller({required bool qa}) => FeatureFlagController(
    repository: FeatureFlagRepository(settings),
    allowLocalOverrides: qa,
  );

  test(
    'build defaults preserve all stable features and route needs map',
    () async {
      final flags = controller(qa: true);
      await flags.initialize();

      expect(flags.isEnabled(RelioFeatureFlag.nearbyMapUi), isTrue);
      expect(flags.isEnabled(RelioFeatureFlag.peerBatteryUi), isTrue);
      expect(flags.isEnabled(RelioFeatureFlag.routePreview), isTrue);
    },
  );

  test('QA overrides persist and reset only feature keys', () async {
    await settings.setBool('qa_simulated_internet_offline', true);
    final flags = controller(qa: true);
    await flags.initialize();
    await flags.setOverride(RelioFeatureFlag.peerBatteryUi, false);
    await flags.setOverride(RelioFeatureFlag.routePreview, false);

    final restored = controller(qa: true);
    await restored.initialize();
    expect(restored.isEnabled(RelioFeatureFlag.peerBatteryUi), isFalse);
    expect(restored.isEnabled(RelioFeatureFlag.routePreview), isFalse);

    await restored.resetOverrides();
    expect(restored.isEnabled(RelioFeatureFlag.peerBatteryUi), isTrue);
    expect(
      await settings.getBool(
        'qa_simulated_internet_offline',
        defaultValue: false,
      ),
      isTrue,
    );
  });

  test(
    'map off suppresses route without changing its saved override',
    () async {
      final flags = controller(qa: true);
      await flags.initialize();
      await flags.setOverride(RelioFeatureFlag.routePreview, true);
      await flags.setOverride(RelioFeatureFlag.nearbyMapUi, false);

      expect(flags.localOverride(RelioFeatureFlag.routePreview), isTrue);
      expect(flags.configuredValue(RelioFeatureFlag.routePreview), isTrue);
      expect(flags.isEnabled(RelioFeatureFlag.routePreview), isFalse);

      await flags.setOverride(RelioFeatureFlag.nearbyMapUi, true);
      expect(flags.isEnabled(RelioFeatureFlag.routePreview), isTrue);
    },
  );

  test('PROD ignores saved QA overrides and cannot mutate them', () async {
    await settings.setBool(RelioFeatureFlag.nearbyMapUi.storageKey, false);
    final flags = controller(qa: false);
    await flags.initialize();

    expect(flags.isEnabled(RelioFeatureFlag.nearbyMapUi), isTrue);
    expect(flags.localOverride(RelioFeatureFlag.nearbyMapUi), isNull);
    await flags.setOverride(RelioFeatureFlag.nearbyMapUi, false);
    expect(
      await settings.getNullableBool(RelioFeatureFlag.nearbyMapUi.storageKey),
      isFalse,
    );
  });
}
