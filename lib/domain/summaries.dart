/// Monthly summaries written by the `onEntryWritten` function (spec §6):
/// `orgs/{orgId}/summaries/{uid}_{YYYY-MM}`.
library;

import 'date_ranges.dart';
import 'projects.dart';
import 'reports.dart';

/// Minutes and money of one project on one day.
class SummaryBucket {
  const SummaryBucket({
    this.workMin = 0,
    this.standbyMin = 0,
    this.amountMinor = 0,
    this.count = 0,
  });

  final int workMin;
  final int standbyMin;
  final int amountMinor;
  final int count;
}

class MonthSummary {
  const MonthSummary({
    required this.uid,
    required this.monthKey,
    required this.days,
  });

  final String uid;

  /// `YYYY-MM`.
  final String monthKey;

  /// Day of month → project ID (or [noProjectKey]) → bucket.
  final Map<int, Map<String, SummaryBucket>> days;

  /// One cell per day and project.
  Iterable<ReportCell> cells() sync* {
    final year = int.parse(monthKey.substring(0, 4));
    final month = int.parse(monthKey.substring(5, 7));
    for (final MapEntry(key: day, value: projects) in days.entries) {
      for (final MapEntry(key: project, value: b) in projects.entries) {
        yield ReportCell(
          uid: uid,
          day: DateTime(year, month, day),
          projectId: project == noProjectKey ? null : project,
          workMin: b.workMin,
          standbyMin: b.standbyMin,
          amountMinor: b.amountMinor,
          count: b.count,
        );
      }
    }
  }
}

/// `YYYY-MM` keys of every month [range] touches.
List<String> monthKeysIn(DateRange range) {
  final keys = <String>[];
  var m = DateTime(range.start.year, range.start.month);
  while (m.isBefore(range.end)) {
    keys.add(monthKey(m));
    m = DateTime(m.year, m.month + 1);
  }
  return keys;
}
