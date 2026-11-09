import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../app/work_state.dart';
import '../../data/providers.dart';
import '../../domain/date_ranges.dart';
import '../../domain/durations.dart';
import '../../domain/models.dart';
import '../../domain/reports.dart';
import '../common/csv_export.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../placeholder/placeholder_screens.dart';
import '../reports/report_widgets.dart';

/// One person's entries starting in a range (admins reading the team).
final personEntriesProvider =
    StreamProvider.family<List<TimeEntry>, (String, DateRange)>((ref, key) {
      final orgId = ref.watch(workContextProvider.select((c) => c?.orgId));
      if (orgId == null) return Stream.value(const []);
      final (uid, range) = key;
      return ref
          .watch(entriesRepositoryProvider)
          .watchEntries(orgId, uid: uid, from: range.start, to: range.end);
    });

/// Team (spec §5.5, admins and the owner): totals from the monthly
/// summaries, a people table with everyone active (even at zero), one
/// person's entries, chart, project table and team CSV.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  ReportRange? _range;
  String? _project;
  String? _person;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ctx = ref.watch(workContextProvider);
    if (ctx == null) return const TeamPlaceholder();
    if (!ctx.isAdmin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.teamAdminsOnly, textAlign: TextAlign.center),
        ),
      );
    }
    final range =
        _range ??
        ReportRange.preset(
          RangePreset.thisMonth,
          weekStart: ctx.settings.weekStart,
        );
    final state = ref.watch(teamCellsProvider(range.range));
    final members = ref.watch(orgMembersProvider(ctx.orgId)).value ?? const [];
    final projects = ref.watch(projectsByIdProvider);
    final byUid = {for (final m in members) m.uid: m};

    final projectCells = (state.value ?? const <ReportCell>[])
        .where((c) => cellMatchesProject(c, _project))
        .toList();
    final cells = _person == null
        ? projectCells
        : projectCells.where((c) => c.uid == _person).toList();
    final perPerson = totalsByPerson(projectCells);

    // Everyone active, plus anyone else with hours in the range.
    final uids = {
      ...members.where((m) => m.isActive).map((m) => m.uid),
      ...perPerson.keys,
    };
    String nameOf(String uid) => byUid[uid]?.displayName ?? l10n.formerMember;
    String sortKey(String uid) {
      final m = byUid[uid];
      return m == null ? '￿' : '${m.lastName} ${m.firstName}'.toLowerCase();
    }

    final people = uids.toList()
      ..sort((a, b) => sortKey(a).compareTo(sortKey(b)));

    Future<void> export({required bool summary}) async {
      setState(() => _exporting = true);
      try {
        final entries =
            (await ref
                    .read(entriesRepositoryProvider)
                    .watchEntries(
                      ctx.orgId,
                      uid: _person,
                      from: range.range.start,
                      to: range.range.end,
                    )
                    .first)
                .where((e) => matchesProject(e, _project));
        final csvPeople = <String, CsvPerson>{
          for (final m in members)
            m.uid: (
              firstName: m.firstName,
              lastName: m.lastName,
              email: m.email,
            ),
        };
        final csv = summary
            ? teamSummaryCsv(
                uids: _person == null ? people : [_person!],
                entries: entries,
                people: csvPeople,
                settings: ctx.settings,
                labels: TeamCsvLabels(
                  person: l10n.person,
                  email: l10n.csvEmail,
                  work: l10n.typeWork,
                  standby: l10n.typeStandby,
                  total: l10n.total,
                  hours: l10n.csvHours,
                  entries: l10n.entries,
                  amount: l10n.amount,
                  totalRow: l10n.total,
                  formerMember: l10n.formerMember,
                ),
              )
            : entriesCsv(
                entries: entries,
                projects: projects,
                settings: ctx.settings,
                labels: csvLabels(l10n),
                people: csvPeople,
              );
        if (!context.mounted) return;
        await ref
            .read(csvSaverProvider)
            .save(
              context,
              csvFileName(
                summary ? 'team-summary' : 'team-entries',
                range.range.start,
                range.lastDay,
              ),
              csv,
            );
      } catch (e) {
        if (context.mounted) showError(context, l10n.error(e));
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        RangeBar(
          value: range,
          weekStart: ctx.settings.weekStart,
          onChanged: (r) => setState(() => _range = r),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: ProjectFilterField(
                value: _project,
                projects: projects.values.toList(),
                onChanged: (p) => setState(() => _project = p),
              ),
            ),
            SizedBox(
              width: 260,
              child: _PersonFilter(
                value: _person,
                people: people,
                nameOf: nameOf,
                onChanged: (p) => setState(() => _person = p),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _exporting ? null : () => export(summary: true),
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(l10n.exportTeamCsv),
            ),
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => export(summary: false),
              icon: const Icon(Icons.list_alt),
              label: Text(l10n.exportTeamEntriesCsv),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.isLoading && !state.hasValue)
          const Center(child: CircularProgressIndicator())
        else ...[
          ReportTiles(totals: totalsOfCells(cells), currency: ctx.currency),
          const SizedBox(height: 16),
          SectionHeader(l10n.teamPeople),
          Card(
            child: _PeopleTable(
              people: people,
              totals: perPerson,
              nameOf: nameOf,
              selected: _person,
              currency: ctx.currency,
              onSelect: (uid) =>
                  setState(() => _person = _person == uid ? null : uid),
            ),
          ),
          if (_person != null) ...[
            SectionHeader(l10n.teamEntriesOf(nameOf(_person!))),
            Card(
              child: _PersonEntries(
                uid: _person!,
                range: range.range,
                project: _project,
              ),
            ),
          ],
          if (cells.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: ReportChart(
                  cells: cells,
                  range: range.range,
                  projects: projects,
                  weekStart: ctx.settings.weekStart,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ProjectTable(
                cells: cells,
                projects: projects,
                currency: ctx.currency,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            l10n.teamSummariesNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _PersonFilter extends StatelessWidget {
  const _PersonFilter({
    required this.value,
    required this.people,
    required this.nameOf,
    required this.onChanged,
  });

  final String? value;
  final List<String> people;
  final String Function(String) nameOf;
  final ValueChanged<String?> onChanged;

  static const _everyone = '\u0000everyone';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: value != null && people.contains(value) ? value : _everyone,
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.person, isDense: true),
      onChanged: (v) => onChanged(v == _everyone ? null : v),
      items: [
        DropdownMenuItem(value: _everyone, child: Text(l10n.everyone)),
        for (final uid in people)
          DropdownMenuItem(
            value: uid,
            child: Text(nameOf(uid), overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

/// Name, Work, Standby, Total, Entries, Amount and a Total row.
class _PeopleTable extends StatelessWidget {
  const _PeopleTable({
    required this.people,
    required this.totals,
    required this.nameOf,
    required this.selected,
    required this.currency,
    required this.onSelect,
  });

  final List<String> people;
  final Map<String, Totals> totals;
  final String Function(String) nameOf;
  final String? selected;
  final String currency;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const num = TextStyle(fontFeatures: tabularFigures);
    const bold = TextStyle(
      fontFeatures: tabularFigures,
      fontWeight: FontWeight.bold,
    );
    final all = Totals();
    for (final uid in people) {
      final t = totals[uid];
      if (t != null) all.addTotals(t);
    }
    List<DataCell> figures(Totals t, TextStyle style) => [
      DataCell(Text(formatHoursMinutes(t.workMin), style: style)),
      DataCell(Text(formatHoursMinutes(t.standbyMin), style: style)),
      DataCell(Text(formatHoursMinutes(t.totalMin), style: style)),
      DataCell(Text('${t.count}', style: style)),
      DataCell(Text(money(context, t.amountMinor, currency), style: style)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columnSpacing: 24,
        columns: [
          DataColumn(label: Text(l10n.person)),
          DataColumn(label: Text(l10n.typeWork), numeric: true),
          DataColumn(label: Text(l10n.typeStandby), numeric: true),
          DataColumn(label: Text(l10n.total), numeric: true),
          DataColumn(label: Text(l10n.entries), numeric: true),
          DataColumn(label: Text(l10n.amount), numeric: true),
        ],
        rows: [
          for (final uid in people)
            DataRow(
              selected: uid == selected,
              onSelectChanged: (_) => onSelect(uid),
              cells: [
                DataCell(Text(nameOf(uid))),
                ...figures(totals[uid] ?? Totals(), num),
              ],
            ),
          DataRow(
            cells: [
              DataCell(Text(l10n.total, style: bold)),
              ...figures(all, bold),
            ],
          ),
        ],
      ),
    );
  }
}

/// Date, times, project, type, description, duration, rate, amount.
class _PersonEntries extends ConsumerWidget {
  const _PersonEntries({
    required this.uid,
    required this.range,
    required this.project,
  });

  final String uid;
  final DateRange range;
  final String? project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ctx = ref.watch(workContextProvider)!;
    final projects = ref.watch(projectsByIdProvider);
    final state = ref.watch(personEntriesProvider((uid, range)));
    final entries = (state.value ?? const <TimeEntry>[])
        .where((e) => matchesProject(e, project))
        .toList();
    final time = timeFormat(context, use24h: ctx.settings.use24h);
    const num = TextStyle(fontFeatures: tabularFigures);
    if (state.isLoading && !state.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(l10n.reportEmpty),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        columns: [
          DataColumn(label: Text(l10n.csvDate)),
          DataColumn(label: Text(l10n.time)),
          DataColumn(label: Text(l10n.project)),
          DataColumn(label: Text(l10n.csvType)),
          DataColumn(label: Text(l10n.description)),
          DataColumn(label: Text(l10n.duration), numeric: true),
          DataColumn(label: Text(l10n.rate), numeric: true),
          DataColumn(label: Text(l10n.amount), numeric: true),
        ],
        rows: [
          for (final e in entries)
            DataRow(
              cells: [
                DataCell(Text(dateLabel(context, e.start))),
                DataCell(
                  Text(
                    '${time.format(e.start)}–${time.format(e.end)}',
                    style: num,
                  ),
                ),
                DataCell(
                  Text(projectLabel(l10n, projects[e.projectId], e.projectId)),
                ),
                DataCell(
                  Text(
                    e.type == EntryType.work ? l10n.typeWork : l10n.typeStandby,
                  ),
                ),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(e.description, overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(Text(formatHoursMinutes(e.durationMin), style: num)),
                DataCell(
                  Text(money(context, e.rateMinor, ctx.currency), style: num),
                ),
                DataCell(
                  Text(money(context, e.amountMinor, ctx.currency), style: num),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
