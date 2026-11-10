import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:standwise/app/tracker_prefs.dart';
import 'package:standwise/app/updates.dart';
import 'package:standwise/core/update_check.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/app/app.dart';
import 'package:standwise/app/flavor.dart';
import 'package:standwise/data/providers.dart';
import 'package:standwise/domain/models.dart';

import 'fakes.dart';

const testProfile = UserProfile(
  uid: 'u1',
  firstName: 'Anna',
  lastName: 'Kowalska',
  email: 'anna@example.com',
  lastOrgId: 'o1',
);

const testOrg = Organization(
  id: 'o1',
  name: 'ACME',
  status: OrgStatus.active,
  settings: OrgSettings(currency: 'PLN'),
);

/// Starts the app signed in as Anna in ACME with [role].
Future<void> pumpApp(
  WidgetTester tester, {
  OrgRole role = OrgRole.owner,
  Organization org = testOrg,
  List<Membership> otherMembers = const [],
  List<Override> overrides = const [],
  Size size = const Size(500, 1000),
  void Function(FakeOrgRepository orgs)? onOrgs,
  TrackerPrefs? prefs,
  AvailableUpdate? update,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final profiles = FakeProfileRepository({'u1': testProfile});
  final orgs = FakeOrgRepository(
    profiles: profiles,
    memberships: [
      membershipOf(org.id, role: role),
      ...otherMembers,
    ],
    orgs: {org.id: org},
  );
  onOrgs?.call(orgs);
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
        trackerPrefsProvider.overrideWithValue(prefs ?? MemoryTrackerPrefs()),
        availableUpdateProvider.overrideWith((ref) async => update),
        ...overrides,
      ],
      child: const StandwiseApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps the navigation destination labelled [label].
Future<void> goTo(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}
