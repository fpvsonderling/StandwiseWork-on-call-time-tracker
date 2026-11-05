import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/domain/date_ranges.dart';
import 'package:standwise/domain/models.dart';
import 'package:standwise/domain/projects.dart';
import 'package:standwise/domain/reports.dart';
import 'package:standwise/domain/timer.dart';

TimeEntry _e(
  String id,
  DateTime start,
  int minutes, {
  EntryType type = EntryType.work,
  String? project,
  int rate = 6000,
  String uid = 'u1',
  String description = '',
}) => TimeEntry(
  id: id,
  uid: uid,
  projectId: project,
  type: type,
  rateMinor: rate,
  start: start,
  end: start.add(Duration(minutes: minutes)),
  description: description,
);

const _labels = CsvLabels(
  headers: [
    'Date', 'Start', 'End', 'Duration (h:mm)', 'Hours', 'Type', 'Rate', //
    'Amount', 'Project', 'Client', 'Description',
  ],
  teamHeaders: ['First name', 'Last name', 'Email'],
  work: 'Work',
  standby: 'Standby',
  noProject: 'No project',
  deletedProject: 'No project (deleted)',
);

void main() {
  test('totals split Work and Standby and add money', () {
    final t = totalsOf([
      _e('a', DateTime(2026, 11, 2, 8), 90),
      _e(
        'b',
        DateTime(2026, 11, 2, 20),
        60,
        type: EntryType.standby,
        rate: 1500,
      ),
    ]);
    expect(t.workMin, 90);
    expect(t.standbyMin, 60);
    expect(t.totalMin, 150);
    expect(t.amountMinor, 9000 + 1500);
    expect(t.count, 2);
  });

  test(
    'groups by start day, newest first; midnight entries stay on start day',
    () {
      final groups = groupByDay([
        _e('a', DateTime(2026, 11, 2, 8), 60),
        _e('b', DateTime(2026, 11, 3, 23), 120),
        _e('c', DateTime(2026, 11, 3, 9), 30),
      ]);
      expect(groups.map((g) => g.day), [
        DateTime(2026, 11, 3),
        DateTime(2026, 11, 2),
      ]);
      expect(groups.first.entries.map((e) => e.id), ['b', 'c']);
      expect(groups.first.totals.totalMin, 150);
    },
  );

  test('week bars cover seven days from the week start', () {
    final week = weekRange(DateTime(2026, 11, 4));
    final bars = weekBars([
      _e('a', DateTime(2026, 11, 2, 8), 60),
      _e('b', DateTime(2026, 11, 2, 20), 30, type: EntryType.standby),
      _e('c', DateTime(2026, 11, 9, 8), 60), // next week
    ], week);
    expect(bars.length, 7);
    expect(bars.first.day, DateTime(2026, 11, 2));
    expect(bars.first.workMin, 60);
    expect(bars.first.standbyMin, 30);
    expect(bars.skip(1).every((b) => b.totalMin == 0), isTrue);
  });

  test('project filter and table', () {
    final entries = [
      _e('a', DateTime(2026, 11, 2), 60, project: 'p1'),
      _e('b', DateTime(2026, 11, 2), 120),
      _e('c', DateTime(2026, 11, 3), 30, project: 'p1'),
    ];
    expect(entries.where((e) => matchesProject(e, null)).length, 3);
    expect(
      entries.where((e) => matchesProject(e, noProjectKey)).single.id,
      'b',
    );
    expect(entries.where((e) => matchesProject(e, 'p1')).length, 2);
    final rows = projectRows(entries);
    expect(rows.map((r) => r.projectId), [null, 'p1']);
    expect(rows.last.totals.totalMin, 90);
  });

  test('chart uses days, or weeks above 62 days', () {
    final daily = chartBuckets([
      _e('a', DateTime(2026, 11, 3, 8), 60, project: 'p1'),
    ], monthRange(DateTime(2026, 11)));
    expect(daily.length, 30);
    expect(daily[2].minutes, {'p1': 60});

    final range = customRange(DateTime(2026, 1, 1), DateTime(2026, 6, 30));
    final weekly = chartBuckets([_e('a', DateTime(2026, 1, 7), 60)], range);
    expect(weekly.first.start, DateTime(2025, 12, 29));
    expect(weekly.first.totalMin, 0);
    expect(weekly[1].totalMin, 60);
  });

  test('CSV has a BOM, CRLF lines and the organization format', () {
    final csv = entriesCsv(
      entries: [
        _e(
          'a',
          DateTime(2026, 11, 2, 8, 5),
          95,
          project: 'p1',
          rate: 4550,
          description: 'Shift; "night"',
        ),
        _e(
          'b',
          DateTime(2026, 11, 1, 22),
          60,
          project: 'gone',
          description: '=1+1',
        ),
      ],
      projects: {
        'p1': const Project(id: 'p1', name: 'Hospital', client: 'St. Mary'),
      },
      settings: const OrgSettings(csvSeparator: ';', csvDecimal: ','),
      labels: _labels,
    );
    expect(csv.startsWith('﻿Date;Start;End;'), isTrue);
    final lines = csv.substring(1).split('\r\n');
    expect(lines.length, 4); // header, 2 rows, trailing empty
    expect(
      lines[1],
      "2026-11-01;22:00;23:00;1:00;1,00;Work;60,00;60,00;No project (deleted);;'=1+1",
    );
    expect(
      lines[2],
      '2026-11-02;08:05;09:40;1:35;1,58;Work;45,50;72,04;Hospital;St. Mary;'
      '"Shift; ""night"""',
    );
  });

  test('team CSV puts people first, sorted by last name', () {
    final csv = entriesCsv(
      entries: [
        _e('a', DateTime(2026, 11, 2), 60, uid: 'u1'),
        _e('b', DateTime(2026, 11, 1), 60, uid: 'u2'),
      ],
      projects: const {},
      settings: const OrgSettings(),
      labels: _labels,
      people: {
        'u1': (firstName: 'Zoe', lastName: 'Zielińska', email: 'z@x.pl'),
        'u2': (firstName: 'Adam', lastName: 'Adamski', email: 'a@x.pl'),
      },
    );
    final lines = csv.substring(1).split('\r\n');
    expect(lines[0], startsWith('First name,Last name,Email,Date'));
    expect(lines[1], startsWith('Adam,Adamski,a@x.pl,2026-11-01'));
    expect(lines[2], startsWith('Zoe,Zielińska,z@x.pl,2026-11-02'));
  });

  test('a stopped timer never exceeds 24 hours', () {
    final t = RunningTimer(start: DateTime(2026, 11, 1, 8));
    expect(t.stopTime(DateTime(2026, 11, 1, 10)), DateTime(2026, 11, 1, 10));
    expect(t.stopTime(DateTime(2026, 11, 3)), DateTime(2026, 11, 2, 8));
  });

  test('current rate falls back to zero', () {
    final rates = {
      'p1': const ProjectRate(
        projectId: 'p1',
        workRateMinor: 100,
        standbyRateMinor: 50,
      ),
      noProjectKey: const ProjectRate(
        projectId: noProjectKey,
        workRateMinor: 7,
      ),
    };
    expect(currentRate(rates, 'p1', EntryType.standby), 50);
    expect(currentRate(rates, null, EntryType.work), 7);
    expect(currentRate(rates, 'p2', EntryType.work), 0);
  });
}
