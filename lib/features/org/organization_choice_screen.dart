import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n.dart';
import '../../app/router.dart';
import '../../app/session.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';

/// Currencies offered when creating an organization; any ISO code is valid
/// server-side, these cover the expected markets.
const orgCurrencies = [
  'EUR', 'PLN', 'USD', 'GBP', 'CHF', 'CZK', 'SEK', 'NOK', 'DKK', 'HUF', //
  'RON', 'UAH', 'BGN', 'CAD', 'AUD',
];

/// Join with an invite code or create an organization (spec §4.3). Shown
/// after the profile when the user has no organization, and from the
/// switcher ([adding]) to add another one.
class OrganizationChoiceScreen extends ConsumerWidget {
  const OrganizationChoiceScreen({super.key, this.adding = false});

  final bool adding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    void done() {
      // The function already set lastOrgId; the session switches to it.
      if (adding) context.go(Routes.timer);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(adding ? l10n.orgAddTitle : l10n.orgChoiceTitle),
        automaticallyImplyLeading: adding,
        actions: [
          if (!adding)
            TextButton(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              child: Text(l10n.settingsSignOut),
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.orgChoiceIntro, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text(
                  l10n.orgNeedsConnection,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                _JoinCard(onDone: done),
                const SizedBox(height: 16),
                _CreateCard(onDone: done),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinCard extends ConsumerStatefulWidget {
  const _JoinCard({required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<_JoinCard> createState() => _JoinCardState();
}

class _JoinCardState extends ConsumerState<_JoinCard> {
  final _code = TextEditingController();
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(orgRepositoryProvider).acceptInvite(_code.text.trim());
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.orgJoinTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              decoration: InputDecoration(
                labelText: l10n.orgJoinCode,
                hintText: l10n.orgJoinCodeHint,
                errorText: _error == null ? null : l10n.error(_error!),
                errorMaxLines: 3,
              ),
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              inputFormatters: [LengthLimitingTextInputFormatter(16)],
              onSubmitted: (_) => _busy ? null : _join(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _join,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.orgJoinButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateCard extends ConsumerStatefulWidget {
  const _CreateCard({required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<_CreateCard> createState() => _CreateCardState();
}

class _CreateCardState extends ConsumerState<_CreateCard> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _timezone = TextEditingController(text: 'Europe/Warsaw');
  String _currency = 'EUR';
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _name.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(orgRepositoryProvider)
          .createOrganization(
            name: _name.text.trim(),
            currency: _currency,
            timezone: _timezone.text.trim(),
          );
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    String? required(String? v) =>
        (v ?? '').trim().isEmpty ? l10n.fieldRequired : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.orgCreateTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.orgCreateName),
                maxLength: 100,
                textCapitalization: TextCapitalization.words,
                validator: required,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: InputDecoration(labelText: l10n.orgCreateCurrency),
                items: [
                  for (final c in orgCurrencies)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _currency = v ?? _currency),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _timezone,
                decoration: InputDecoration(
                  labelText: l10n.orgCreateTimezone,
                  hintText: l10n.orgCreateTimezoneHint,
                ),
                autocorrect: false,
                validator: required,
              ),
              const SizedBox(height: 8),
              Text(l10n.orgCreateTrial, style: theme.textTheme.bodySmall),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.error(_error!),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _busy ? null : _create,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.orgCreateButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header switcher: organization name and role badge; switches between the
/// user's organizations and opens "create or join" (spec §4.4, §5).
class OrgSwitcher extends ConsumerWidget {
  const OrgSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider);
    if (session is! SessionReady) return Text(l10n.noOrganization);

    // Watch every organization here, not inside the menu builder, so the
    // names are loaded before the menu opens.
    final names = {
      for (final m in session.memberships)
        m.orgId: ref.watch(orgProvider(m.orgId)).value?.name ?? '…',
    };
    String nameOf(String orgId) => names[orgId] ?? '…';

    return PopupMenuButton<String>(
      tooltip: l10n.orgSwitch,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value.isEmpty) {
          context.go(Routes.addOrganization);
        } else if (value != session.orgId) {
          ref
              .read(profileRepositoryProvider)
              .setLastOrg(uid: session.user.uid, orgId: value);
        }
      },
      itemBuilder: (context) => [
        for (final m in session.memberships)
          PopupMenuItem(
            value: m.orgId,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                m.orgId == session.orgId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(nameOf(m.orgId)),
              subtitle: Text(l10n.role(m.role)),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: '',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add),
            title: Text(l10n.orgAddOrJoin),
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(nameOf(session.orgId), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          RoleBadge(role: session.membership.role),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}

class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});

  final OrgRole role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        context.l10n.role(role),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}
