import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import '../features/auth/loading_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/profile/profile_screens.dart';
import '../features/placeholder/placeholder_screens.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/spike/platform_check_screen.dart';
import 'session.dart';

abstract final class Routes {
  static const timer = '/timer';
  static const reports = '/reports';
  static const projects = '/projects';
  static const team = '/team';
  static const settings = '/settings';
  static const profile = '/settings/profile';
  static const platformCheck = '/settings/platform-check';

  static const loading = '/loading';
  static const welcome = '/welcome';
  static const profileSetup = '/your-name';

  /// Onboarding screens shown outside the shell.
  static const gates = {loading, welcome, profileSetup};
}

/// Where to send the user for [status] when they are at [location], or `null`
/// to stay (spec §4: sign in → profile → app). Organization choice joins in
/// stage 3.
String? sessionRedirect(SessionStatus status, String location) {
  final atGate = Routes.gates.contains(location);
  return switch (status) {
    SessionUnconfigured() => atGate ? Routes.timer : null,
    SessionLoading() => location == Routes.loading ? null : Routes.loading,
    SessionSignedOut() => location == Routes.welcome ? null : Routes.welcome,
    SessionNeedsProfile() =>
      location == Routes.profileSetup ? null : Routes.profileSetup,
    SessionReady() => atGate ? Routes.timer : null,
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(appConfigProvider);
  // The router is built once; session changes only re-run its redirect.
  final session = ValueNotifier<SessionStatus>(ref.read(sessionProvider));
  ref.listen(sessionProvider, (_, next) => session.value = next);
  ref.onDispose(session.dispose);

  final router = GoRouter(
    initialLocation: Routes.timer,
    refreshListenable: session,
    redirect: (context, state) =>
        sessionRedirect(session.value, state.matchedLocation),
    routes: [
      GoRoute(path: Routes.loading, builder: (_, _) => const LoadingScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: Routes.profileSetup,
        builder: (_, _) => const ProfileSetupScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.timer,
                builder: (_, _) => const TimerPlaceholder(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.reports,
                builder: (_, _) => const ReportsPlaceholder(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.projects,
                builder: (_, _) => const ProjectsPlaceholder(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.team,
                builder: (_, _) => const TeamPlaceholder(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (_, _) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'profile',
                    builder: (_, _) => const EditProfileScreen(),
                  ),
                  if (config.isDev)
                    GoRoute(
                      path: 'platform-check',
                      builder: (_, _) => const PlatformCheckScreen(),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
