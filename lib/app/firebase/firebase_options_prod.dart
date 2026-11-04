// PLACEHOLDER — replaced by `flutterfire configure` (see docs/SETUP.md):
//
//   flutterfire configure --project=standwise-prod \
//     --out=lib/app/firebase/firebase_options_prod.dart \
//     --platforms=android,ios,macos,windows
//
// Until then the app starts in "Firebase not configured" mode.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured for the prod flavor yet. '
      'Run flutterfire configure (docs/SETUP.md).',
    );
  }
}
