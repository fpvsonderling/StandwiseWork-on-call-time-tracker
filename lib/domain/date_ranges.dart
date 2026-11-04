/// Report ranges (spec §5.3) and calendar helpers.
///
/// All functions work on local wall-clock dates. Converting to the
/// organization's timezone happens before calling them.
library;

/// Preset report ranges.
enum RangePreset { thisWeek, lastWeek, thisMonth, lastMonth }

/// A half-open date range `[start, end)` at midnight boundaries.
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// Number of calendar days covered.
  int get days => _dayIndex(end) - _dayIndex(start);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start – $end)';
}

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// First day of the week containing [day]. [weekStart] uses
/// [DateTime.monday]..[DateTime.sunday] (default Monday, spec §1).
DateTime startOfWeek(DateTime day, {int weekStart = DateTime.monday}) {
  final d = dateOnly(day);
  final offset = (d.weekday - weekStart + 7) % 7;
  return DateTime(d.year, d.month, d.day - offset);
}

DateRange weekRange(DateTime day, {int weekStart = DateTime.monday}) {
  final s = startOfWeek(day, weekStart: weekStart);
  return DateRange(s, DateTime(s.year, s.month, s.day + 7));
}

DateRange monthRange(DateTime day) =>
    DateRange(DateTime(day.year, day.month), DateTime(day.year, day.month + 1));

DateRange presetRange(
  RangePreset preset,
  DateTime now, {
  int weekStart = DateTime.monday,
}) {
  switch (preset) {
    case RangePreset.thisWeek:
      return weekRange(now, weekStart: weekStart);
    case RangePreset.lastWeek:
      final s = startOfWeek(now, weekStart: weekStart);
      return weekRange(
        DateTime(s.year, s.month, s.day - 7),
        weekStart: weekStart,
      );
    case RangePreset.thisMonth:
      return monthRange(now);
    case RangePreset.lastMonth:
      return monthRange(DateTime(now.year, now.month - 1));
  }
}

/// Custom range from inclusive [first] to inclusive [last] day.
DateRange customRange(DateTime first, DateTime last) {
  final a = dateOnly(first);
  final b = dateOnly(last);
  final lo = a.isAfter(b) ? b : a;
  final hi = a.isAfter(b) ? a : b;
  return DateRange(lo, DateTime(hi.year, hi.month, hi.day + 1));
}

/// Charts switch from per-day to per-week buckets above 62 days (spec §5.3).
bool useWeeklyBuckets(DateRange range) => range.days > 62;

/// `YYYY-MM` key used by entries and summaries (spec §6).
String monthKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}';

/// Day index independent of DST (days since epoch in UTC terms).
int _dayIndex(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;
