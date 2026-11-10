import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screens.dart';
import '../features/auth/password_recovery_screens.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/chat/chat_screens.dart';
import '../features/developer/nearby_diagnostics_screen.dart';
import '../features/developer/nearby_transport_test_screen.dart';
import '../features/developer/cloud_diagnostics_screen.dart';
import '../features/developer/internal_tools_screen.dart';
import '../features/developer/relay_diagnostics_screen.dart';
import '../features/diagnostics/system_diagnostics_screen.dart';
import '../features/home/home_screen.dart';
import '../features/flashlight/screen_flashlight_screen.dart';
import '../features/nearby/nearby_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/emergency/emergency_contact_screen.dart';
import '../features/rescue/rescue_screen.dart';
import '../features/rescue/rescue_request_detail_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sos/sos_screens.dart';
import '../features/sos/sos_history_screen.dart';
import '../features/sync/sync_screen.dart';
import 'app.dart';
import 'environment.dart';

// รวม route ไว้จุดเดียว เพื่อให้ทุกหน้ามีเส้นทางและชื่อที่ตรวจสอบได้ตรงกัน
String? authStartupRedirect({
  required String location,
  required bool authReady,
  required bool hasSession,
  bool passwordRecovery = false,
}) {
  if (passwordRecovery && location != '/reset-password') {
    return '/reset-password';
  }
  if (location != '/startup' || !authReady) return null;
  return hasSession ? '/home' : '/welcome';
}

GoRouter createRelioRouter({
  bool Function()? authReady,
  bool Function()? hasSession,
  bool Function()? passwordRecovery,
  bool Function()? developerModeEnabled,
  Listenable? refreshListenable,
}) {
  return GoRouter(
    initialLocation: '/startup',
    refreshListenable: refreshListenable,
    redirect: (_, state) {
      final authRedirect = authStartupRedirect(
        location: state.matchedLocation,
        authReady: authReady?.call() ?? true,
        hasSession: hasSession?.call() ?? false,
        passwordRecovery: passwordRecovery?.call() ?? false,
      );
      if (authRedirect != null) return authRedirect;
      final path = state.matchedLocation;
      final internalRoute =
          path == '/internal-tools' ||
          path == '/diagnostics' ||
          path == '/developer/nearby' ||
          path == '/diagnostics/nearby-transport' ||
          path == '/developer/cloud' ||
          path == '/developer/relay';
      if (internalRoute &&
          RelioBuildInfo.developerDiagnosticsEnabled &&
          !(developerModeEnabled?.call() ?? true)) {
        return '/settings';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/startup',
        builder: (_, _) => Scaffold(
          body: Center(
            child: Semantics(
              label: 'กำลังตรวจสอบบัญชี RELIO',
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      ),
      GoRoute(path: '/', redirect: (_, _) => '/welcome'),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),
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
          GoRoute(
            path: '/nearby',
            builder: (_, state) {
              final query = state.uri.queryParameters;
              final capturedAtMs = int.tryParse(query['capturedAt'] ?? '');
              return NearbyScreen(
                initialTargetId: query['target'],
                initialTargetLatitude: double.tryParse(query['lat'] ?? ''),
                initialTargetLongitude: double.tryParse(query['lon'] ?? ''),
                initialTargetAccuracy: double.tryParse(query['accuracy'] ?? ''),
                initialTargetHistorical: query['historical'] == '1',
                initialTargetSharedLocation: query['shared'] == '1',
                initialTargetCapturedAt: capturedAtMs == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(capturedAtMs),
              );
            },
          ),
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
          GoRoute(
            path: '/sos/history',
            builder: (_, _) => const SOSHistoryScreen(),
          ),
          GoRoute(
            path: '/sos/history/:eventId',
            builder: (_, state) => SOSHistoryDetailScreen(
              eventId: state.pathParameters['eventId']!,
            ),
          ),
          GoRoute(path: '/rescue', builder: (_, _) => const RescueScreen()),
          GoRoute(
            path: '/rescue/request/:deviceId',
            builder: (_, state) => RescueRequestDetailScreen(
              deviceId: state.pathParameters['deviceId']!,
              eventId: state.uri.queryParameters['eventId'],
              order:
                  int.tryParse(state.uri.queryParameters['order'] ?? '') ?? 1,
            ),
          ),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(
            path: '/profile/emergency',
            builder: (_, _) => const EmergencyContactScreen(),
          ),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          GoRoute(
            path: '/settings/theme',
            builder: (_, _) => const ThemeSettingsScreen(),
          ),
          GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
        ],
      ),
      GoRoute(
        path: '/screen-flashlight',
        builder: (_, _) => const ScreenFlashlightScreen(),
      ),
      if (RelioBuildInfo.developerDiagnosticsEnabled) ...[
        GoRoute(
          path: '/internal-tools',
          builder: (_, _) => const InternalToolsScreen(),
        ),
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
