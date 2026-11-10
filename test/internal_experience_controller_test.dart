import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/developer/internal_experience_controller.dart';
import 'package:relio_mobile/core/repositories/local_repositories.dart';

void main() {
  test(
    'Developer Mode and DEMO persist independently and DEMO is cleared on disable',
    () async {
      final database = AppDatabase.memory();
      final settings = RelioRepositories(database).settings;
      final first = InternalExperienceController(settings);
      await first.initialize();

      expect(first.developerModeEnabled, isFalse);
      expect(first.demoEnabled, isFalse);
      await first.setDemoEnabled(true);
      expect(first.demoEnabled, isFalse);

      await first.setDeveloperMode(true);
      expect(first.developerModeEnabled, isTrue);
      expect(first.demoEnabled, isFalse);
      await first.setDemoEnabled(true);
      expect(first.demoEnabled, isTrue);

      final restarted = InternalExperienceController(settings);
      await restarted.initialize();
      expect(restarted.developerModeEnabled, isTrue);
      expect(restarted.demoEnabled, isTrue);

      await restarted.setDeveloperMode(false);
      expect(restarted.developerModeEnabled, isFalse);
      expect(restarted.demoEnabled, isFalse);
      expect(
        await settings.getBool(
          InternalExperienceController.demoModeKey,
          defaultValue: true,
        ),
        isFalse,
      );

      first.dispose();
      restarted.dispose();
      await database.close();
    },
  );

  test(
    'stale DEMO preference is cleared while Developer Mode is off',
    () async {
      final database = AppDatabase.memory();
      final settings = RelioRepositories(database).settings;
      await settings.setBool(
        InternalExperienceController.developerModeKey,
        false,
      );
      await settings.setBool(InternalExperienceController.demoModeKey, true);
      final controller = InternalExperienceController(settings);

      await controller.initialize();
      expect(controller.demoEnabled, isFalse);
      expect(
        await settings.getBool(
          InternalExperienceController.demoModeKey,
          defaultValue: true,
        ),
        isFalse,
      );
      await controller.setDeveloperMode(true);
      expect(controller.demoEnabled, isFalse);

      controller.dispose();
      await database.close();
    },
  );

  test('rapid DEMO ON/OFF/ON leaves the last requested state active', () async {
    final database = AppDatabase.memory();
    final settings = RelioRepositories(database).settings;
    final seedStarted = Completer<void>();
    final releaseFirstSeed = Completer<void>();
    var seeds = 0;
    final controller = InternalExperienceController(
      settings,
      onDemoEnabled: () async {
        seeds++;
        if (seeds == 1) {
          seedStarted.complete();
          await releaseFirstSeed.future;
        }
      },
    );
    await controller.setDeveloperMode(true);

    final firstOn = controller.setDemoEnabled(true);
    await seedStarted.future;
    final off = controller.setDemoEnabled(false);
    final lastOn = controller.setDemoEnabled(true);
    expect(controller.demoEnabled, isTrue);
    releaseFirstSeed.complete();
    await Future.wait([firstOn, off, lastOn]);

    expect(controller.demoEnabled, isTrue);
    expect(
      await settings.getBool(
        InternalExperienceController.demoModeKey,
        defaultValue: false,
      ),
      isTrue,
    );
    expect(seeds, 2);

    controller.dispose();
    await database.close();
  });

  test('a delayed DEMO seed cannot restore the state after OFF', () async {
    final database = AppDatabase.memory();
    final settings = RelioRepositories(database).settings;
    final seedStarted = Completer<void>();
    final finishSeed = Completer<void>();
    final controller = InternalExperienceController(
      settings,
      onDemoEnabled: () async {
        seedStarted.complete();
        await finishSeed.future;
      },
    );
    await controller.setDeveloperMode(true);

    final enabling = controller.setDemoEnabled(true);
    await seedStarted.future;
    final disabling = controller.setDemoEnabled(false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.demoEnabled, isFalse);
    finishSeed.complete();
    await Future.wait([enabling, disabling]);

    expect(controller.demoEnabled, isFalse);
    expect(
      await settings.getBool(
        InternalExperienceController.demoModeKey,
        defaultValue: true,
      ),
      isFalse,
    );

    controller.dispose();
    await database.close();
  });
}
