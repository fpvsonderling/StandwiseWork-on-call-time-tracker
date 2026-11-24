import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../app/work_state.dart';
import '../../domain/date_ranges.dart';
import '../../domain/durations.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../common/approval_widgets.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import 'timer_actions.dart';
import 'timer_screen.dart' show ProjectPicker, TypeSwitch;

/// Opens the entry editor: a bottom sheet on phones, a dialog on wide
/// screens (spec §5.1). Esc closes it.
///
/// An admin opening someone else's entry ([ownerName] is that person) gets
/// a comment field instead of Delete; the owner then sees who changed the
/// entry and why (D-051).
Future<void> editEntry(
  BuildContext context,
  WidgetRef ref,
  TimeEntry entry, {
  String? ownerName,
}) async {
  final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
  final editor = _EntryEditor(entry: entry, ownerName: ownerName);
  if (wide) {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: editor,
        ),
      ),
    );
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: editor,
      ),
    );
  }
}

class _EntryEditor extends ConsumerStatefulWidget {
  const _EntryEditor({required this.entry, this.ownerName});

  final TimeEntry entry;
  final String? ownerName;

  @override
  ConsumerState<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends ConsumerState<_EntryEditor> {
  late final _description = TextEditingController(
    text: widget.entry.description,
  );
  late final _comment = TextEditingController();
  late final _rate = TextEditingController(
    text: formatMinorPlain(widget.entry.rateMinor),
  );
  late String? _projectId = widget.entry.projectId;
  late EntryType _type = widget.entry.type;
  late DateTime _date = dateOnly(widget.entry.start);
  late TimeOfDay _from = TimeOfDay.fromDateTime(widget.entry.start);
  late TimeOfDay _to = TimeOfDay.fromDateTime(widget.entry.end);
  String? _rateError;

  /// An admin editing someone else's entry.
  bool get _asAdmin => widget.entry.uid != ref.read(workContextProvider)?.uid;

  @override
  void dispose() {
    _description.dispose();
    _comment.dispose();
    _rate.dispose();
    super.dispose();
  }

  ({DateTime start, DateTime end}) get _bounds => manualEntryBounds(
    date: _date,
    from: (hour: _from.hour, minute: _from.minute),
    to: (hour: _to.hour, minute: _to.minute),
  );

  /// Changing project or type fills in the member's current rate (§5.2).
  void _refreshRate() {
    final r = ref
        .read(timerActionsProvider)
        .rateForMember(widget.entry.uid, _projectId, _type);
    _rate.text = formatMinorPlain(r);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final rate = parseRateMinor(_rate.text);
    setState(() => _rateError = rate == null ? l10n.rateInvalid : null);
    final b = _bounds;
    if (rate == null || validateSpan(b.start, b.end) != null) return;
    final updated = widget.entry.copyWith(
      description: _description.text.trim(),
      projectId: _projectId,
      clearProject: _projectId == null,
      type: _type,
      rateMinor: rate,
      start: b.start,
      end: b.end,
    );
    try {
      final actions = ref.read(timerActionsProvider);
      if (_asAdmin) {
        await actions.editAsAdmin(
          updated,
          before: widget.entry,
          comment: _comment.text,
        );
      } else {
        await actions.update(updated);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, l10n.error(e));
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(timerActionsProvider);
    final id = widget.entry.id;
    Navigator.pop(context);
    try {
      await actions.setDeleted(id, deleted: true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.entryDeleted),
            action: SnackBarAction(
              label: l10n.undo,
              onPressed: () => actions.setDeleted(id, deleted: false),
            ),
          ),
        );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.error(e))));
    }
  }

  /// An admin deletes someone else's entry; the owner sees it crossed out
  /// with the comment.
  Future<void> _deleteAsAdmin() async {
    final l10n = context.l10n;
    final name = widget.ownerName ?? '';
    final ok = await confirm(
      context,
      title: l10n.entryDeleteAsAdminTitle(name),
      body: l10n.entryDeleteAsAdminBody(name),
      action: l10n.delete,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(timerActionsProvider);
    final entry = widget.entry;
    final comment = _comment.text;
    Navigator.pop(context);
    try {
      await actions.setDeletedAsAdmin(entry, deleted: true, comment: comment);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.entryDeleted),
            action: SnackBarAction(
              label: l10n.undo,
              onPressed: () => actions.setDeletedAsAdmin(
                entry,
                deleted: false,
                comment: comment,
              ),
            ),
          ),
        );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.error(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ctx = ref.watch(workContextProvider)!;
    final active = ref.watch(activeProjectsProvider);
    final byId = ref.watch(projectsByIdProvider);
    final b = _bounds;
    final spanError = validateSpan(b.start, b.end);
    final time = timeFormat(context, use24h: ctx.settings.use24h);
    final current = _projectId == null ? null : byId[_projectId];
    final asAdmin = _asAdmin;
    if (asAdmin) {
      // Keeps the member's rates loaded for _refreshRate.
      ref.watch(memberRatesProvider((ctx.orgId, widget.entry.uid)));
    }
    final edit = widget.entry.edit;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            asAdmin && widget.ownerName != null
                ? l10n.entryEditOf(widget.ownerName!)
                : l10n.entryEdit,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (edit != null) ...[
            EditedNote(edit: edit, entry: widget.entry),
            const SizedBox(height: 16),
          ],
          if (widget.entry.approval case final approval?) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ApprovedPill(approval: approval),
            ),
            const SizedBox(height: 16),
          ],
          ProjectPicker(
            value: _projectId,
            projects: [
              ...active,
              if (current != null && !current.active) current,
            ],
            onChanged: (v) {
              setState(() => _projectId = v);
              _refreshRate();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLength: 500,
            decoration: InputDecoration(labelText: l10n.description),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TypeSwitch(
                value: _type,
                onChanged: (t) {
                  setState(() => _type = t);
                  _refreshRate();
                },
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  // The iPhone number pad has no Done key.
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: InputDecoration(
                    labelText: l10n.rate,
                    suffixText: l10n.perHour(ctx.currency),
                    errorText: _rateError,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(dateLabel(context, _date)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 366)),
                  );
                  if (d != null) setState(() => _date = d);
                },
              ),
              OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _from,
                  );
                  if (t != null) setState(() => _from = t);
                },
                child: Text(l10n.fromTime(time.format(b.start))),
              ),
              OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _to,
                  );
                  if (t != null) setState(() => _to = t);
                },
                child: Text(l10n.toTime(time.format(b.end))),
              ),
              Text(
                spanError == null
                    ? formatHoursMinutes(durationMinutes(b.start, b.end))
                    : l10n.spanError,
                style: TextStyle(
                  fontFeatures: tabularFigures,
                  color: spanError == null
                      ? null
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
          if (asAdmin) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _comment,
              maxLength: 500,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: l10n.editComment,
                helperText: l10n.editCommentHelp,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton.icon(
                onPressed: asAdmin ? _deleteAsAdmin : _delete,
                icon: Icon(
                  Icons.delete_outline,
                  color: context.statusColors.stop,
                ),
                label: Text(
                  l10n.delete,
                  style: TextStyle(color: context.statusColors.stop),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: spanError == null && _projectId != null
                    ? _save
                    : null,
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Changed by X on date", the admin's comment (D-051) and the owner's
/// values from before the change.
class EditedNote extends ConsumerWidget {
  const EditedNote({super.key, required this.edit, required this.entry});

  final EntryEdit edit;
  final TimeEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final at = edit.at;
    final ctx = ref.watch(workContextProvider);
    final from = entry.editedFrom;
    final before = from == null || ctx == null
        ? null
        : entryBeforeText(
            context,
            before: from,
            now: entry,
            projects: ref.watch(projectsByIdProvider),
            currency: ctx.currency,
            use24h: ctx.settings.use24h,
          );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.edit_note, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  at == null
                      ? l10n.editedBy(edit.byName)
                      : l10n.editedByOn(edit.byName, dateLabel(context, at)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (edit.comment.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    edit.comment,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
                if (before != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    before,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
