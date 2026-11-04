import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/domain/durations.dart';

void main() {
  test('formatClock', () {
    expect(formatClock(Duration.zero), '0:00:00');
    expect(formatClock(const Duration(minutes: 5, seconds: 7)), '0:05:07');
    expect(formatClock(const Duration(hours: 12)), '12:00:00');
    expect(formatClock(const Duration(seconds: -5)), '0:00:00');
  });

  test('formatHoursMinutes', () {
    expect(formatHoursMinutes(0), '0:00');
    expect(formatHoursMinutes(450), '7:30');
    expect(formatHoursMinutes(7505), '125:05');
  });

  test('formatDecimalHours', () {
    expect(formatDecimalHours(90), '1.50');
    expect(formatDecimalHours(1), '0.02');
    expect(formatDecimalHours(20, decimalMark: ','), '0,33');
    expect(formatDecimalHours(600), '10.00');
  });

  test('elapsedSince is computed from start, never negative', () {
    final start = DateTime.utc(2026, 11, 3, 8);
    expect(
      elapsedSince(start, DateTime.utc(2026, 11, 3, 9, 30, 15)),
      const Duration(hours: 1, minutes: 30, seconds: 15),
    );
    expect(elapsedSince(start, DateTime.utc(2026, 11, 3, 7)), Duration.zero);
  });

  group('manualEntryBounds', () {
    final date = DateTime(2026, 11, 3);

    test('same day', () {
      final b = manualEntryBounds(
        date: date,
        from: (hour: 9, minute: 0),
        to: (hour: 17, minute: 30),
      );
      expect(b.start, DateTime(2026, 11, 3, 9));
      expect(b.end, DateTime(2026, 11, 3, 17, 30));
    });

    test('crosses midnight when to <= from', () {
      final b = manualEntryBounds(
        date: date,
        from: (hour: 22, minute: 0),
        to: (hour: 6, minute: 0),
      );
      expect(b.start, DateTime(2026, 11, 3, 22));
      expect(b.end, DateTime(2026, 11, 4, 6));
      expect(durationMinutes(b.start, b.end), 8 * 60);
    });

    test('to == from means a full 24h shift', () {
      final b = manualEntryBounds(
        date: date,
        from: (hour: 8, minute: 0),
        to: (hour: 8, minute: 0),
      );
      expect(durationMinutes(b.start, b.end), 24 * 60);
      expect(validateSpan(b.start, b.end), isNull);
    });

    test('end of month rolls over', () {
      final b = manualEntryBounds(
        date: DateTime(2026, 12, 31),
        from: (hour: 23, minute: 0),
        to: (hour: 1, minute: 0),
      );
      expect(b.end, DateTime(2027, 1, 1, 1));
    });
  });

  test('validateSpan', () {
    final s = DateTime.utc(2026, 11, 3, 8);
    expect(validateSpan(s, s), SpanError.endNotAfterStart);
    expect(
      validateSpan(s, s.subtract(const Duration(minutes: 1))),
      SpanError.endNotAfterStart,
    );
    expect(
      validateSpan(s, s.add(const Duration(hours: 24, minutes: 1))),
      SpanError.longerThan24h,
    );
    expect(validateSpan(s, s.add(const Duration(hours: 24))), isNull);
  });
}
