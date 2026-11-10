import 'package:flutter_test/flutter_test.dart';
import 'package:standwise/core/update_check.dart';

import '../support/harness.dart';

void main() {
  testWidgets('a newer release shows a banner until Later', (tester) async {
    await pumpApp(
      tester,
      update: AvailableUpdate(
        version: '0.1.1',
        url: Uri.parse('https://dl/app.apk'),
      ),
    );
    expect(find.text('Standwise 0.1.1 is available.'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Standwise 0.1.1 is available.'), findsNothing);
  });

  testWidgets('no banner when up to date', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('is available'), findsNothing);
  });
}
