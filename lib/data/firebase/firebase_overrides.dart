import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../app/flavor.dart';
import '../../core/auth/google_tokens.dart';
import '../providers.dart';
import 'callable_client.dart';
import 'firebase_auth_repository.dart';
import 'firebase_org_repository.dart';
import 'firebase_platform_check_repository.dart';
import 'firebase_profile_repository.dart';

/// Initializes Firebase for [config] and returns provider overrides wiring the
/// FlutterFire repositories. Returns an empty list when Firebase is not
/// configured or fails to start, so the app falls back to "not configured".
///
/// This is the only place (with `data/firebase/`) that touches Firebase SDKs.
Future<List<Override>> initFirebase(AppConfig config) async {
  final options = config.firebaseOptions;
  if (options == null) return const [];
  try {
    await Firebase.initializeApp(options: options);
  } catch (e, st) {
    debugPrint('Firebase.initializeApp failed: $e\n$st');
    return const [];
  }
  final db = FirebaseFirestore.instance;
  // Cloud Functions region (functions/src/lib/config.ts).
  const region = 'europe-west1';
  var functionsUrl = 'https://$region-${options.projectId}.cloudfunctions.net';
  if (config.useEmulators) {
    // Local emulator suite (docs/SETUP.md §7). The Android emulator reaches
    // the host computer at 10.0.2.2.
    final host = defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    db.useFirestoreEmulator(host, 8080);
    functionsUrl = 'http://$host:5001/${options.projectId}/$region';
  }
  // Offline cache: default on mobile/macOS; set explicitly so Windows uses it
  // too (verified by the platform check).
  db.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  final google = GoogleTokenProvider.forPlatform(config);
  final auth = FirebaseAuthRepository(FirebaseAuth.instance, google);
  final functions = CallableClient(
    baseUrl: functionsUrl,
    idToken: auth.idToken,
  );
  return [
    firebaseReadyProvider.overrideWithValue(true),
    authRepositoryProvider.overrideWithValue(auth),
    platformCheckRepositoryProvider.overrideWithValue(
      FirebasePlatformCheckRepository(db),
    ),
    profileRepositoryProvider.overrideWithValue(FirebaseProfileRepository(db)),
    orgRepositoryProvider.overrideWithValue(
      FirebaseOrgRepository(db, functions),
    ),
  ];
}
