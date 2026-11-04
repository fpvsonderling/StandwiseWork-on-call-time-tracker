import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firebase/firebase_overrides.dart';
import '../data/providers.dart';
import 'app.dart';
import 'flavor.dart';

/// Shared startup for `main_dev.dart` and `main_prod.dart`.
Future<void> bootstrap(Flavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment(flavor);
  final firebaseOverrides = await initFirebase(config);
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        ...firebaseOverrides,
      ],
      child: const StandwiseApp(),
    ),
  );
}
