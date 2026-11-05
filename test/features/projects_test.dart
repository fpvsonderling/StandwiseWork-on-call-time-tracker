import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/data/providers.dart';
import 'package:standwise/domain/models.dart';
import 'package:standwise/domain/projects.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  testWidgets('admins add a project and everyone sets own rates', (
    tester,
  ) async {
    final repo = FakeProjectsRepository();
    await pumpApp(
      tester,
      overrides: [projectsRepositoryProvider.overrideWithValue(repo)],
    );
    await goTo(tester, 'Projects & rates');

    await tester.tap(find.text('Add project'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Project name'),
      'Hospital night shifts',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Client (optional)'),
      'St. Mary',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.projects.single.name, 'Hospital night shifts');
    expect(find.text('Hospital night shifts'), findsOneWidget);

    final work = find.widgetWithText(TextField, 'Work').first;
    await tester.enterText(work, '45,5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.rates[repo.projects.single.id]?.workRateMinor, 4550);

    await tester.enterText(work, 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount like 45 or 45,50'), findsOneWidget);
    expect(repo.rates[repo.projects.single.id]?.workRateMinor, 4550);
  });

  testWidgets('archive hides a project; delete asks first', (tester) async {
    final repo = FakeProjectsRepository(
      projects: [const Project(id: 'a', name: 'Alpha')],
    );
    await pumpApp(
      tester,
      overrides: [projectsRepositoryProvider.overrideWithValue(repo)],
    );
    await goTo(tester, 'Projects & rates');

    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(repo.projects.single.archived, isTrue);
    expect(find.text('Archived (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Alpha”?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.projects.single.deleted, isTrue);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('employees only see active projects and no admin actions', (
    tester,
  ) async {
    final repo = FakeProjectsRepository(
      projects: [
        const Project(id: 'a', name: 'Alpha'),
        const Project(id: 'b', name: 'Bravo', archived: true),
      ],
    );
    await pumpApp(
      tester,
      role: OrgRole.employee,
      overrides: [projectsRepositoryProvider.overrideWithValue(repo)],
    );
    await goTo(tester, 'Projects & rates');

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsNothing);
    expect(find.text('Add project'), findsNothing);
    expect(find.byTooltip('Project actions'), findsNothing);
  });
}
