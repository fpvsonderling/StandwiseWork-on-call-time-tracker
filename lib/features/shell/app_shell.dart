import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../app/session.dart';
import '../../app/updates.dart';
import '../../app/work_state.dart';
import '../../data/sync.dart';
import '../../data/providers.dart';
import '../org/organization_choice_screen.dart';

/// Responsive shell: bottom navigation on phones, `NavigationRail` from
/// 900 px (spec §5). The header carries the organization switcher with the
/// role badge, and the sync status (Saved / Saving… / Offline).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final firebaseReady = ref.watch(firebaseReadyProvider);
    final org = ref.watch(currentOrgProvider).value;
    ref.listen(writeErrorsProvider, (_, next) {
      final e = next.value;
      if (e == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.writeRejected(l10n.error(e)))),
        );
    });
    // Team is for admins and the owner (spec §5); branch 3 stays in the
    // router, employees just don't get a button for it.
    final showTeam = ref.watch(workContextProvider)?.isAdmin ?? !firebaseReady;
    final all = [
      (0, Icons.timer_outlined, Icons.timer, l10n.navTimer),
      (1, Icons.bar_chart_outlined, Icons.bar_chart, l10n.navReports),
      (2, Icons.folder_outlined, Icons.folder, l10n.navProjects),
      (3, Icons.groups_outlined, Icons.groups, l10n.navTeam),
      (4, Icons.settings_outlined, Icons.settings, l10n.navSettings),
    ];
    final destinations = [
      for (final d in all)
        if (d.$1 != 3 || showTeam) d,
    ];
    final selected = destinations
        .indexWhere((d) => d.$1 == shell.currentIndex)
        .clamp(0, destinations.length - 1);

    void go(int i) {
      final branch = destinations[i].$1;
      shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
    }

    final update = ref.watch(availableUpdateProvider).value;
    final showUpdate = update != null && !ref.watch(updateDismissedProvider);

    final body = Column(
      children: [
        if (!firebaseReady) const _NotConfiguredBanner(),
        if (showUpdate)
          MaterialBanner(
            content: Text(l10n.updateAvailable(update.version)),
            leading: const Icon(Icons.system_update_alt),
            actions: [
              TextButton(
                onPressed: () =>
                    ref.read(updateDismissedProvider.notifier).dismiss(),
                child: Text(l10n.updateLater),
              ),
              FilledButton(
                onPressed: () =>
                    launchUrl(update.url, mode: LaunchMode.externalApplication),
                child: Text(l10n.updateDownload),
              ),
            ],
          ),
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
            actions: [
              if (firebaseReady) _SyncIndicator(showLabel: wide),
              const SizedBox(width: 8),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: selected,
                      onDestinationSelected: go,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final (_, icon, selectedIcon, label)
                            in destinations)
                          NavigationRailDestination(
                            icon: Icon(icon),
                            selectedIcon: Icon(selectedIcon),
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
                  selectedIndex: selected,
                  onDestinationSelected: go,
                  destinations: [
                    for (final (_, icon, selectedIcon, label) in destinations)
                      NavigationDestination(
                        icon: Icon(icon),
                        selectedIcon: Icon(selectedIcon),
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

/// Saved / Saving… / Offline: changes will sync (spec §5, §8).
class _SyncIndicator extends ConsumerWidget {
  const _SyncIndicator({required this.showLabel});

  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // The timer listener reports whether Firestore is serving from cache.
    ref.watch(timerProvider);
    final state = ref.watch(syncStateProvider).value ?? SyncState.saved;
    final scheme = Theme.of(context).colorScheme;
    final (icon, text, color) = switch (state) {
      SyncState.saved => (
        Icons.cloud_done_outlined,
        l10n.syncSaved,
        scheme.outline,
      ),
      SyncState.saving => (
        Icons.cloud_upload_outlined,
        l10n.syncSaving,
        scheme.primary,
      ),
      SyncState.offline => (
        Icons.cloud_off_outlined,
        l10n.syncOffline,
        scheme.error,
      ),
    };
    return Semantics(
      liveRegion: true,
      label: text,
      child: Tooltip(
        message: text,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Text(text, style: TextStyle(color: color)),
            ],
          ],
        ),
      ),
    );
  }
}
