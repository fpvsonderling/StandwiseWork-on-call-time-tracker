import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/data/providers.dart';
import 'package:standwise/domain/models.dart';
import 'package:standwise/domain/projects.dart';
import 'package:standwise/domain/summaries.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

void main() {
  final bob = membershipOf(
    'o1',
    uid: 'u2',
    role: OrgRole.employee,
    firstName: 'Bob',
    lastName: 'Nowak',
    email: 'bob@example.com',
  );
  final cleo = membershipOf(
    'o1',
    uid: 'u3',
    role: OrgRole.employee,
    firstName: 'Cleo',
    lastName: 'Zielinska',
    email: 'cleo@example.com',
  );

  testWidgets('admins see everyone, totals from summaries, one person', (
    tester,
  ) async {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final key = _monthKey(month);
    final entries = FakeEntriesRepository(
      summaries: [
        MonthSummary(
          uid: 'u2',
          monthKey: key,
          days: {
            1: {
              'p1': const SummaryBucket(
                workMin: 120,
                amountMinor: 12000,
                count: 1,
              ),
              noProjectKey: const SummaryBucket(standbyMin: 60, count: 1),
            },
          },
        ),
        // Last month is outside "This month".
        MonthSummary(
          uid: 'u2',
          monthKey: _monthKey(DateTime(month.year, month.month - 1)),
          days: {
            3: {'p1': const SummaryBucket(workMin: 999, count: 1)},
          },
        ),
      ],
      entries: [
        TimeEntry(
          id: 'b1',
          uid: 'u2',
          projectId: 'p1',
          type: EntryType.work,
          rateMinor: 6000,
          start: month.add(const Duration(hours: 9)),
          end: month.add(const Duration(hours: 11)),
          description: 'Night shift handover',
        ),
      ],
    );
    await pumpApp(
      tester,
      size: const Size(1200, 1600),
      otherMembers: [bob, cleo],
      overrides: [
        entriesRepositoryProvider.overrideWithValue(entries),
        projectsRepositoryProvider.overrideWithValue(
          FakeProjectsRepository(
            projects: [const Project(id: 'p1', name: 'Hospital')],
          ),
        ),
      ],
    );
    await tester.tap(find.text('Team').first);
    await tester.pumpAndSettle();

    // Everyone active is listed, even at zero.
    expect(find.text('Anna Kowalska'), findsWidgets);
    expect(find.text('Bob Nowak'), findsWidgets);
    expect(find.text('Cleo Zielinska'), findsWidgets);
    // Bob: 2h work + 1h standby this month; last month not counted.
    expect(find.text('3:00'), findsWidgets);
    expect(find.textContaining('16:39'), findsNothing);

    await tester.tap(find.text('Bob Nowak').last);
    await tester.pumpAndSettle();
    expect(find.text('Entries of Bob Nowak'), findsOneWidget);
    expect(find.text('Night shift handover'), findsOneWidget);
  });

  testWidgets('employees have no Team tab', (tester) async {
    await pumpApp(tester, role: OrgRole.employee);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Team'),
      ),
      findsNothing,
    );
    expect(find.text('Timer'), findsWidgets);
  });

  testWidgets('owner makes an employee admin and removes another', (
    tester,
  ) async {
    late FakeOrgRepository orgs;
    await pumpApp(tester, otherMembers: [bob, cleo], onOrgs: (o) => orgs = o);
    await goTo(tester, 'Settings');
    await tester.tap(find.text('Members and invites'));
    await tester.pumpAndSettle();

    Finder menuOf(String name) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
      matching: find.byTooltip('Member actions'),
    );

    await tester.tap(menuOf('Bob Nowak'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make admin'));
    await tester.pumpAndSettle();
    expect(orgs.calls, contains('setMemberRole:u2:admin'));

    await tester.tap(menuOf('Cleo Zielinska'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(find.text('Remove Cleo Zielinska?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(orgs.calls, contains('removeMember:u3'));
    expect(find.text('Cleo Zielinska'), findsNothing);
  });

  testWidgets('admin saves organization settings', (tester) async {
    late FakeOrgRepository orgs;
    await pumpApp(tester, role: OrgRole.admin, onOrgs: (o) => orgs = o);
    await goTo(tester, 'Settings');
    await tester.tap(find.text('Organization settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Company name'),
      'ACME Medical',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(orgs.calls, contains('updateOrganization:o1:ACME Medical:PLN'));
  });

  testWidgets('owner deletes the organization only with the right name', (
    tester,
  ) async {
    late FakeOrgRepository orgs;
    await pumpApp(tester, onOrgs: (o) => orgs = o);
    await goTo(tester, 'Settings');
    await tester.scrollUntilVisible(
      find.text('Delete organization'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete organization'));
    await tester.pumpAndSettle();
    expect(find.text('Delete ACME?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'ACME');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(orgs.calls, contains('deleteOrganization:o1:ACME'));
  });

  testWidgets('an employee leaves the organization', (tester) async {
    late FakeOrgRepository orgs;
    await pumpApp(tester, role: OrgRole.employee, onOrgs: (o) => orgs = o);
    await goTo(tester, 'Settings');
    expect(find.text('Delete organization'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Leave organization'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Leave organization'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Leave organization'));
    await tester.pumpAndSettle();
    expect(orgs.calls, contains('leaveOrganization:o1'));
  });
}
