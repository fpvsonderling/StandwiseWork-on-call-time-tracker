import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/data/providers.dart';
import 'package:standwise/domain/models.dart';
import 'package:standwise/domain/projects.dart';
import 'package:standwise/domain/summaries.dart';
import 'package:standwise/features/common/csv_export.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

class _FakeSaver implements CsvSaver {
  final saved = <(String, String)>[];

  @override
  Future<bool> save(BuildContext context, String fileName, String csv) async {
    saved.add((fileName, csv));
    return true;
  }
}

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
    final saver = _FakeSaver();
    await pumpApp(
      tester,
      size: const Size(1200, 1600),
      otherMembers: [bob, cleo],
      overrides: [
        csvSaverProvider.overrideWithValue(saver),
        entriesRepositoryProvider.overrideWithValue(entries),
        projectsRepositoryProvider.overrideWithValue(
          FakeProjectsRepository(
            projects: [const Project(id: 'p1', name: 'Hospital')],
            memberRates: {
              'u2': {
                'p1': const ProjectRate(
                  projectId: 'p1',
                  workRateMinor: 6000,
                  standbyRateMinor: 2500,
                ),
              },
            },
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
    // Bob: 2h work on Hospital and 1h standby without a project this
    // month, one row each; last month not counted.
    expect(find.text('Bob Nowak'), findsNWidgets(2)); // one row per project
    expect(find.text('Hospital'), findsWidgets);
    expect(find.text('3:00'), findsWidgets); // Total row
    expect(find.textContaining('16:39'), findsNothing);
    // Bob's current Hospital rates are shown.
    expect(find.textContaining('25.00'), findsWidgets);

    // The team CSV is the People table with a Total row.
    await tester.tap(find.text('Export team CSV'));
    await tester.pumpAndSettle();
    final (name, csv) = saver.saved.single;
    expect(name, startsWith('standwise-team-summary-'));
    final rows = csv.substring(1).split('\r\n');
    expect(
      rows.first,
      'Person,Email,Project,Work,Standby,Total,Hours,Entries,'
      'Work rate,Standby rate,Amount',
    );
    expect(
      rows,
      contains(
        'Bob Nowak,bob@example.com,Hospital,2:00,0:00,2:00,2.00,1,'
        '60.00,25.00,120.00',
      ),
    );
    expect(
      rows,
      contains('Cleo Zielinska,cleo@example.com,,0:00,0:00,0:00,0.00,0,,,0.00'),
    );
    expect(rows, contains('Total,,,2:00,0:00,2:00,2.00,1,,,120.00'));

    await tester.tap(find.text('Bob Nowak').last);
    await tester.pumpAndSettle();
    expect(find.text('Entries of Bob Nowak'), findsOneWidget);
    expect(find.text('Night shift handover'), findsOneWidget);

    // The owner fixes Bob's entry with a comment; Bob will see both (D-050).
    await tester.ensureVisible(find.byTooltip('Edit entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit entry'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Bob Nowak’s entry'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Handover fixed',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Comment (optional)'),
      '  Wrong description  ',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final edited = entries.entries.single;
    expect(edited.uid, 'u2');
    expect(edited.description, 'Handover fixed');
    expect(edited.rateMinor, 6000);
    expect(edited.edit?.byUid, 'u1');
    expect(edited.edit?.byName, 'Anna Kowalska');
    expect(edited.edit?.comment, 'Wrong description');
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
