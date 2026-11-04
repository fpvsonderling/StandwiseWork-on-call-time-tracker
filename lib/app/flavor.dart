import 'package:firebase_core/firebase_core.dart';

import 'firebase/firebase_options_dev.dart' as dev;
import 'firebase/firebase_options_prod.dart' as prod;

enum Flavor { dev, prod }

/// Build-time configuration for one flavor.
///
/// OAuth client IDs are identifiers, not secrets, but they differ per Firebase
/// project, so they are passed with `--dart-define` (see docs/SETUP.md):
///
/// - `GOOGLE_SERVER_CLIENT_ID`: Firebase "Web client" ID (Android `serverClientId`)
/// - `GOOGLE_APPLE_CLIENT_ID`: iOS/macOS OAuth client ID
/// - `GOOGLE_DESKTOP_CLIENT_ID` / `GOOGLE_DESKTOP_CLIENT_SECRET`: Windows
///   "Desktop app" OAuth client (Google treats a desktop client secret as
///   non-confidential; it is still kept out of the repo).
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.googleServerClientId,
    required this.googleAppleClientId,
    required this.googleDesktopClientId,
    required this.googleDesktopClientSecret,
  });

  factory AppConfig.fromEnvironment(Flavor flavor) => AppConfig(
    flavor: flavor,
    googleServerClientId: const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    ),
    googleAppleClientId: const String.fromEnvironment('GOOGLE_APPLE_CLIENT_ID'),
    googleDesktopClientId: const String.fromEnvironment(
      'GOOGLE_DESKTOP_CLIENT_ID',
    ),
    googleDesktopClientSecret: const String.fromEnvironment(
      'GOOGLE_DESKTOP_CLIENT_SECRET',
    ),
  );

  final Flavor flavor;
  final String googleServerClientId;
  final String googleAppleClientId;
  final String googleDesktopClientId;
  final String googleDesktopClientSecret;

  bool get isDev => flavor == Flavor.dev;

  /// Firebase options for this flavor and platform, or `null` when
  /// `flutterfire configure` has not been run for it yet.
  FirebaseOptions? get firebaseOptions {
    try {
      return switch (flavor) {
        Flavor.dev => dev.DefaultFirebaseOptions.currentPlatform,
        Flavor.prod => prod.DefaultFirebaseOptions.currentPlatform,
      };
    } on UnsupportedError {
      return null;
    }
  }
}
