import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../app/session.dart';
import '../../data/providers.dart';
import '../org/organization_choice_screen.dart';

/// Responsive shell: bottom navigation on phones, `NavigationRail` from
/// 900 px (spec §5). The header carries the organization switcher with the
/// role badge; the sync status joins in stage 5.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final org = ref.watch(currentOrgProvider).value;
    final destinations = [
      (Icons.timer_outlined, Icons.timer, l10n.navTimer),
      (Icons.bar_chart_outlined, Icons.bar_chart, l10n.navReports),
      (Icons.folder_outlined, Icons.folder, l10n.navProjects),
      (Icons.groups_outlined, Icons.groups, l10n.navTeam),
      (Icons.settings_outlined, Icons.settings, l10n.navSettings),
    ];

    void go(int i) =>
        shell.goBranch(i, initialLocation: i == shell.currentIndex);

    final body = Column(
      children: [
        if (!firebaseReady) const _NotConfiguredBanner(),
        if (org != null && !org.status.writable)
          MaterialBanner(
            content: Text(l10n.orgReadOnlyBanner),
            leading: const Icon(Icons.lock_outline),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(child: shell),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Breakpoints.expanded;
        return Scaffold(
          appBar: AppBar(
            title: firebaseReady
                ? const OrgSwitcher()
                : Text(l10n.noOrganization),
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: shell.currentIndex,
                      onDestinationSelected: go,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final (icon, selected, label) in destinations)
                          NavigationRailDestination(
                            icon: Icon(icon),
                            selectedIcon: Icon(selected),
                            label: Text(label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: go,
                  destinations: [
                    for (final (icon, selected, label) in destinations)
                      NavigationDestination(
                        icon: Icon(icon),
                        selectedIcon: Icon(selected),
                        label: label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _NotConfiguredBanner extends StatelessWidget {
  const _NotConfiguredBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.l10n.firebaseNotConfiguredBanner,
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
