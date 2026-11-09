import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/app/tracker_prefs.dart';
import 'package:standwise/data/providers.dart';
import 'package:standwise/domain/models.dart';
import 'package:standwise/domain/projects.dart';
import 'package:standwise/domain/timer.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  late FakeEntriesRepository entries;
  late FakeProjectsRepository projects;

  setUp(() {
    entries = FakeEntriesRepository();
    projects = FakeProjectsRepository(
      projects: [const Project(id: 'p1', name: 'Hospital', color: 0xFF1E88E5)],
      rates: {
        'p1': const ProjectRate(
          projectId: 'p1',
          workRateMinor: 6000,
          standbyRateMinor: 1500,
        ),
      },
    );
  });

  Future<void> pump(WidgetTester tester, {Organization org = testOrg}) =>
      pumpApp(
        tester,
        org: org,
        overrides: [
          entriesRepositoryProvider.overrideWithValue(entries),
          projectsRepositoryProvider.overrideWithValue(projects),
        ],
      );

  Future<void> pickProject(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Enter starts the timer and Stop saves an entry', (tester) async {
    await pump(tester);
    expect(find.text('No hours yet'), findsOneWidget);

    await pickProject(tester, 'Hospital');
    expect(find.text('Your rate: zł60.00/h'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Night shift');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(entries.timer?.description, 'Night shift');
    expect(entries.timer?.projectId, 'p1');
    expect(find.text('Stop'), findsOneWidget);

    // Pretend it has been running for 90 minutes.
    entries.setTimer(
      RunningTimer(
        start: DateTime.now().subtract(const Duration(minutes: 90)),
        projectId: 'p1',
        description: 'Night shift',
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();

    expect(entries.timer, isNull);
    final e = entries.entries.single;
    expect(e.durationMin, 90);
    expect(e.rateMinor, 6000);
    expect(e.type, EntryType.work);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Night shift'), findsOneWidget);
    expect(find.text('1:30'), findsWidgets);
  });

  testWidgets('manual entry adds hours to the chosen day', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Manual entry'));
    await tester.pumpAndSettle();
    expect(find.text('8:00'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Inventory');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    final e = entries.entries.single;
    expect(e.description, 'Inventory');
    expect(e.durationMin, 8 * 60);
    expect(e.start.hour, 8);
    // The only active project is picked automatically.
    expect(e.projectId, 'p1');
  });

  testWidgets('without a project nothing can be started or added', (
    tester,
  ) async {
    projects.projects.clear();
    await pump(tester);
    expect(
      find.text('No projects yet. Add one in Projects first.'),
      findsOneWidget,
    );
    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start'),
    );
    expect(start.onPressed, isNull);
    expect(find.text('No project'), findsNothing);
  });

  testWidgets('remembers the last mode and project', (tester) async {
    projects.projects.add(
      const Project(id: 'p2', name: 'Clinic', color: 0xFF43A047),
    );
    final prefs = MemoryTrackerPrefs({
      TrackerPrefKeys.mode: 'manual',
      TrackerPrefKeys.project('o1'): 'p2',
    });
    await pumpApp(
      tester,
      overrides: [
        entriesRepositoryProvider.overrideWithValue(entries),
        projectsRepositoryProvider.overrideWithValue(projects),
      ],
      prefs: prefs,
    );
    expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
    expect(find.text('Clinic'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(entries.entries.single.projectId, 'p2');

    await pickProject(tester, 'Hospital');
    await tester.tap(find.byIcon(Icons.timer_outlined).first);
    await tester.pumpAndSettle();
    expect(prefs.values[TrackerPrefKeys.project('o1')], 'p1');
    expect(prefs.values[TrackerPrefKeys.mode], 'timer');
  });

  testWidgets('delete shows Undo, which brings the entry back', (tester) async {
    final now = DateTime.now();
    entries.entries.add(
      TimeEntry(
        id: 'x',
        uid: 'u1',
        type: EntryType.standby,
        rateMinor: 1500,
        start: DateTime(now.year, now.month, now.day, 0, 30),
        end: DateTime(now.year, now.month, now.day, 1, 30),
        description: 'Pager duty',
      ),
    );
    await pump(tester);
    expect(find.text('Pager duty'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Pager duty'), findsNothing);
    expect(entries.entries.single.deleted, isTrue);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(entries.entries.single.deleted, isFalse);
    expect(find.text('Pager duty'), findsOneWidget);
  });

  testWidgets('editing the type fills in the current rate', (tester) async {
    final now = DateTime.now();
    entries.entries.add(
      TimeEntry(
        id: 'x',
        uid: 'u1',
        projectId: 'p1',
        type: EntryType.work,
        rateMinor: 5000,
        start: DateTime(now.year, now.month, now.day, 0, 0),
        end: DateTime(now.year, now.month, now.day, 2, 0),
        description: 'Ward round',
      ),
    );
    await pump(tester);
    await tester.tap(find.text('Ward round'));
    await tester.pumpAndSettle();
    expect(find.text('Edit entry'), findsOneWidget);

    await tester.tap(find.text('Standby').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final e = entries.entries.single;
    expect(e.type, EntryType.standby);
    expect(e.rateMinor, 1500);
    expect(e.durationMin, 120);
  });

  testWidgets('Continue while a timer runs saves it first', (tester) async {
    final now = DateTime.now();
    entries.entries.add(
      TimeEntry(
        id: 'x',
        uid: 'u1',
        projectId: 'p1',
        type: EntryType.work,
        rateMinor: 6000,
        start: DateTime(now.year, now.month, now.day, 0, 0),
        end: DateTime(now.year, now.month, now.day, 1, 0),
        description: 'Ward round',
      ),
    );
    entries.timer = RunningTimer(
      start: now.subtract(const Duration(minutes: 30)),
      description: 'Paperwork',
    );
    await pump(tester);

    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();

    expect(entries.timer?.description, 'Ward round');
    expect(entries.timer?.projectId, 'p1');
    final saved = entries.entries.firstWhere((e) => e.id != 'x');
    expect(saved.description, 'Paperwork');
    expect(saved.durationMin, 30);
  });

  testWidgets('a suspended organization cannot start timers', (tester) async {
    await pump(
      tester,
      org: const Organization(
        id: 'o1',
        name: 'ACME',
        status: OrgStatus.suspended,
      ),
    );
    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start'),
    );
    expect(start.onPressed, isNull);
  });
}
