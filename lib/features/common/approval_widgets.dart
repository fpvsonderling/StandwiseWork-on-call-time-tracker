import 'package:flutter/material.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../domain/projects.dart';
import 'format.dart';
import 'widgets.dart';

/// A small colored label: an icon and a short text.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}

/// "Pending approval", "Approved" or "Rejected" for a member's rate.
class RateStatusPill extends StatelessWidget {
  const RateStatusPill({super.key, required this.rate});

  final ProjectRate rate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = context.statusColors;
    final review = rate.review;
    return switch (rate.status) {
      RateStatus.pending => StatusPill(
        icon: Icons.hourglass_top,
        label: l10n.ratePending,
        color: s.standby,
        tooltip: l10n.ratePendingHelp,
      ),
      RateStatus.approved => StatusPill(
        icon: Icons.check_circle_outline,
        label: l10n.rateApproved,
        color: s.work,
        tooltip: review == null ? null : l10n.rateApprovedBy(review.byName),
      ),
      RateStatus.rejected => StatusPill(
        icon: Icons.block,
        label: l10n.rateRejected,
        color: s.stop,
        tooltip: review == null
            ? null
            : [
                l10n.rateRejectedBy(review.byName),
                if (review.comment.isNotEmpty) review.comment,
              ].join(': '),
      ),
    };
  }
}

/// "Approved" with a lock, for an approved entry.
class ApprovedPill extends StatelessWidget {
  const ApprovedPill({super.key, required this.approval});

  final EntryApproval approval;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final at = approval.at;
    return StatusPill(
      icon: Icons.lock_outline,
      label: l10n.entryApproved,
      color: context.statusColors.work,
      tooltip: at == null
          ? l10n.entryApprovedBy(approval.byName)
          : l10n.entryApprovedByOn(approval.byName, dateLabel(context, at)),
    );
  }
}

/// What an admin changed, as the owner's earlier values: "Nov 3, 2026,
/// 08:00–16:00 · Work · €45.00/h". Only fields that differ from [now] are
/// listed; `null` when nothing differs.
String? entryBeforeText(
  BuildContext context, {
  required EntrySnapshot before,
  required TimeEntry now,
  required Map<String, Project> projects,
  required String currency,
  required bool use24h,
}) {
  final l10n = context.l10n;
  final time = timeFormat(context, use24h: use24h);
  final parts = <String>[
    if (dateLabel(context, before.start) != dateLabel(context, now.start))
      dateLabel(context, before.start),
    if (before.start != now.start || before.end != now.end)
      '${time.format(before.start)}–${time.format(before.end)}',
    if (before.projectId != now.projectId)
      projectLabel(l10n, projects[before.projectId], before.projectId),
    if (before.type != now.type)
      before.type == EntryType.work ? l10n.typeWork : l10n.typeStandby,
    if (before.rateMinor != now.rateMinor)
      '${money(context, before.rateMinor, currency)}/h',
    if (before.description != now.description)
      before.description.isEmpty ? '“”' : '“${before.description}”',
  ];
  return parts.isEmpty ? null : l10n.entryBefore(parts.join(' · '));
}
