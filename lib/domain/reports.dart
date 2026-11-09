/// Aggregation for the Timer list, week summary, reports and CSV (spec
/// §5.1, §5.3, §5.5). Pure Dart; all days are local wall-clock days of the
/// entry's start.
library;

import 'date_ranges.dart';
import 'durations.dart';
import 'models.dart';
import 'money.dart';
import 'projects.dart';

/// Minutes and money for a set of entries.
class Totals {
  Totals();

  int workMin = 0;
  int standbyMin = 0;
  int amountMinor = 0;
  int count = 0;

  int get totalMin => workMin + standbyMin;

  void add(TimeEntry e) {
    if (e.type == EntryType.work) {
      workMin += e.durationMin;
    } else {
      standbyMin += e.durationMin;
    }
    amountMinor += e.amountMinor;
    count++;
  }

  void addCell(ReportCell c) {
    workMin += c.workMin;
    standbyMin += c.standbyMin;
    amountMinor += c.amountMinor;
    count += c.count;
  }

  void addTotals(Totals o) {
    workMin += o.workMin;
    standbyMin += o.standbyMin;
    amountMinor += o.amountMinor;
    count += o.count;
  }
}

Totals totalsOf(Iterable<TimeEntry> entries) {
  final t = Totals();
  entries.forEach(t.add);
  return t;
}

Totals totalsOfCells(Iterable<ReportCell> cells) {
  final t = Totals();
  cells.forEach(t.addCell);
  return t;
}

/// Pre-aggregated time of one person, day and project: one entry, or one
/// project bucket of a monthly summary (spec §5.5). Reports, the chart and
/// the tables are built from cells, so the same code serves My reports
/// (entries) and Team (summaries).
class ReportCell {
  const ReportCell({
    required this.uid,
    required this.day,
    required this.projectId,
    this.workMin = 0,
    this.standbyMin = 0,
    this.amountMinor = 0,
    this.count = 0,
  });

  final String uid;

  /// Local midnight of the day the time counts on.
  final DateTime day;

  /// `null` for no project.
  final String? projectId;
  final int workMin;
  final int standbyMin;
  final int amountMinor;
  final int count;

  int get totalMin => workMin + standbyMin;
}

ReportCell cellOf(TimeEntry e) => ReportCell(
  uid: e.uid,
  day: dateOnly(e.start),
  projectId: e.projectId,
  workMin: e.type == EntryType.work ? e.durationMin : 0,
  standbyMin: e.type == EntryType.standby ? e.durationMin : 0,
  amountMinor: e.amountMinor,
  count: 1,
);

/// Project filter for cells (see [matchesProject]).
bool cellMatchesProject(ReportCell c, String? filter) {
  if (filter == null) return true;
  if (filter == noProjectKey) return c.projectId == null;
  return c.projectId == filter;
}

/// Totals per person.
Map<String, Totals> totalsByPerson(Iterable<ReportCell> cells) {
  final m = <String, Totals>{};
  for (final c in cells) {
    m.putIfAbsent(c.uid, Totals.new).addCell(c);
  }
  return m;
}

/// Entries of one day, newest first.
class DayGroup {
  DayGroup(this.day);

  final DateTime day;
  final entries = <TimeEntry>[];
  final totals = Totals();
}

/// Groups [entries] by the local day they start, newest day first.
List<DayGroup> groupByDay(Iterable<TimeEntry> entries) {
  final groups = <DateTime, DayGroup>{};
  final sorted = entries.toList()..sort((a, b) => b.start.compareTo(a.start));
  for (final e in sorted) {
    final g = groups.putIfAbsent(
      dateOnly(e.start),
      () => DayGroup(dateOnly(e.start)),
    );
    g.entries.add(e);
    g.totals.add(e);
  }
  return groups.values.toList();
}

/// One bar of the week summary.
class DayBar {
  DayBar(this.day);

  final DateTime day;
  int workMin = 0;
  int standbyMin = 0;

  int get totalMin => workMin + standbyMin;
}

/// Seven bars for [week] (spec §5.1), Work and Standby separately.
List<DayBar> weekBars(Iterable<TimeEntry> entries, DateRange week) {
  final bars = [
    for (var i = 0; i < 7; i++)
      DayBar(DateTime(week.start.year, week.start.month, week.start.day + i)),
  ];
  for (final e in entries) {
    if (!week.contains(e.start)) continue;
    final bar = bars.firstWhere((b) => b.day == dateOnly(e.start));
    if (e.type == EntryType.work) {
      bar.workMin += e.durationMin;
    } else {
      bar.standbyMin += e.durationMin;
    }
  }
  return bars;
}

/// Project filter: `null` = all projects, [noProjectKey] = entries without
/// a project, otherwise a project ID.
bool matchesProject(TimeEntry e, String? filter) {
  if (filter == null) return true;
  if (filter == noProjectKey) return e.projectId == null;
  return e.projectId == filter;
}

/// A row of the project table (spec §5.3).
class ProjectRow {
  ProjectRow(this.projectId);

  /// `null` for entries without a project.
  final String? projectId;
  final totals = Totals();
}

/// Project table rows, largest total first.
List<ProjectRow> projectRows(Iterable<ReportCell> cells) {
  final rows = <String?, ProjectRow>{};
  for (final c in cells) {
    rows
        .putIfAbsent(c.projectId, () => ProjectRow(c.projectId))
        .totals
        .addCell(c);
  }
  return rows.values.toList()
    ..sort((a, b) => b.totals.totalMin.compareTo(a.totals.totalMin));
}

/// A chart bar: minutes per project in one day or week.
class ChartBucket {
  ChartBucket(this.start);

  final DateTime start;

  /// Project ID (`null` = no project) → minutes.
  final minutes = <String?, int>{};

  int get totalMin => minutes.values.fold(0, (a, b) => a + b);
}

/// Bars for [range]: one per day, or one per week above 62 days (spec §5.3).
List<ChartBucket> chartBuckets(
  Iterable<ReportCell> cells,
  DateRange range, {
  int weekStart = DateTime.monday,
}) {
  final weekly = useWeeklyBuckets(range);
  final buckets = <ChartBucket>[];
  var cursor = weekly
      ? startOfWeek(range.start, weekStart: weekStart)
      : range.start;
  while (cursor.isBefore(range.end)) {
    buckets.add(ChartBucket(cursor));
    cursor = DateTime(cursor.year, cursor.month, cursor.day + (weekly ? 7 : 1));
  }
  for (final c in cells) {
    if (!range.contains(c.day)) continue;
    final key = weekly ? startOfWeek(c.day, weekStart: weekStart) : c.day;
    final b = buckets.firstWhere((b) => b.start == key);
    b.minutes[c.projectId] = (b.minutes[c.projectId] ?? 0) + c.totalMin;
  }
  return buckets;
}

/// Column titles and values that depend on the UI language.
class CsvLabels {
  const CsvLabels({
    required this.headers,
    required this.teamHeaders,
    required this.work,
    required this.standby,
    required this.noProject,
    required this.deletedProject,
  });

  /// Date, Start, End, Duration (h:mm), Hours, Type, Rate, Amount, Project,
  /// Client, Description.
  final List<String> headers;

  /// First name, Last name, Email (team export only).
  final List<String> teamHeaders;
  final String work;
  final String standby;
  final String noProject;
  final String deletedProject;
}

/// A person in a team export.
typedef CsvPerson = ({String firstName, String lastName, String email});

/// CSV of [entries] (spec §5.3): UTF-8 with BOM, CRLF lines, separator and
/// decimal mark from the organization settings. With [people] it is the
/// team export with name and email columns first (spec §5.5).
String entriesCsv({
  required Iterable<TimeEntry> entries,
  required Map<String, Project> projects,
  required OrgSettings settings,
  required CsvLabels labels,
  Map<String, CsvPerson>? people,
}) {
  final sep = settings.csvSeparator;
  final dec = settings.csvDecimal;
  String cell(String v) => _csvCell(v, sep);
  String two(int n) => n.toString().padLeft(2, '0');
  String date(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)}';
  String time(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

  final lines = <String>[
    [
      if (people != null) ...labels.teamHeaders,
      ...labels.headers,
    ].map(cell).join(sep),
  ];
  final sorted = entries.toList()
    ..sort((a, b) {
      final byPerson = people == null
          ? 0
          : _personKey(people[a.uid]).compareTo(_personKey(people[b.uid]));
      return byPerson != 0 ? byPerson : a.start.compareTo(b.start);
    });
  for (final e in sorted) {
    final p = e.projectId == null ? null : projects[e.projectId];
    final projectName = e.projectId == null
        ? labels.noProject
        : (p == null || p.deleted)
        ? labels.deletedProject
        : p.name;
    final person = people?[e.uid];
    lines.add(
      [
        if (people != null) ...[
          person?.firstName ?? '',
          person?.lastName ?? '',
          person?.email ?? '',
        ],
        date(e.start),
        time(e.start),
        time(e.end),
        formatHoursMinutes(e.durationMin),
        formatDecimalHours(e.durationMin, decimalMark: dec),
        e.type == EntryType.work ? labels.work : labels.standby,
        formatMinorPlain(e.rateMinor, decimalMark: dec),
        formatMinorPlain(e.amountMinor, decimalMark: dec),
        projectName,
        p?.client ?? '',
        e.description,
      ].map(cell).join(sep),
    );
  }
  return '﻿${lines.join('\r\n')}\r\n';
}

/// One row of the Team people table and the team summary CSV: a person's
/// hours on one project (spec §5.5, D-044). A person without hours in the
/// range gets one row with [hasHours] false.
class TeamRow {
  const TeamRow({
    required this.uid,
    required this.projectId,
    required this.totals,
    required this.hasHours,
  });

  final String uid;

  /// `null` for entries without a project (or a person without hours).
  final String? projectId;
  final Totals totals;
  final bool hasHours;
}

typedef PersonProjectTotals = Map<String, Map<String?, Totals>>;

PersonProjectTotals cellTotalsByPersonProject(Iterable<ReportCell> cells) {
  final m = <String, Map<String?, Totals>>{};
  for (final c in cells) {
    (m[c.uid] ??= {}).putIfAbsent(c.projectId, Totals.new).addCell(c);
  }
  return m;
}

PersonProjectTotals entryTotalsByPersonProject(Iterable<TimeEntry> entries) {
  final m = <String, Map<String?, Totals>>{};
  for (final e in entries) {
    (m[e.uid] ??= {}).putIfAbsent(e.projectId, Totals.new).add(e);
  }
  return m;
}

/// Rows for [uids] in order, then anyone else with hours; within a person
/// one row per project, sorted by [projectName].
List<TeamRow> teamRows({
  required List<String> uids,
  required PersonProjectTotals totals,
  required String Function(String? projectId) projectName,
}) {
  final order = [...uids, ...totals.keys.where((u) => !uids.contains(u))];
  final rows = <TeamRow>[];
  for (final uid in order) {
    final byProject = totals[uid] ?? const <String?, Totals>{};
    if (byProject.isEmpty) {
      rows.add(
        TeamRow(uid: uid, projectId: null, totals: Totals(), hasHours: false),
      );
      continue;
    }
    final ids = byProject.keys.toList()
      ..sort(
        (a, b) =>
            projectName(a)
                .toLowerCase()
                .compareTo(projectName(b).toLowerCase()),
      );
    for (final id in ids) {
      rows.add(
        TeamRow(
          uid: uid,
          projectId: id,
          totals: byProject[id]!,
          hasHours: true,
        ),
      );
    }
  }
  return rows;
}

/// Column titles of the team summary export.
class TeamCsvLabels {
  const TeamCsvLabels({
    required this.person,
    required this.email,
    required this.project,
    required this.work,
    required this.standby,
    required this.total,
    required this.hours,
    required this.entries,
    required this.workRate,
    required this.standbyRate,
    required this.amount,
    required this.totalRow,
    required this.formerMember,
  });

  final String person;
  final String email;
  final String project;
  final String work;
  final String standby;
  final String total;
  final String hours;
  final String entries;
  final String workRate;
  final String standbyRate;
  final String amount;
  final String totalRow;
  final String formerMember;
}

/// The Team view's People table as CSV (spec §5.5, D-044): one row per
/// person and project ([teamRows]), people without hours included, then a
/// Total row. Work, Standby and Total as h:mm like on screen, plus total
/// decimal hours; the rates are the member's current ones for the project.
String teamSummaryCsv({
  required List<String> uids,
  required Iterable<TimeEntry> entries,
  required Map<String, CsvPerson> people,
  required Map<String, Map<String, ProjectRate>> rates,
  required String Function(String? projectId) projectName,
  required OrgSettings settings,
  required TeamCsvLabels labels,
}) {
  final sep = settings.csvSeparator;
  final dec = settings.csvDecimal;
  String cell(String v) => _csvCell(v, sep);
  String money(int? minor) => minor == null || minor == 0
      ? ''
      : formatMinorPlain(minor, decimalMark: dec);
  final rows = teamRows(
    uids: uids,
    totals: entryTotalsByPersonProject(entries),
    projectName: projectName,
  );
  List<String> hours(Totals t) => [
    formatHoursMinutes(t.workMin),
    formatHoursMinutes(t.standbyMin),
    formatHoursMinutes(t.totalMin),
    formatDecimalHours(t.totalMin, decimalMark: dec),
    '${t.count}',
  ];
  final lines = <String>[
    [
      labels.person,
      labels.email,
      labels.project,
      labels.work,
      labels.standby,
      labels.total,
      labels.hours,
      labels.entries,
      labels.workRate,
      labels.standbyRate,
      labels.amount,
    ].map(cell).join(sep),
  ];
  final all = Totals();
  for (final r in rows) {
    all.addTotals(r.totals);
    final p = people[r.uid];
    final personRates = rates[r.uid];
    final rate = r.hasHours && personRates != null
        ? personRates[r.projectId ?? noProjectKey]
        : null;
    lines.add(
      [
        p == null ? labels.formerMember : '${p.firstName} ${p.lastName}'.trim(),
        p?.email ?? '',
        r.hasHours ? projectName(r.projectId) : '',
        ...hours(r.totals),
        money(rate?.workRateMinor),
        money(rate?.standbyRateMinor),
        formatMinorPlain(r.totals.amountMinor, decimalMark: dec),
      ].map(cell).join(sep),
    );
  }
  lines.add(
    [
      labels.totalRow,
      '',
      '',
      ...hours(all),
      '',
      '',
      formatMinorPlain(all.amountMinor, decimalMark: dec),
    ].map(cell).join(sep),
  );
  return '\uFEFF${lines.join('\r\n')}\r\n';
}

String _personKey(CsvPerson? p) =>
    p == null ? '￿' : '${p.lastName} ${p.firstName}'.toLowerCase();

/// Quotes a cell when needed and defuses spreadsheet formulas.
String _csvCell(String value, String sep) {
  var v = value;
  // A cell starting with = + - @ would run as a formula in Excel.
  if (v.isNotEmpty && '=+-@'.contains(v[0]) && !_isNumber(v)) v = "'$v";
  final needsQuotes =
      v.contains(sep) ||
      v.contains('"') ||
      v.contains('\n') ||
      v.contains('\r') ||
      v.startsWith(' ') ||
      v.endsWith(' ');
  return needsQuotes ? '"${v.replaceAll('"', '""')}"' : v;
}

bool _isNumber(String v) => RegExp(r'^-?\d+([.,]\d+)?$').hasMatch(v);
