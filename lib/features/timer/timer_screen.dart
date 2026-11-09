import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../app/tracker_prefs.dart';
import '../../app/work_state.dart';
import '../../domain/date_ranges.dart';
import '../../domain/durations.dart';
import '../../domain/models.dart';
import '../../domain/projects.dart';
import '../../domain/reports.dart';
import '../../domain/timer.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../placeholder/placeholder_screens.dart';
import 'entry_editor.dart';
import 'timer_actions.dart';

/// Timer tab (spec §5.1): tracker bar and entries by day. The week chart
/// lives in My reports (D-044).
class TimerScreen extends ConsumerWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ctx = ref.watch(workContextProvider);
    if (ctx == null) return const TimerPlaceholder();
    final entriesState = ref.watch(myRecentEntriesProvider);
    final entries = entriesState.value ?? const <TimeEntry>[];
    final groups = groupByDay(entries);
    final hasSamples = (ref.watch(projectsProvider).value ?? const []).any(
      (p) => p.isSample && !p.deleted,
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const TrackerCard(),
        if (entriesState.isLoading && entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (entries.isEmpty)
          _EmptyState(canLoadSamples: ctx.isAdmin && ctx.writable)
        else
          for (final g in groups) ...[
            _DayHeader(group: g, currency: ctx.currency),
            for (final e in g.entries) EntryTile(key: ValueKey(e.id), entry: e),
          ],
        if (entries.isNotEmpty || !entriesState.isLoading)
          Center(
            child: TextButton.icon(
              onPressed: () => ref.read(historyDaysProvider.notifier).more(),
              icon: const Icon(Icons.history),
              label: Text(l10n.showEarlierDays),
            ),
          ),
        if (hasSamples && ctx.isAdmin && ctx.writable)
          Center(
            child: TextButton.icon(
              onPressed: () => _guard(
                context,
                () => ref.read(timerActionsProvider).removeSampleData(),
              ),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(l10n.sampleRemove),
            ),
          ),
      ],
    );
  }
}

/// Runs [action] and shows its error, if any, in a SnackBar.
Future<void> _guard(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) showError(context, context.l10n.error(e));
  }
}

enum _Mode { timer, manual }

/// The tracker bar: description, project, Work/Standby, rate, clock and
/// Start/Stop, or the manual entry form.
class TrackerCard extends ConsumerStatefulWidget {
  const TrackerCard({super.key});

  @override
  ConsumerState<TrackerCard> createState() => _TrackerCardState();
}

class _TrackerCardState extends ConsumerState<TrackerCard> {
  final _description = TextEditingController();
  final _focus = FocusNode();
  _Mode _mode = _Mode.timer;

  /// Picked in this session; `null` falls back to [_defaultProject].
  String? _projectId;
  EntryType _type = EntryType.work;

  /// Last project remembered for [_prefsOrg] on this device.
  String? _rememberedProject;
  String? _prefsOrg;

  // Manual entry.
  DateTime _date = dateOnly(DateTime.now());
  TimeOfDay _from = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 16, minute: 0);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _pushDescription();
    });
    _loadMode();
  }

  TrackerPrefs get _prefs => ref.read(trackerPrefsProvider);

  Future<void> _loadMode() async {
    final mode = await _prefs.read(TrackerPrefKeys.mode);
    if (!mounted || mode == null || _running != null) return;
    setState(() => _mode = mode == 'manual' ? _Mode.manual : _Mode.timer);
  }

  Future<void> _loadProject(String orgId) async {
    _prefsOrg = orgId;
    final id = await _prefs.read(TrackerPrefKeys.project(orgId));
    if (!mounted || _prefsOrg != orgId) return;
    setState(() => _rememberedProject = id);
  }

  void _setMode(_Mode mode) {
    setState(() => _mode = mode);
    _prefs.write(TrackerPrefKeys.mode, mode.name);
  }

  /// The remembered project, else the project of the latest entry, else the
  /// first active project; always an active one (or `null` if none).
  String? _defaultProject(List<Project> active, List<TimeEntry> recent) {
    bool ok(String? id) => id != null && active.any((p) => p.id == id);
    if (ok(_rememberedProject)) return _rememberedProject;
    TimeEntry? latest;
    for (final e in recent) {
      if (ok(e.projectId) &&
          (latest == null || e.start.isAfter(latest.start))) {
        latest = e;
      }
    }
    if (latest != null) return latest.projectId;
    return active.isEmpty ? null : active.first.id;
  }

  @override
  void dispose() {
    _description.dispose();
    _focus.dispose();
    super.dispose();
  }

  RunningTimer? get _running => ref.read(timerProvider).value;

  void _pushDescription() {
    final t = _running;
    if (t != null && t.description != _description.text.trim()) {
      _guard(
        context,
        () => ref
            .read(timerActionsProvider)
            .updateRunning(description: _description.text.trim()),
      );
    }
  }

  Future<void> _start(String? projectId) async {
    await _guard(
      context,
      () => ref
          .read(timerActionsProvider)
          .start(
            description: _description.text,
            projectId: projectId,
            type: _type,
          ),
    );
  }

  Future<void> _stop() async {
    await _guard(context, () => ref.read(timerActionsProvider).stop());
    _description.clear();
  }

  void _setProject(String? id) {
    if (id == null) return;
    setState(() => _projectId = id);
    final orgId = ref.read(workContextProvider)?.orgId;
    if (orgId != null) {
      _rememberedProject = id;
      _prefs.write(TrackerPrefKeys.project(orgId), id);
    }
    if (_running != null) {
      _guard(
        context,
        () => ref.read(timerActionsProvider).updateRunning(projectId: id),
      );
    }
  }

  void _setType(EntryType type) {
    setState(() => _type = type);
    if (_running != null) {
      _guard(
        context,
        () => ref.read(timerActionsProvider).updateRunning(type: type),
      );
    }
  }

  ({DateTime start, DateTime end}) get _manualBounds => manualEntryBounds(
    date: _date,
    from: (hour: _from.hour, minute: _from.minute),
    to: (hour: _to.hour, minute: _to.minute),
  );

  Future<void> _addManual(String? projectId) async {
    final b = _manualBounds;
    if (validateSpan(b.start, b.end) != null) return;
    await _guard(
      context,
      () => ref
          .read(timerActionsProvider)
          .addManual(
            start: b.start,
            end: b.end,
            description: _description.text,
            projectId: projectId,
            type: _type,
          ),
    );
    _description.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ctx = ref.watch(workContextProvider)!;
    final running = ref.watch(timerProvider).value;
    final projects = ref.watch(activeProjectsProvider);
    final byId = ref.watch(projectsByIdProvider);
    final rates = ref.watch(myRatesProvider).value ?? const {};
    final recent = ref.watch(myRecentEntriesProvider).value ?? const [];
    final status = context.statusColors;
    if (_prefsOrg != ctx.orgId) {
      _prefsOrg = ctx.orgId;
      _rememberedProject = null;
      Future.microtask(() => _loadProject(ctx.orgId));
    }

    // A running timer (from this or another device) drives the fields.
    ref.listen(timerProvider, (_, next) {
      final t = next.value;
      if (t == null) return;
      setState(() {
        _projectId = t.projectId;
        _type = t.type;
        _mode = _Mode.timer;
      });
      if (!_focus.hasFocus && _description.text != t.description) {
        _description.text = t.description;
      }
    });

    final picked = _projectId != null && projects.any((p) => p.id == _projectId)
        ? _projectId
        : null;
    final projectId = running != null
        ? running.projectId
        : picked ?? _defaultProject(projects, recent);
    final type = running?.type ?? _type;
    final rate = currentRate(rates, projectId, type);
    final enabled = ctx.writable;
    final canSave = enabled && projectId != null;

    final description = TextField(
      controller: _description,
      focusNode: _focus,
      enabled: enabled,
      maxLength: 500,
      textInputAction: TextInputAction.go,
      onSubmitted: (_) {
        if (_mode == _Mode.manual) {
          if (canSave) _addManual(projectId);
        } else if (running == null) {
          if (canSave) _start(projectId);
        } else {
          _pushDescription();
        }
      },
      decoration: InputDecoration(
        hintText: l10n.trackerDescriptionHint,
        counterText: '',
        prefixIcon: const Icon(Icons.edit_note),
      ),
    );

    final picker = ProjectPicker(
      value: projectId,
      projects: [
        ...projects,
        // Keep showing an archived project a running timer still uses.
        if (projectId != null &&
            byId[projectId] != null &&
            !projects.any((p) => p.id == projectId))
          byId[projectId]!,
      ],
      enabled: enabled,
      onChanged: _setProject,
      helperText: projects.isEmpty
          ? (ctx.isAdmin ? l10n.projectsNoneAdmin : l10n.projectsNoneEmployee)
          : null,
    );

    final typeSwitch = TypeSwitch(
      value: type,
      onChanged: enabled ? _setType : null,
    );

    final ratePreview = Text(
      rate == 0
          ? l10n.rateNotSet
          : l10n.yourRate(money(context, rate, ctx.currency)),
      style: Theme.of(context).textTheme.bodySmall,
    );

    final modeSwitch = SegmentedButton<_Mode>(
      segments: [
        ButtonSegment(
          value: _Mode.timer,
          icon: const Icon(Icons.timer_outlined),
          label: Text(l10n.modeTimer),
        ),
        ButtonSegment(
          value: _Mode.manual,
          icon: const Icon(Icons.edit_calendar_outlined),
          label: Text(l10n.modeManual),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: running == null ? (s) => _setMode(s.first) : null,
      showSelectedIcon: false,
    );

    final Widget action;
    if (_mode == _Mode.timer) {
      action = Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: running != null
                  ? _Clock(timer: running)
                  : Text(
                      formatClock(Duration.zero),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontFeatures: tabularFigures,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: running != null
                ? (enabled ? _stop : null)
                : (canSave ? () => _start(projectId) : null),
            style: FilledButton.styleFrom(
              backgroundColor: running == null ? status.work : status.stop,
              foregroundColor: running == null ? status.onWork : status.onStop,
              minimumSize: const Size(120, 48),
            ),
            icon: Icon(running == null ? Icons.play_arrow : Icons.stop),
            label: Text(running == null ? l10n.start : l10n.stop),
          ),
        ],
      );
    } else {
      final b = _manualBounds;
      final error = validateSpan(b.start, b.end);
      final time = timeFormat(context, use24h: ctx.settings.use24h);
      action = Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.end,
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
            error == null
                ? formatHoursMinutes(durationMinutes(b.start, b.end))
                : l10n.spanError,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontFeatures: tabularFigures,
              color: error == null ? null : Theme.of(context).colorScheme.error,
            ),
          ),
          FilledButton.icon(
            onPressed: canSave && error == null
                ? () => _addManual(projectId)
                : null,
            icon: const Icon(Icons.add),
            label: Text(l10n.add),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= Breakpoints.expanded - 200;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.centerLeft, child: modeSwitch),
                  const SizedBox(height: 12),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: picker),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: description),
                      ],
                    )
                  else ...[
                    picker,
                    const SizedBox(height: 12),
                    description,
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [typeSwitch, ratePreview],
                  ),
                  const SizedBox(height: 12),
                  action,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// `H:MM:SS` computed from the stored start every second.
class _Clock extends StatefulWidget {
  const _Clock({required this.timer});

  final RunningTimer timer;

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = formatClock(widget.timer.elapsed(DateTime.now()));
    return Semantics(
      liveRegion: false,
      label: context.l10n.runningFor(text),
      child: ExcludeSemantics(
        child: Text(
          text,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontFeatures: tabularFigures),
        ),
      ),
    );
  }
}

/// Project dropdown; a project is required for new time (D-044), so there is
/// no "No project" choice.
class ProjectPicker extends StatelessWidget {
  const ProjectPicker({
    super.key,
    required this.value,
    required this.projects,
    required this.onChanged,
    this.enabled = true,
    this.helperText,
  });

  final String? value;
  final List<Project> projects;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final known = value != null && projects.any((p) => p.id == value);
    return DropdownButtonFormField<String>(
      key: ValueKey(known ? value : null),
      initialValue: known ? value : null,
      isExpanded: true,
      hint: Text(l10n.chooseProject),
      decoration: InputDecoration(
        labelText: l10n.project,
        helperText: helperText,
        helperMaxLines: 2,
      ),
      onChanged: enabled ? onChanged : null,
      items: [
        for (final p in projects)
          DropdownMenuItem(
            value: p.id,
            child: Row(
              children: [
                ProjectDot(color: p.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.client.isEmpty ? p.name : '${p.name} · ${p.client}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Work / Standby.
class TypeSwitch extends StatelessWidget {
  const TypeSwitch({super.key, required this.value, required this.onChanged});

  final EntryType value;
  final ValueChanged<EntryType>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = context.statusColors;
    return SegmentedButton<EntryType>(
      segments: [
        ButtonSegment(
          value: EntryType.work,
          icon: Icon(Icons.work_outline, color: status.work),
          label: Text(l10n.typeWork),
        ),
        ButtonSegment(
          value: EntryType.standby,
          icon: Icon(
            Icons.notifications_active_outlined,
            color: status.standby,
          ),
          label: Text(l10n.typeStandby),
        ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: onChanged == null ? null : (s) => onChanged!(s.first),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.group, required this.currency});

  final DayGroup group;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionHeader(
      dayLabel(context, group.day),
      trailing: Text(
        '${formatHoursMinutes(group.totals.totalMin)} · '
        '${money(context, group.totals.amountMinor, currency)}',
        style: theme.textTheme.titleSmall?.copyWith(
          fontFeatures: tabularFigures,
        ),
      ),
    );
  }
}

/// One entry: tap to edit, Continue, delete with Undo.
class EntryTile extends ConsumerWidget {
  const EntryTile({super.key, required this.entry});

  final TimeEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ctx = ref.watch(workContextProvider)!;
    final project = entry.projectId == null
        ? null
        : ref.watch(projectsByIdProvider)[entry.projectId];
    final time = timeFormat(context, use24h: ctx.settings.use24h);
    final theme = Theme.of(context);
    final status = context.statusColors;
    final writable = ctx.writable;

    Future<void> delete() async {
      final messenger = ScaffoldMessenger.of(context);
      final actions = ref.read(timerActionsProvider);
      await _guard(context, () => actions.setDeleted(entry.id, deleted: true));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.entryDeleted),
            action: SnackBarAction(
              label: l10n.undo,
              onPressed: () => actions.setDeleted(entry.id, deleted: false),
            ),
          ),
        );
    }

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: writable ? () => editEntry(context, ref, entry) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              ProjectDot(
                color: project?.deleted == true ? null : project?.color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.description.isEmpty
                          ? l10n.noDescription
                          : entry.description,
                      style: entry.description.isEmpty
                          ? theme.textTheme.bodyLarge?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.outline,
                            )
                          : theme.textTheme.bodyLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        projectLabel(l10n, project, entry.projectId),
                        '${time.format(entry.start)}–${time.format(entry.end)}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatHoursMinutes(entry.durationMin),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        entry.type == EntryType.work
                            ? Icons.work_outline
                            : Icons.notifications_active_outlined,
                        size: 14,
                        color: entry.type == EntryType.work
                            ? status.work
                            : status.standby,
                        semanticLabel: entry.type == EntryType.work
                            ? l10n.typeWork
                            : l10n.typeStandby,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        money(context, entry.amountMinor, ctx.currency),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (writable) ...[
                IconButton(
                  tooltip: l10n.continueEntry,
                  icon: const Icon(Icons.play_arrow_outlined),
                  onPressed: () => _guard(
                    context,
                    () => ref.read(timerActionsProvider).continueEntry(entry),
                  ),
                ),
                IconButton(
                  tooltip: l10n.delete,
                  icon: Icon(Icons.delete_outline, color: status.stop),
                  onPressed: delete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.canLoadSamples});

  final bool canLoadSamples;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.timer_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.timerEmptyTitle,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(l10n.timerEmptyBody, textAlign: TextAlign.center),
          if (canLoadSamples) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _guard(
                context,
                () => ref.read(timerActionsProvider).loadSampleData(),
              ),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(l10n.sampleLoad),
            ),
          ],
        ],
      ),
    );
  }
}
