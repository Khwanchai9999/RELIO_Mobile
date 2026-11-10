import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/app/router.dart';
import 'package:relio_mobile/core/cloud/fake_cloud_data_source.dart';
import 'package:relio_mobile/core/connectivity/qa_internet_simulator.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('relio-guest-mode-');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  RelioDependencies createDependencies() {
    final simulator = QaInternetSimulator.forTesting()
      ..setSimulatedOffline(true);
    return RelioDependencies(
      database: AppDatabase.withExecutor(
        NativeDatabase(File('${directory.path}/relio.sqlite')),
      ),
      cloudDataSource: FakeCloudDataSource(),
      internetSimulator: simulator,
      useMockTransport: true,
      androidPlatformOverride: false,
    );
  }

  test(
    'fresh installation remains at Welcome until the user selects Guest',
    () async {
      final dependencies = createDependencies();
      await dependencies.initializeAuth();

      expect(dependencies.hasSelectedUserSession, isFalse);
      expect(
        authStartupRedirect(
          location: '/startup',
          authReady: true,
          hasSession: dependencies.hasSelectedUserSession,
        ),
        '/welcome',
      );
      await dependencies.dispose();
    },
  );

  test(
    // เปิด SQLite เดิมหลายรอบเพื่อตรวจว่า Guest กลับเข้าได้หลัง restart และการออกไม่ลบ principal เดิม
    'Guest mode and its stable principal survive restart and explicit exit',
    () async {
      final firstLaunch = createDependencies();
      await firstLaunch.initializeAuth();
      await firstLaunch.resumeGuestMode();
      final guestPrincipal = await firstLaunch.repositories.profiles
          .guestPrincipal();
      expect(firstLaunch.hasSelectedUserSession, isTrue);
      await firstLaunch.dispose();

      final coldLaunch = createDependencies();
      await coldLaunch.initializeAuth();
      expect(coldLaunch.hasSelectedUserSession, isTrue);
      expect(
        await coldLaunch.repositories.profiles.guestPrincipal(),
        guestPrincipal,
      );
      expect(
        authStartupRedirect(
          location: '/startup',
          authReady: true,
          hasSession: coldLaunch.hasSelectedUserSession,
        ),
        '/home',
      );

      expect(await coldLaunch.exitGuestMode(), isTrue);
      expect(coldLaunch.hasSelectedUserSession, isFalse);
      await coldLaunch.dispose();

      final afterExit = createDependencies();
      await afterExit.initializeAuth();
      expect(afterExit.hasSelectedUserSession, isFalse);
      expect(
        await afterExit.repositories.profiles.guestPrincipal(),
        guestPrincipal,
      );
      await afterExit.dispose();
    },
  );
}
