import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/data/providers.dart';
import 'package:standwise/domain/models.dart';
import 'package:standwise/domain/projects.dart';
import 'package:standwise/domain/summaries.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  TimeEntry entry(
    String id, {
    String uid = 'u1',
    String description = 'Night shift',
    EntryApproval? approval,
    EntryEdit? edit,
    EntrySnapshot? editedFrom,
    bool deleted = false,
    String? deletedBy,
    int startHour = 8,
  }) => TimeEntry(
    id: id,
    uid: uid,
    projectId: 'p1',
    type: EntryType.work,
    rateMinor: 6000,
    start: day.add(Duration(hours: startHour)),
    end: day.add(Duration(hours: startHour + 2)),
    description: description,
    approval: approval,
    edit: edit,
    editedFrom: editedFrom,
    deleted: deleted,
    deletedBy: deletedBy,
  );
  const boss = EntryEdit(byUid: 'u9', byName: 'Boss Admin', comment: 'Typo');
  const approved = EntryApproval(byUid: 'u9', byName: 'Boss Admin');
  const project = Project(id: 'p1', name: 'Hospital');

  testWidgets('employees see approved, changed and deleted entries', (
    tester,
  ) async {
    final original = entry('c', description: 'Nite shift', startHour: 12);
    final entries = FakeEntriesRepository(
      entries: [
        entry('a', description: 'Locked work', approval: approved),
        entry(
          'c',
          description: 'Night shift',
          startHour: 12,
          edit: boss,
          editedFrom: original.snapshot,
        ),
        entry(
          'd',
          description: 'Twice',
          startHour: 16,
          deleted: true,
          deletedBy: 'u9',
          edit: boss,
        ),
      ],
    );
    final projects = FakeProjectsRepository(
      projects: [project],
      rates: {
        'p1': const ProjectRate(
          projectId: 'p1',
          workRateMinor: 6000,
          standbyRateMinor: 1500,
        ),
      },
    );
    await pumpApp(
      tester,
      role: OrgRole.employee,
      size: const Size(500, 1400),
      overrides: [
        entriesRepositoryProvider.overrideWithValue(entries),
        projectsRepositoryProvider.overrideWithValue(projects),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Changed by Boss Admin: Typo'), findsOneWidget);
    expect(find.text('Before: “Nite shift”'), findsOneWidget);
    expect(find.text('Deleted by Boss Admin: Typo'), findsOneWidget);
    // The deleted entry is listed but not counted: 4h of 6h.
    expect(find.textContaining('4:00'), findsWidgets);
    expect(find.text('6:00'), findsNothing);
    // Only the open entry can be deleted, and the locked one not opened.
    expect(find.byTooltip('Delete'), findsOneWidget);
    await tester.tap(find.text('Locked work'));
    await tester.pumpAndSettle();
    expect(find.text('Edit entry'), findsNothing);

    // A pending rate is shown as such, and saving one keeps it pending.
    expect(find.textContaining('pending approval'), findsOneWidget);
    await goTo(tester, 'Projects & rates');
    expect(find.text('Pending approval'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Work'), '70');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(projects.rates['p1']?.workRateMinor, 7000);
    expect(projects.rates['p1']?.status, RateStatus.pending);
  });

  testWidgets('an admin’s own rate is approved when saved', (tester) async {
    final projects = FakeProjectsRepository(projects: [project]);
    await pumpApp(
      tester,
      size: const Size(500, 1000),
      overrides: [projectsRepositoryProvider.overrideWithValue(projects)],
    );
    await goTo(tester, 'Projects & rates');
    await tester.enterText(find.widgetWithText(TextField, 'Work'), '55');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(projects.rates['p1']?.status, RateStatus.approved);
    expect(projects.rates['p1']?.review?.byName, 'Anna Kowalska');
  });

  testWidgets('admins approve rates and hours, and delete entries', (
    tester,
  ) async {
    final bob = membershipOf(
      'o1',
      uid: 'u2',
      role: OrgRole.employee,
      firstName: 'Bob',
      lastName: 'Nowak',
      email: 'bob@example.com',
    );
    final entries = FakeEntriesRepository(
      entries: [
        entry('b1', uid: 'u2', description: 'Handover'),
        entry('b2', uid: 'u2', description: 'Cabling', startHour: 12),
      ],
      summaries: [
        MonthSummary(
          uid: 'u2',
          monthKey: '${day.year}-${day.month.toString().padLeft(2, '0')}',
          days: {
            day.day: {
              'p1': const SummaryBucket(
                workMin: 240,
                amountMinor: 24000,
                count: 2,
              ),
            },
          },
        ),
      ],
    );
    final projects = FakeProjectsRepository(
      projects: [project],
      memberRates: {
        'u2': {
          'p1': const ProjectRate(
            projectId: 'p1',
            workRateMinor: 6000,
            standbyRateMinor: 2000,
          ),
        },
      },
    );
    await pumpApp(
      tester,
      size: const Size(1400, 1800),
      otherMembers: [bob],
      overrides: [
        entriesRepositoryProvider.overrideWithValue(entries),
        projectsRepositoryProvider.overrideWithValue(projects),
      ],
    );
    await tester.tap(find.text('Team').first);
    await tester.pumpAndSettle();

    // Bob's pending rate: amounts are marked until it is approved.
    expect(find.text('Rates awaiting approval (1)'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(projects.memberRates['u2']?['p1']?.status, RateStatus.approved);
    expect(find.textContaining('Rates awaiting approval'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    // Approve all of Bob's hours this month.
    await tester.tap(find.text('Bob Nowak').last);
    await tester.pumpAndSettle();
    expect(find.text('0 of 2 approved'), findsOneWidget);
    await tester.ensureVisible(find.text('Approve hours (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve hours (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Approve 2 entries of Bob Nowak?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(entries.entries.every((e) => e.isApproved), isTrue);
    expect(entries.entries.first.approval?.byName, 'Anna Kowalska');
    expect(find.text('2 of 2 approved'), findsOneWidget);

    // Reopen one, then delete it with a comment.
    await tester.ensureVisible(find.byTooltip('Reopen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reopen').first);
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 approved'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Edit entry').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit entry').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Comment (optional)'),
      'Entered twice',
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    final removed = entries.entries.firstWhere((e) => e.deleted);
    expect(removed.deletedBy, 'u1');
    expect(removed.edit?.comment, 'Entered twice');
    expect(removed.deletedByAdmin, isTrue);
  });
}
