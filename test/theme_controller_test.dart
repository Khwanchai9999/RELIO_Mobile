import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:relio_mobile/app/app.dart';
import 'package:relio_mobile/app/theme/relio_theme.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';

class _MemoryThemeStore implements RelioThemePreferenceStore {
  _MemoryThemeStore([this.value]);

  String? value;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    writes++;
    this.value = value;
  }
}

class _UnavailableThemeStore implements RelioThemePreferenceStore {
  @override
  Future<String?> read() async => throw StateError('preference unavailable');

  @override
  Future<void> write(String value) async =>
      throw StateError('preference unavailable');
}

void main() {
  group('RelioThemeController', () {
    test('defaults to system and unknown values fall back to system', () async {
      final defaultController = RelioThemeController(
        store: _MemoryThemeStore(),
      );
      await defaultController.load();
      expect(defaultController.mode, ThemeMode.system);

      final unknownController = RelioThemeController(
        store: _MemoryThemeStore('corrupted-value'),
      );
      await unknownController.load();
      expect(unknownController.mode, ThemeMode.system);
    });

    test(
      'preference read failure falls back without blocking app startup',
      () async {
        final controller = RelioThemeController(
          store: _UnavailableThemeStore(),
        );

        await controller.load();

        expect(controller.isLoaded, isTrue);
        expect(controller.mode, ThemeMode.system);
      },
    );

    test('loads and saves all supported modes using stable values', () async {
      for (final entry in <ThemeMode, String>{
        ThemeMode.light: 'light',
        ThemeMode.dark: 'dark',
        ThemeMode.system: 'system',
      }.entries) {
        final store = _MemoryThemeStore(entry.value);
        final controller = RelioThemeController(store: store);
        await controller.load();
        expect(controller.mode, entry.key);

        final nextMode = entry.key == ThemeMode.dark
            ? ThemeMode.light
            : ThemeMode.dark;
        await controller.setMode(nextMode);
        expect(controller.mode, nextMode);
        expect(store.value, nextMode.name);
        expect(store.writes, 1);
      }
    });

    test(
      'notifies once for a changed mode and ignores duplicate mode writes',
      () async {
        final store = _MemoryThemeStore('light');
        final controller = RelioThemeController(store: store);
        var notifications = 0;
        controller.addListener(() => notifications++);

        await controller.load();
        notifications = 0;
        await controller.setMode(ThemeMode.dark);
        await controller.setMode(ThemeMode.dark);

        expect(notifications, 1);
        expect(store.writes, 1);
      },
    );

    test('recreating the controller restores the persisted mode', () async {
      final store = _MemoryThemeStore();
      final first = RelioThemeController(store: store);
      await first.load();
      await first.setMode(ThemeMode.dark);

      final second = RelioThemeController(store: store);
      await second.load();
      expect(second.mode, ThemeMode.dark);

      await second.setMode(ThemeMode.light);
      final third = RelioThemeController(store: store);
      await third.load();
      expect(third.mode, ThemeMode.light);

      await third.setMode(ThemeMode.system);
      final fourth = RelioThemeController(store: store);
      await fourth.load();
      expect(fourth.mode, ThemeMode.system);
    });
  });

  testWidgets('root MaterialApp binds its live theme mode', (tester) async {
    final dependencies = RelioDependencies(
      database: AppDatabase.memory(),
      transport: MockNearbyTransport(autoAcknowledge: false),
    );
    final controller = RelioThemeController(store: _MemoryThemeStore('light'));
    await controller.load();
    await dependencies.initialize();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await dependencies.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      RelioApp(dependencies: dependencies, themeController: controller),
    );
    await tester.pumpAndSettle();

    MaterialApp root() => tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(root().themeMode, ThemeMode.light);
    await controller.setMode(ThemeMode.dark);
    await tester.pump();
    expect(root().themeMode, ThemeMode.dark);

    await controller.setMode(ThemeMode.system);
    await tester.pump();
    expect(root().themeMode, ThemeMode.system);
  });

  testWidgets('ThemeMode.system follows light platform brightness', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    tester.binding.platformDispatcher.clearPlatformBrightnessTestValue();
    await tester.pumpWidget(_systemThemeProbe());
    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('ThemeMode.system follows dark platform brightness', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pumpWidget(_systemThemeProbe());
    expect(find.text('dark'), findsOneWidget);
  });
}

Widget _systemThemeProbe() => MaterialApp(
  theme: RelioTheme.light(),
  darkTheme: RelioTheme.dark(),
  themeMode: ThemeMode.system,
  home: Builder(
    builder: (context) => Text(
      Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light',
    ),
  ),
);
