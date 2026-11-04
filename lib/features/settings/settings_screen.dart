import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/brand.dart';
import '../../app/l10n.dart';
import '../../app/router.dart';
import '../../data/providers.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final config = ref.watch(appConfigProvider);
    final version = ref.watch(_packageInfoProvider).value;

    Future<void> open(String url) =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

    return ListView(
      children: [
        _Header(l10n.settingsAbout),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.appTitle),
          subtitle: Text(
            [
              if (version != null)
                l10n.settingsVersion(
                  '${version.version}+${version.buildNumber}',
                ),
              if (config.isDev) l10n.flavorDev,
            ].join(' · '),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: Text(l10n.settingsSourceCode),
          onTap: () => open(Brand.repoUrl),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(l10n.settingsPrivacyPolicy),
          onTap: () => open(Brand.privacyPolicyUrl),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(l10n.settingsTerms),
          onTap: () => open(Brand.termsUrl),
        ),
        if (config.isDev) ...[
          _Header(l10n.settingsDeveloper),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(l10n.settingsPlatformCheck),
            subtitle: Text(l10n.settingsPlatformCheckSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.platformCheck),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}
