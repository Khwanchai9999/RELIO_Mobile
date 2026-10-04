import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screens.dart';
import '../features/chat/chat_screens.dart';
import '../features/developer/nearby_diagnostics_screen.dart';
import '../features/developer/nearby_transport_test_screen.dart';
import '../features/developer/cloud_diagnostics_screen.dart';
import '../features/developer/relay_diagnostics_screen.dart';
import '../features/diagnostics/system_diagnostics_screen.dart';
import '../features/home/home_screen.dart';
import '../features/nearby/nearby_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/rescue/rescue_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sos/sos_screens.dart';
import '../features/sync/sync_screen.dart';
import 'app.dart';
import 'environment.dart';

GoRouter createRelioRouter() {
  return GoRouter(
    initialLocation: '/welcome',
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/welcome'),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/permissions',
        builder: (_, _) => const PermissionsScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            RelioShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/nearby', builder: (_, _) => const NearbyScreen()),
          GoRoute(path: '/chats', builder: (_, _) => const ChatListScreen()),
          GoRoute(
            path: '/chat/:id',
            builder: (_, state) =>
                ChatRoomScreen(chatId: state.pathParameters['id'] ?? 'somchai'),
          ),
          GoRoute(path: '/sos', builder: (_, _) => const SOSScreen()),
          GoRoute(
            path: '/sos/active',
            builder: (_, _) => const SOSActiveScreen(),
          ),
          GoRoute(
            path: '/sos/received',
            builder: (_, _) => const SOSReceivedScreen(),
          ),
          GoRoute(path: '/rescue', builder: (_, _) => const RescueScreen()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          GoRoute(
            path: '/settings/theme',
            builder: (_, _) => const ThemeSettingsScreen(),
          ),
          GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
        ],
      ),
      if (RelioBuildInfo.developerDiagnosticsEnabled) ...[
        GoRoute(
          path: '/diagnostics',
          builder: (_, _) => const SystemDiagnosticsScreen(),
        ),
        GoRoute(
          path: '/developer/nearby',
          builder: (_, _) => const NearbyDiagnosticsScreen(),
        ),
        GoRoute(
          path: '/diagnostics/nearby-transport',
          builder: (_, _) => const NearbyTransportTestScreen(),
        ),
        GoRoute(
          path: '/developer/cloud',
          builder: (_, _) => const CloudDiagnosticsScreen(),
        ),
        GoRoute(
          path: '/developer/relay',
          builder: (_, _) => const RelayDiagnosticsScreen(),
        ),
      ],
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => context.go('/home'),
          child: const Text('กลับหน้าหลัก'),
        ),
      ),
    ),
  );
}
