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
List<ProjectRow> projectRows(Iterable<TimeEntry> entries) {
  final rows = <String?, ProjectRow>{};
  for (final e in entries) {
    rows.putIfAbsent(e.projectId, () => ProjectRow(e.projectId)).totals.add(e);
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
  Iterable<TimeEntry> entries,
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
  for (final e in entries) {
    if (!range.contains(e.start)) continue;
    final key = weekly
        ? startOfWeek(e.start, weekStart: weekStart)
        : dateOnly(e.start);
    final b = buckets.firstWhere((b) => b.start == key);
    b.minutes[e.projectId] = (b.minutes[e.projectId] ?? 0) + e.durationMin;
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
