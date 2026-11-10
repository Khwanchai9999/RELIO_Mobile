import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:relio_mobile/core/database/app_database.dart';
import 'package:relio_mobile/core/connectivity/qa_internet_simulator.dart';
import 'package:relio_mobile/core/identity/owner_context.dart';
import 'package:relio_mobile/core/repositories/principal_profile_repository.dart';
import 'package:relio_mobile/core/repositories/profile_avatar_repository.dart';
import 'package:relio_mobile/core/nearby/nearby_transport.dart';
import 'package:relio_mobile/core/relio_dependencies.dart';
import 'package:relio_mobile/features/home/home_screen.dart';
import 'package:relio_mobile/features/profile/profile_screen.dart';
import 'package:relio_mobile/shared/widgets/relio_widgets.dart';

void main() {
  testWidgets(
    'principal avatar uses the same initials and corrupt-image fallback',
    (tester) async {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            themeMode: mode,
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            home: Scaffold(
              body: Column(
                children: [
                  const RelioPrincipalAvatar(name: 'Bob', imagePath: null),
                  const RelioPrincipalAvatar(
                    name: 'Bob',
                    imagePath: 'missing.png',
                  ),
                  const RelioPrincipalAvatar(name: '', imagePath: null),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('B'), findsOneWidget);
        expect(find.byIcon(Icons.person_rounded), findsOneWidget);
        final image = tester.widget<Image>(find.byType(Image));
        final fallback = image.errorBuilder!(
          tester.element(find.byType(Image)),
          const FormatException('corrupt image'),
          StackTrace.empty,
        );
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: fallback)));
        expect(find.text('B'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'Home and Profile render the same principal photo and no-photo fallback',
    (tester) async {
      final db = AppDatabase.memory();
      final avatars = _StubAvatarRepository(db);
      final dependencies = RelioDependencies(
        database: db,
        transport: MockNearbyTransport(autoAcknowledge: false),
        internetSimulator: QaInternetSimulator.forTesting(bootOffline: true),
        profileAvatarRepository: avatars,
      );
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('relio-avatar-parity-'),
      ))!;
      final image = (await tester.runAsync(
        () => File(
          'assets/branding/relio-logo-master.png',
        ).copy('${dir.path}${Platform.pathSeparator}avatar.png'),
      ))!;
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(path: '/settings', builder: (_, _) => const Scaffold()),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await dependencies.dispose();
        await dir.delete(recursive: true);
      });
      await dependencies.initialize();
      await dependencies.repositories.profiles.setName('Bob');
      avatars.path = image.path;
      await tester.pumpWidget(
        RelioDependencyScope(
          dependencies: dependencies,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final homeAvatar = tester.widget<RelioPrincipalAvatar>(
        find.byType(RelioPrincipalAvatar),
      );
      expect(homeAvatar.imagePath, image.path);
      router.go('/profile');
      await tester.pumpAndSettle();
      final profileAvatar = tester.widget<RelioPrincipalAvatar>(
        find.byType(RelioPrincipalAvatar),
      );
      expect(profileAvatar.imagePath, homeAvatar.imagePath);
      avatars.path = null;
      await dependencies.repositories.profiles.setName('Bob changed');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RelioPrincipalAvatar>(find.byType(RelioPrincipalAvatar))
            .imagePath,
        isNull,
      );
      expect(find.text('B'), findsOneWidget);
      router.go('/home');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<RelioPrincipalAvatar>(find.byType(RelioPrincipalAvatar))
            .imagePath,
        isNull,
      );
      expect(find.text('B'), findsOneWidget);
    },
  );

  test(
    'avatar paths remain principal scoped across Guest, A, B and A',
    () async {
      final db = AppDatabase.memory();
      String? active;
      final owners = OwnerContext(() => active);
      final profiles = PrincipalProfileRepository(db, owners);
      final dir = await Directory.systemTemp.createTemp('relio-avatar-owners-');
      final guest = File('${dir.path}${Platform.pathSeparator}guest.png');
      final accountA = File('${dir.path}${Platform.pathSeparator}a.png');
      final accountB = File('${dir.path}${Platform.pathSeparator}b.png');
      await guest.writeAsBytes([1]);
      await accountA.writeAsBytes([1]);
      await accountB.writeAsBytes([1]);
      final avatars = ProfileAvatarRepository(db, profiles: profiles);
      addTearDown(() async {
        profiles.dispose();
        await owners.dispose();
        await db.close();
        await dir.delete(recursive: true);
      });
      await profiles.setAvatar(guest.path, owners.capture());
      active = 'a';
      await profiles.setAvatar(accountA.path, owners.capture());
      active = 'b';
      await profiles.setAvatar(accountB.path, owners.capture());
      expect(await avatars.getAvatarPath(), accountB.path);
      active = 'a';
      expect(await avatars.getAvatarPath(), accountA.path);
      active = null;
      expect(await avatars.getAvatarPath(), guest.path);
    },
  );
}

class _StubAvatarRepository extends ProfileAvatarRepository {
  _StubAvatarRepository(super.db);

  String? path;

  @override
  Future<String?> getAvatarPath() async => path;
}
