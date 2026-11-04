import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers.dart';
import '../features/placeholder/placeholder_screens.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/spike/platform_check_screen.dart';

abstract final class Routes {
  static const timer = '/timer';
  static const reports = '/reports';
  static const projects = '/projects';
  static const team = '/team';
  static const settings = '/settings';
  static const platformCheck = '/settings/platform-check';
}

/// App router. Auth, profile and organization redirects are added in stage 2
/// (spec §12); stage 1 opens straight into the shell.
final routerProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(appConfigProvider);
  return GoRouter(
    initialLocation: Routes.timer,
    routes: [
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
});
