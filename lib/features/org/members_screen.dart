import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/l10n.dart';
import '../../app/session.dart';
import '../../core/errors.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import 'organization_choice_screen.dart' show RoleBadge;

final _membersProvider = StreamProvider.family<List<Membership>, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).watchMembers(orgId),
);

final _invitesProvider = StreamProvider.family<List<Invite>, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).watchPendingInvites(orgId),
);

/// Members and invites for admins (spec §5.6). Role changes, disabling and
/// removing members come in stage 7.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider);
    if (session is! SessionReady || !session.membership.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.membersTitle)),
        body: Center(child: Text(l10n.errorNotAdmin)),
      );
    }
    final orgId = session.orgId;
    final members = ref.watch(_membersProvider(orgId)).value ?? const [];
    final invites = ref.watch(_invitesProvider(orgId)).value ?? const [];
    final sorted = [...members]
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.membersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _invite(context, ref, orgId),
        icon: const Icon(Icons.person_add_alt),
        label: Text(l10n.inviteButton),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          _Header(l10n.invitesSection(invites.length)),
          if (invites.isEmpty) ListTile(title: Text(l10n.invitesEmpty)),
          for (final i in invites)
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text(i.email),
              subtitle: Text(
                '${l10n.role(i.role)} · '
                '${i.isExpired(now) ? l10n.inviteExpired : l10n.inviteExpires(date.format(i.expiresAt))}',
              ),
              trailing: Wrap(
                children: [
                  TextButton(
                    onPressed: () => _resend(context, ref, orgId, i),
                    child: Text(l10n.inviteResend),
                  ),
                  TextButton(
                    onPressed: () => _revoke(context, ref, orgId, i),
                    child: Text(l10n.inviteRevoke),
                  ),
                ],
              ),
            ),
          _Header(l10n.membersSection(members.length)),
          for (final m in sorted)
            ListTile(
              leading: CircleAvatar(
                child: Text(
                  m.firstName.isEmpty ? '?' : m.firstName.characters.first,
                ),
              ),
              title: Text(
                m.uid == session.user.uid
                    ? '${m.displayName} (${l10n.memberYou})'
                    : m.displayName,
              ),
              subtitle: Text(
                [m.email, if (!m.isActive) l10n.memberDisabled].join(' · '),
              ),
              trailing: RoleBadge(role: m.role),
            ),
        ],
      ),
    );
  }

  Future<void> _invite(
    BuildContext context,
    WidgetRef ref,
    String orgId,
  ) async {
    final result = await showDialog<(String, InviteCode)>(
      context: context,
      builder: (_) => _InviteDialog(orgId: orgId),
    );
    if (result != null && context.mounted) {
      await _showCode(context, result.$1, result.$2);
    }
  }

  Future<void> _resend(
    BuildContext context,
    WidgetRef ref,
    String orgId,
    Invite invite,
  ) async {
    try {
      final code = await ref
          .read(orgRepositoryProvider)
          .resendInvite(orgId: orgId, inviteId: invite.id);
      if (context.mounted) await _showCode(context, invite.email, code);
    } catch (e) {
      if (context.mounted) _snack(context, context.l10n.error(e));
    }
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    String orgId,
    Invite invite,
  ) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.inviteRevokeConfirm(invite.email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.inviteRevoke),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(orgRepositoryProvider)
          .revokeInvite(orgId: orgId, inviteId: invite.id);
      if (context.mounted) _snack(context, l10n.inviteRevoked);
    } catch (e) {
      if (context.mounted) _snack(context, l10n.error(e));
    }
  }

  static void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  static Future<void> _showCode(
    BuildContext context,
    String email,
    InviteCode code,
  ) {
    final l10n = context.l10n;
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .format(code.expiresAt.toLocal());
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.inviteCreatedTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              code.code,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.inviteCreatedBody(email, date)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code.code));
              if (context.mounted) _snack(context, l10n.inviteCopied);
            },
            child: Text(l10n.inviteCopy),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.orgId});

  final String orgId;

  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  OrgRole _role = OrgRole.employee;
  bool _busy = false;
  Object? _error;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _email.text.trim().toLowerCase();
    try {
      final code = await ref
          .read(orgRepositoryProvider)
          .createInvite(orgId: widget.orgId, email: email, role: _role);
      if (mounted) Navigator.pop(context, (email, code));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.inviteTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(labelText: l10n.inviteEmail),
              validator: (v) => _emailPattern.hasMatch((v ?? '').trim())
                  ? null
                  : l10n.inviteEmailInvalid,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<OrgRole>(
              initialValue: _role,
              decoration: InputDecoration(labelText: l10n.inviteRole),
              items: [
                for (final r in [OrgRole.employee, OrgRole.admin])
                  DropdownMenuItem(value: r, child: Text(l10n.role(r))),
              ],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.error(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.inviteSend),
        ),
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
