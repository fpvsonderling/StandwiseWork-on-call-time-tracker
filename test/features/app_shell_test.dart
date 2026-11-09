import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/app/app.dart';
import 'package:standwise/app/flavor.dart';
import 'package:standwise/data/providers.dart';

Widget _app({Flavor flavor = Flavor.dev}) => ProviderScope(
  overrides: [
    appConfigProvider.overrideWithValue(AppConfig.fromEnvironment(flavor)),
  ],
  child: const StandwiseApp(),
);

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('phone width (360 px) uses a bottom navigation bar', (
    tester,
  ) async {
    await _setSize(tester, const Size(360, 740));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Track work and standby time'), findsOneWidget);
    expect(find.textContaining('Firebase is not configured'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide screens (>= 900 px) use a navigation rail', (tester) async {
    await _setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('navigates between tabs', (tester) async {
    await _setSize(tester, const Size(400, 800));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('My reports'));
    await tester.pumpAndSettle();
    expect(find.text('Your hours and earnings'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Platform check'), findsOneWidget);
  });

  testWidgets('prod flavor hides the developer platform check', (tester) async {
    await _setSize(tester, const Size(400, 800));
    await tester.pumpWidget(_app(flavor: Flavor.prod));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Platform check'), findsNothing);
  });

  testWidgets('About opens the bundled privacy policy and terms', (
    tester,
  ) async {
    await _setSize(tester, const Size(400, 800));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Source code'), findsNothing);

    await tester.scrollUntilVisible(find.text('Privacy policy'), 200);
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(find.text('Who is responsible'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Terms'));
    await tester.pumpAndSettle();
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('Acceptable use'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mode renders', (tester) async {
    await _setSize(tester, const Size(360, 740));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NavigationBar));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform check without Firebase reports not configured', (
    tester,
  ) async {
    await _setSize(tester, const Size(400, 900));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Platform check'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run all checks'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed'), findsOneWidget);
    expect(find.textContaining('firebaseNotConfigured'), findsOneWidget);
  });
}
