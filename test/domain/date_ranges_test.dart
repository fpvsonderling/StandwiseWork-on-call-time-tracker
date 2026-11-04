import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/domain/date_ranges.dart';

void main() {
  // Wednesday, 4 November 2026
  final now = DateTime(2026, 11, 4, 15, 30);

  test('startOfWeek honours weekStart', () {
    expect(startOfWeek(now), DateTime(2026, 11, 2)); // Monday
    expect(startOfWeek(now, weekStart: DateTime.sunday), DateTime(2026, 11, 1));
    // Monday itself
    expect(startOfWeek(DateTime(2026, 11, 2, 0, 1)), DateTime(2026, 11, 2));
    // Sunday with Monday start belongs to the previous week
    expect(startOfWeek(DateTime(2026, 11, 8)), DateTime(2026, 11, 2));
  });

  test('presets', () {
    expect(
      presetRange(RangePreset.thisWeek, now),
      DateRange(DateTime(2026, 11, 2), DateTime(2026, 11, 9)),
    );
    expect(
      presetRange(RangePreset.lastWeek, now),
      DateRange(DateTime(2026, 10, 26), DateTime(2026, 11, 2)),
    );
    expect(
      presetRange(RangePreset.thisMonth, now),
      DateRange(DateTime(2026, 11), DateTime(2026, 12)),
    );
    expect(
      presetRange(RangePreset.lastMonth, DateTime(2026, 1, 10)),
      DateRange(DateTime(2025, 12), DateTime(2026, 1)),
    );
  });

  test('week across DST change has 7 days', () {
    // Europe DST ended 25 Oct 2026
    final r = weekRange(DateTime(2026, 10, 25));
    expect(r.days, 7);
  });

  test('customRange is inclusive and order-independent', () {
    final r = customRange(DateTime(2026, 11, 10), DateTime(2026, 11, 1));
    expect(r.start, DateTime(2026, 11, 1));
    expect(r.end, DateTime(2026, 11, 11));
    expect(r.days, 10);
    expect(r.contains(DateTime(2026, 11, 10, 23, 59)), isTrue);
    expect(r.contains(DateTime(2026, 11, 11)), isFalse);
  });

  test('weekly buckets above 62 days', () {
    expect(
      useWeeklyBuckets(customRange(DateTime(2026, 1, 1), DateTime(2026, 3, 3))),
      isFalse,
    ); // 62
    expect(
      useWeeklyBuckets(customRange(DateTime(2026, 1, 1), DateTime(2026, 3, 4))),
      isTrue,
    ); // 63
  });

  test('monthKey', () {
    expect(monthKey(DateTime(2026, 3, 9)), '2026-03');
    expect(monthKey(DateTime(2026, 12, 31)), '2026-12');
  });
}
