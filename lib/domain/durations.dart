/// Duration formatting and time-entry arithmetic.
library;

/// Longest allowed single entry (spec §3.2).
const int maxEntryMinutes = 24 * 60;

/// `H:MM:SS` for the running timer clock, e.g. `0:05:07`, `12:00:00`.
String formatClock(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return '$h:${_two(m)}:${_two(s)}';
}

/// `h:mm` for totals, e.g. `7:30`, `125:05`.
String formatHoursMinutes(int minutes) {
  final negative = minutes < 0;
  final abs = minutes.abs();
  return '${negative ? '-' : ''}${abs ~/ 60}:${_two(abs % 60)}';
}

/// Decimal hours with two decimals, e.g. 90 min → `1.50`. Integer maths only.
String formatDecimalHours(int minutes, {String decimalMark = '.'}) {
  final negative = minutes < 0;
  final abs = minutes.abs();
  // hundredths of an hour, rounded half up
  final hundredths = (abs * 100 + 30) ~/ 60;
  final whole = hundredths ~/ 100;
  final frac = _two(hundredths % 100);
  return '${negative ? '-' : ''}$whole$decimalMark$frac';
}

/// Elapsed time of a running timer, computed from its stored [start] rather
/// than by counting ticks, so it stays correct after sleep and while offline.
Duration elapsedSince(DateTime start, DateTime now) {
  final d = now.difference(start);
  return d.isNegative ? Duration.zero : d;
}

/// Whole minutes between [start] and [end], truncated.
int durationMinutes(DateTime start, DateTime end) =>
    end.difference(start).inMinutes;

/// Builds start/end for a manual entry from a [date] and wall-clock times.
///
/// If [to] is at or before [from], the entry crosses midnight and ends on
/// the next day (spec §5.1).
({DateTime start, DateTime end}) manualEntryBounds({
  required DateTime date,
  required ({int hour, int minute}) from,
  required ({int hour, int minute}) to,
}) {
  final start = DateTime(
    date.year,
    date.month,
    date.day,
    from.hour,
    from.minute,
  );
  final sameDayEnd = DateTime(
    date.year,
    date.month,
    date.day,
    to.hour,
    to.minute,
  );
  final crossesMidnight =
      (to.hour * 60 + to.minute) <= (from.hour * 60 + from.minute);
  final end = crossesMidnight
      ? DateTime(date.year, date.month, date.day + 1, to.hour, to.minute)
      : sameDayEnd;
  return (start: start, end: end);
}

/// Validation problems for an entry's time span.
enum SpanError { endNotAfterStart, longerThan24h }

/// Returns `null` when the span is valid for a time entry.
SpanError? validateSpan(DateTime start, DateTime end) {
  if (!end.isAfter(start)) return SpanError.endNotAfterStart;
  if (end.difference(start) > const Duration(minutes: maxEntryMinutes)) {
    return SpanError.longerThan24h;
  }
  return null;
}

String _two(int n) => n.toString().padLeft(2, '0');
