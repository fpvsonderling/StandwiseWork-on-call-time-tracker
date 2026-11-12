import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/l10n.dart';
import '../../app/work_state.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../common/format.dart';

final _auditProvider = StreamProvider.family<List<AuditEntry>, String>(
  (ref, orgId) => ref.watch(orgRepositoryProvider).watchAuditLog(orgId),
);

/// Settings → Activity (admins): the latest 100 audit log entries.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ctx = ref.watch(workContextProvider);
    if (ctx == null || !ctx.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.settingsActivity)),
        body: Center(child: Text(l10n.errorNotAdmin)),
      );
    }
    final log = ref.watch(_auditProvider(ctx.orgId));
    final members = ref.watch(orgMembersProvider(ctx.orgId)).value ?? const [];
    final names = {for (final m in members) m.uid: m.displayName};
    final when = DateFormat.yMMMd(localeOf(context)).add_Hm();

    String describe(AuditEntry e) {
      final target = names[e.entityId] ?? (e.details['email'] as String?) ?? '';
      return switch (e.action) {
        'org.create' => l10n.auditOrgCreate,
        'org.transferOwnership' => l10n.auditTransfer(target),
        'invite.create' => l10n.auditInviteCreate(
          '${e.details['email'] ?? ''}',
        ),
        'invite.resend' => l10n.auditInviteResend(
          '${e.details['email'] ?? ''}',
        ),
        'invite.revoke' => l10n.auditInviteRevoke(
          '${e.details['email'] ?? ''}',
        ),
        'invite.accept' || 'member.join' => l10n.auditJoin(target),
        'member.role' => l10n.auditRole(target, '${e.details['to'] ?? ''}'),
        'member.disable' => l10n.auditDisable(target),
        'member.enable' => l10n.auditEnable(target),
        'member.remove' => l10n.auditRemove(target),
        'member.leave' => l10n.auditLeave(target),
        'account.delete' => l10n.auditAccountDelete,
        'entry.edit' => l10n.auditEntryEdit(target),
        _ => e.action,
      };
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsActivity)),
      body: switch (log) {
        AsyncValue(:final value?) when value.isEmpty => Center(
          child: Text(l10n.auditEmpty),
        ),
        AsyncValue(:final value?) => ListView.separated(
          itemCount: value.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final e = value[i];
            return ListTile(
              title: Text(describe(e)),
              subtitle: Text(
                '${when.format(e.at)} · ${names[e.actorUid] ?? l10n.formerMember}',
              ),
            );
          },
        ),
        AsyncValue(:final error?) => Center(child: Text(l10n.error(error))),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
