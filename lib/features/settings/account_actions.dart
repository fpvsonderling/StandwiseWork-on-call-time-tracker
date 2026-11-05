import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n.dart';
import '../../app/session.dart';
import '../../app/work_state.dart';
import '../../data/providers.dart';
import '../common/widgets.dart';

/// Runs a server action with a blocking progress dialog.
Future<bool> _withProgress(
  BuildContext context,
  Future<void> Function() action,
) async {
  final l10n = context.l10n;
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    await action();
    navigator.pop();
    return true;
  } catch (e) {
    navigator.pop();
    if (context.mounted) showError(context, l10n.error(e));
    return false;
  }
}

/// Members other than the owner leave the organization in use.
Future<void> leaveOrganizationFlow(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final ctx = ref.read(workContextProvider);
  if (ctx == null) return;
  final org = ref.read(orgProvider(ctx.orgId)).value;
  final ok = await confirm(
    context,
    title: l10n.orgLeaveTitle(org?.name ?? ''),
    body: l10n.orgLeaveBody,
    action: l10n.orgLeave,
  );
  if (!ok || !context.mounted) return;
  await _withProgress(
    context,
    () => ref.read(orgRepositoryProvider).leaveOrganization(ctx.orgId),
  );
}

/// The owner deletes the organization after typing its name.
Future<void> deleteOrganizationFlow(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final ctx = ref.read(workContextProvider);
  if (ctx == null) return;
  final name = ref.read(orgProvider(ctx.orgId)).value?.name ?? '';
  final typed = await showDialog<String>(
    context: context,
    builder: (_) => _TypeToConfirmDialog(
      title: l10n.orgDeleteTitle(name),
      body: l10n.orgDeleteBody,
      expected: name,
      label: l10n.orgDeleteTypeName,
      action: l10n.delete,
    ),
  );
  if (typed == null || !context.mounted) return;
  await _withProgress(
    context,
    () => ref
        .read(orgRepositoryProvider)
        .deleteOrganization(orgId: ctx.orgId, confirmName: typed),
  );
}

/// Deletes the signed-in user's account, then signs out (spec §4.5).
Future<void> deleteAccountFlow(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final ok = await confirm(
    context,
    title: l10n.accountDeleteTitle,
    body: l10n.accountDeleteBody,
    action: l10n.accountDelete,
  );
  if (!ok || !context.mounted) return;
  final done = await _withProgress(
    context,
    () => ref.read(orgRepositoryProvider).deleteAccount(),
  );
  if (done) await ref.read(authRepositoryProvider).signOut();
}

class _TypeToConfirmDialog extends StatefulWidget {
  const _TypeToConfirmDialog({
    required this.title,
    required this.body,
    required this.expected,
    required this.label,
    required this.action,
  });

  final String title;
  final String body;
  final String expected;
  final String label;
  final String action;

  @override
  State<_TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<_TypeToConfirmDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final matches = _text.text.trim() == widget.expected.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.label),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: matches ? () => Navigator.pop(context, _text.text) : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}
