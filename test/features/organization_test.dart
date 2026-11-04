import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/app/app.dart';
import 'package:standwise/app/flavor.dart';
import 'package:standwise/core/errors.dart';
import 'package:standwise/data/providers.dart';
import 'package:standwise/domain/models.dart';

import '../support/fakes.dart';

const _profile = UserProfile(
  uid: 'u1',
  firstName: 'Anna',
  lastName: 'Kowalska',
  email: 'anna@example.com',
);

Future<void> _pump(
  WidgetTester tester, {
  required FakeProfileRepository profiles,
  required FakeOrgRepository orgs,
}) async {
  tester.view.physicalSize = const Size(500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig.fromEnvironment(Flavor.dev),
        ),
        firebaseReadyProvider.overrideWithValue(true),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: testUser),
        ),
        profileRepositoryProvider.overrideWithValue(profiles),
        orgRepositoryProvider.overrideWithValue(orgs),
      ],
      child: const StandwiseApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a user without an organization creates one and becomes owner', (
    tester,
  ) async {
    final profiles = FakeProfileRepository({'u1': _profile});
    final orgs = FakeOrgRepository(profiles: profiles);
    await _pump(tester, profiles: profiles, orgs: orgs);

    expect(find.text('Join with an invite code'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Company name'),
      'ACME Sp. z o.o.',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(
      orgs.calls,
      contains('createOrganization:ACME Sp. z o.o.:EUR:Europe/Warsaw'),
    );
    expect(find.text('Track work and standby time'), findsOneWidget);
    expect(find.text('ACME Sp. z o.o.'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
  });

  testWidgets('joining with a wrong code shows why; a right one enters', (
    tester,
  ) async {
    final profiles = FakeProfileRepository({'u1': _profile});
    final orgs = FakeOrgRepository(
      profiles: profiles,
      orgs: {
        'o9': const Organization(
          id: 'o9',
          name: 'Night Shift Ltd',
          status: OrgStatus.active,
        ),
      },
    )..validCodes['K7M2-9QXP'] = 'o9';
    await _pump(tester, profiles: profiles, orgs: orgs);

    final code = find.widgetWithText(TextField, 'Invite code');
    await tester.enterText(code, 'NOPE-NOPE');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.textContaining("invite code isn't valid"), findsOneWidget);

    await tester.enterText(code, 'K7M2-9QXP');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.text('Night Shift Ltd'), findsOneWidget);
    expect(find.text('Employee'), findsOneWidget);
  });

  testWidgets('the header switches between organizations', (tester) async {
    final profiles = FakeProfileRepository({'u1': _profile});
    final orgs = FakeOrgRepository(
      profiles: profiles,
      memberships: [
        membershipOf('a'),
        membershipOf('b', role: OrgRole.employee),
      ],
      orgs: {
        'a': const Organization(
          id: 'a',
          name: 'Alpha',
          status: OrgStatus.trial,
        ),
        'b': const Organization(
          id: 'b',
          name: 'Bravo',
          status: OrgStatus.suspended,
        ),
      },
    );
    await _pump(tester, profiles: profiles, orgs: orgs);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.textContaining('read-only'), findsNothing);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bravo').last);
    await tester.pumpAndSettle();

    expect(find.text('Bravo'), findsOneWidget);
    expect(find.text('Employee'), findsOneWidget);
    expect(find.textContaining('read-only'), findsOneWidget);
  });

  testWidgets('admins invite people and see the code', (tester) async {
    final profiles = FakeProfileRepository({'u1': _profile});
    final orgs = FakeOrgRepository(
      profiles: profiles,
      memberships: [
        membershipOf('a'),
        membershipOf(
          'a',
          uid: 'u2',
          role: OrgRole.employee,
          firstName: 'Piotr',
          lastName: 'Nowak',
          email: 'piotr@example.com',
        ),
      ],
      orgs: {
        'a': const Organization(
          id: 'a',
          name: 'Alpha',
          status: OrgStatus.trial,
        ),
      },
    );
    await _pump(tester, profiles: profiles, orgs: orgs);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Members and invites'));
    await tester.pumpAndSettle();
    expect(find.text('Piotr Nowak'), findsOneWidget);
    expect(find.text('Anna Kowalska (You)'), findsOneWidget);

    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
    await tester.tap(find.text('Create invite'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Ola@Example.com');
    await tester.tap(find.text('Create invite'));
    await tester.pumpAndSettle();
    expect(orgs.calls, contains('createInvite:ola@example.com:employee'));
    expect(find.text('K7M2-9QXP'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('ola@example.com'), findsOneWidget);

    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();
    expect(orgs.calls.last, startsWith('revokeInvite:'));
    expect(find.text('ola@example.com'), findsNothing);
  });

  testWidgets('employees see no members screen entry', (tester) async {
    final profiles = FakeProfileRepository({'u1': _profile});
    final orgs = FakeOrgRepository(
      profiles: profiles,
      memberships: [membershipOf('a', role: OrgRole.employee)],
      orgs: {
        'a': const Organization(
          id: 'a',
          name: 'Alpha',
          status: OrgStatus.trial,
        ),
      },
    );
    await _pump(tester, profiles: profiles, orgs: orgs);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Members and invites'), findsNothing);
    expect(find.text('Create or join an organization'), findsOneWidget);
  });

  test('server errors keep their reason', () {
    expect(
      const AppException(AppErrorCode.inviteExpired).code,
      AppErrorCode.inviteExpired,
    );
  });
}
