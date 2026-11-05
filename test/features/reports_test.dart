import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/data/providers.dart';
import 'package:standwise/domain/date_ranges.dart';
import 'package:standwise/domain/models.dart';
import 'package:standwise/domain/projects.dart';
import 'package:standwise/features/common/csv_export.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

class _FakeSaver implements CsvSaver {
  final saved = <(String, String)>[];

  @override
  Future<bool> save(BuildContext context, String fileName, String csv) async {
    saved.add((fileName, csv));
    return true;
  }
}

void main() {
  testWidgets('this week totals, project filter and CSV export', (
    tester,
  ) async {
    final monday = startOfWeek(DateTime.now());
    TimeEntry e(
      String id,
      int day,
      int min, {
      String? project,
      EntryType t = EntryType.work,
    }) {
      final start = DateTime(monday.year, monday.month, monday.day + day, 9);
      return TimeEntry(
        id: id,
        uid: 'u1',
        projectId: project,
        type: t,
        rateMinor: 6000,
        start: start,
        end: start.add(Duration(minutes: min)),
        description: 'Task $id',
      );
    }

    final entries = FakeEntriesRepository(
      entries: [
        e('a', 0, 120, project: 'p1'),
        e('b', 1, 60, project: 'p1', t: EntryType.standby),
        e('c', 1, 30),
        // Other people and last week are not in my report.
        TimeEntry(
          id: 'other',
          uid: 'u2',
          type: EntryType.work,
          rateMinor: 1,
          start: monday.add(const Duration(hours: 9)),
          end: monday.add(const Duration(hours: 10)),
        ),
        e('old', -3, 600),
      ],
    );
    final saver = _FakeSaver();
    await pumpApp(
      tester,
      size: const Size(1200, 1400),
      overrides: [
        entriesRepositoryProvider.overrideWithValue(entries),
        projectsRepositoryProvider.overrideWithValue(
          FakeProjectsRepository(
            projects: [
              const Project(id: 'p1', name: 'Hospital', client: 'St. Mary'),
            ],
          ),
        ),
        csvSaverProvider.overrideWithValue(saver),
      ],
    );
    await tester.tap(find.text('My reports'));
    await tester.pumpAndSettle();

    // Total 3:30, Work 2:30, Standby 1:00.
    expect(find.text('3:30'), findsWidgets);
    expect(find.text('3.50 h · 3 entries'), findsOneWidget);
    expect(find.text('St. Mary'), findsOneWidget);

    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();
    final (name, csv) = saver.saved.single;
    expect(name, startsWith('standwise-my-hours-'));
    expect(csv.split('\r\n').where((l) => l.isNotEmpty).length, 4);
    expect(csv, contains('Task a'));
    expect(csv, isNot(contains('Task old')));

    await tester.tap(find.text('All projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No project').last);
    await tester.pumpAndSettle();
    expect(find.text('0.50 h · 1 entry'), findsOneWidget);
  });

  testWidgets('an empty range says so and disables export', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        entriesRepositoryProvider.overrideWithValue(FakeEntriesRepository()),
      ],
    );
    await tester.tap(find.text('My reports'));
    await tester.pumpAndSettle();
    expect(find.text('No entries in this range.'), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Export CSV'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
