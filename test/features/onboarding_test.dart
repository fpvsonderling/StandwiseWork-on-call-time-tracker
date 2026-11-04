import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/app/app.dart';
import 'package:standwise/app/flavor.dart';
import 'package:standwise/core/errors.dart';
import 'package:standwise/data/providers.dart';
import 'package:standwise/domain/models.dart';

import '../support/fakes.dart';

Widget _app(FakeAuthRepository auth, FakeProfileRepository profiles) =>
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig.fromEnvironment(Flavor.dev),
        ),
        firebaseReadyProvider.overrideWithValue(true),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
      child: const StandwiseApp(),
    );

void main() {
  testWidgets('sign in, confirm the prefilled name, then enter the app', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    final profiles = FakeProfileRepository();
    await tester.pumpWidget(_app(auth, profiles));
    await tester.pumpAndSettle();

    expect(find.text('Sign in with Google'), findsOneWidget);
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    // Prefilled from "Anna Maria Kowalska", split on the last space.
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Anna Maria'), findsOneWidget);
    expect(find.text('Kowalska'), findsOneWidget);
    expect(find.text('anna@example.com'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(profiles.saved.single.first, 'Anna Maria');
    expect(profiles.saved.single.exists, isFalse);
    expect(find.text('Track work and standby time'), findsOneWidget);
  });

  testWidgets('validates first and last name', (tester) async {
    final auth = FakeAuthRepository(
      signedIn: const AuthUser(
        uid: 'u2',
        email: 'x@example.com',
        emailVerified: true,
      ),
    );
    final profiles = FakeProfileRepository();
    await tester.pumpWidget(_app(auth, profiles));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'R2D2');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text('Use letters, spaces, hyphens and apostrophes only'),
      findsOneWidget,
    );
    expect(find.text('Required'), findsOneWidget);
    expect(profiles.saved, isEmpty);

    await tester.enterText(fields.at(0), 'Łukasz');
    await tester.enterText(fields.at(1), "O'Neil");
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(profiles.saved.single.last, "O'Neil");
  });

  testWidgets('a cancelled sign-in shows no error, a failed one does', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(_app(auth, FakeProfileRepository()));
    await tester.pumpAndSettle();

    auth.nextSignInError = const AppException(AppErrorCode.signInCancelled);
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in was cancelled.'), findsNothing);

    auth.nextSignInError = const AppException(AppErrorCode.network);
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(
      find.text('No connection. Check your internet and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('a complete profile opens the app; Settings edits the name '
      'and signs out', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = FakeAuthRepository(signedIn: testUser);
    final profiles = FakeProfileRepository({
      'u1': const UserProfile(
        uid: 'u1',
        firstName: 'Anna',
        lastName: 'Kowalska',
        email: 'anna@example.com',
      ),
    });
    await tester.pumpWidget(_app(auth, profiles));
    await tester.pumpAndSettle();
    expect(find.text('Track work and standby time'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Anna Kowalska'), findsOneWidget);

    await tester.tap(find.text('Anna Kowalska'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'Nowak');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(profiles.saved.single.exists, isTrue);
    expect(find.text('Anna Nowak'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
