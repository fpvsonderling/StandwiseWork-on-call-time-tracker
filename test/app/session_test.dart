import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/app/router.dart';
import 'package:standwise/app/session.dart';
import 'package:standwise/data/providers.dart';
import 'package:standwise/domain/models.dart';

import '../support/fakes.dart';

const _complete = UserProfile(
  uid: 'u1',
  firstName: 'Anna',
  lastName: 'Kowalska',
  email: 'anna@example.com',
);

void main() {
  group('sessionRedirect', () {
    final ready = SessionReady(
      testUser,
      _complete,
      memberships: [membershipOf('o1')],
      membership: membershipOf('o1'),
    );
    const needs = SessionNeedsProfile(testUser, null);
    const needsOrg = SessionNeedsOrganization(testUser, _complete);

    test('signed-out users always land on the welcome screen', () {
      expect(
        sessionRedirect(const SessionSignedOut(), Routes.timer),
        Routes.welcome,
      );
      expect(
        sessionRedirect(const SessionSignedOut(), Routes.platformCheck),
        Routes.welcome,
      );
      expect(sessionRedirect(const SessionSignedOut(), Routes.welcome), isNull);
    });

    test('an incomplete profile forces the "Your name" screen', () {
      expect(sessionRedirect(needs, Routes.timer), Routes.profileSetup);
      expect(sessionRedirect(needs, Routes.settings), Routes.profileSetup);
      expect(sessionRedirect(needs, Routes.profileSetup), isNull);
    });

    test('without an organization the choice screen comes next', () {
      expect(sessionRedirect(needsOrg, Routes.timer), Routes.organization);
      expect(sessionRedirect(needsOrg, Routes.organization), isNull);
    });

    test('ready users leave the onboarding screens and stay elsewhere', () {
      for (final gate in Routes.gates) {
        expect(sessionRedirect(ready, gate), Routes.timer);
      }
      expect(sessionRedirect(ready, Routes.reports), isNull);
      expect(sessionRedirect(ready, Routes.profile), isNull);
      expect(sessionRedirect(ready, Routes.addOrganization), isNull);
    });

    test('loading shows the loading screen', () {
      expect(
        sessionRedirect(const SessionLoading(), Routes.timer),
        Routes.loading,
      );
      expect(sessionRedirect(const SessionLoading(), Routes.loading), isNull);
    });

    test('without Firebase the app opens as in stage 1', () {
      expect(
        sessionRedirect(const SessionUnconfigured(), Routes.timer),
        isNull,
      );
      expect(
        sessionRedirect(const SessionUnconfigured(), Routes.welcome),
        Routes.timer,
      );
    });
  });

  group('sessionProvider', () {
    Future<SessionStatus> settle(ProviderContainer c) async {
      c.listen(sessionProvider, (_, _) {});
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return c.read(sessionProvider);
    }

    ProviderContainer container({
      bool ready = true,
      AuthUser? user,
      Map<String, UserProfile>? profiles,
      List<Membership>? memberships,
    }) {
      final c = ProviderContainer(
        overrides: [
          firebaseReadyProvider.overrideWithValue(ready),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(signedIn: user),
          ),
          profileRepositoryProvider.overrideWithValue(
            FakeProfileRepository(profiles),
          ),
          orgRepositoryProvider.overrideWithValue(
            FakeOrgRepository(memberships: memberships),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('is unconfigured without Firebase', () async {
      expect(
        await settle(container(ready: false, user: testUser)),
        isA<SessionUnconfigured>(),
      );
    });

    test('is signed out without a user', () async {
      expect(await settle(container()), isA<SessionSignedOut>());
    });

    test(
      'needs a profile when the document is missing or incomplete',
      () async {
        expect(
          await settle(container(user: testUser)),
          isA<SessionNeedsProfile>(),
        );
        final incomplete = UserProfile(
          uid: 'u1',
          firstName: 'Anna',
          lastName: '',
          email: testUser.email,
        );
        final s = await settle(
          container(user: testUser, profiles: {'u1': incomplete}),
        );
        expect(s, isA<SessionNeedsProfile>());
        expect((s as SessionNeedsProfile).profile, same(incomplete));
      },
    );

    test('needs an organization with a profile but no membership', () async {
      expect(
        await settle(container(user: testUser, profiles: {'u1': _complete})),
        isA<SessionNeedsOrganization>(),
      );
    });

    test('is ready with a profile and a membership', () async {
      final s = await settle(
        container(
          user: testUser,
          profiles: {'u1': _complete},
          memberships: [membershipOf('o1')],
        ),
      );
      expect(s, isA<SessionReady>());
      expect((s as SessionReady).profile.displayName, 'Anna Kowalska');
      expect(s.orgId, 'o1');
    });
  });

  group('activeMembership', () {
    final a = membershipOf('a');
    final b = membershipOf('b');
    final disabled = membershipOf('d', status: MemberStatus.disabled);

    test('prefers the last used organization', () {
      expect(activeMembership([a, b], 'b'), same(b));
    });

    test('falls back to the first active one', () {
      expect(activeMembership([disabled, a, b], 'gone'), same(a));
      expect(activeMembership([disabled], null), same(disabled));
      expect(activeMembership([], 'a'), isNull);
    });
  });
}
