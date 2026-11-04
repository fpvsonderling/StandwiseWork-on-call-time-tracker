# Decisions

Where the spec ([`SPEC.md`](SPEC.md)) leaves something open, the simplest sensible option is chosen and recorded here. Newest stage last.

## Stage 1 — skeleton

| # | Decision | Why |
|---|---|---|
| D-001 | Flutter **3.47.9 stable** (Dart 3.13), pinned in CI. Lints: `flutter_lints` plus a few strict rules in `analysis_options.yaml`. | Current stable at the time of writing; `flutter_lints` is lighter than `very_good_analysis` and enough for a small team. |
| D-002 | **Flavors:** Dart entry points `lib/main_dev.dart` / `lib/main_prod.dart` on every platform. Android also has Gradle `productFlavors` (`dev` gets the `.dev` ID suffix and the label "Standwise Dev"), so it must be run with `--flavor dev`. iOS/macOS Xcode schemes and separate Windows binaries are added in stage 8 together with the prod Firebase project. | Xcode schemes need a Mac to create and test; until a prod project exists, a second scheme adds nothing. `lib/main.dart` points at dev so plain `flutter run` works. |
| D-003 | **Bundle / application ID:** `com.sonderling.standwise` (placeholder, the spec says to set it during setup). | Change it in `android/app/build.gradle.kts`, `ios/Runner.xcodeproj`, `macos/Runner/Configs/AppInfo.xcconfig` and the macOS entitlements before the first store upload. |
| D-004 | **Firebase options:** `lib/app/firebase/firebase_options_{dev,prod}.dart` are committed placeholders that `flutterfire configure` overwrites. When they are placeholders, or `Firebase.initializeApp` fails, the app starts in a "Firebase is not configured" mode (banner, unconfigured repositories). | CI can build and test every platform without Firebase credentials, and a broken config never crashes on launch. Firebase config values are identifiers, not secrets (spec §10), so the generated dev file is committed. Prod handling is decided in stage 8. |
| D-005 | **OAuth client IDs** come from `--dart-define-from-file=config/dev.json` (git-ignored; template `config/dev.example.json`). | IDs differ per Firebase project and platform; keeping them out of code means no rebuild of code for a new project. The Windows desktop client secret is not confidential by Google's definition but is still kept out of the repo. |
| D-006 | **Windows sign-in** implemented now (stage 1, not 2) in `lib/core/auth/desktop_google_oauth.dart`: system browser + PKCE (S256) + loopback `HttpServer` on `127.0.0.1:<random port>`, then Firebase `signInWithCredential`. Unit-tested with a simulated browser redirect. | The spike needs a real sign-in on Windows to prove Firestore with security rules. |
| D-007 | **Offline cache** explicitly enabled with unlimited cache size on all platforms (`Settings(persistenceEnabled: true)`). | Default on mobile/macOS; setting it explicitly makes Windows behave the same, and the platform check verifies it. |
| D-008 | **Money rounding:** `amount = (rateMinor × minutes + 30) ~/ 60` — integer maths, rounded half up once per entry. Report totals are sums of per-entry amounts. | Matches what a person would compute per line on an invoice; no `double` anywhere. |
| D-009 | **Manual entry with `to == from`** is a 24-hour entry ending the next day (spec: "if to ≤ from, the end is on the next day"; 24 h is still within the limit). | Literal reading of the spec. |
| D-010 | **Generated localization files** (`lib/l10n/app_localizations*.dart`) are git-ignored; `flutter pub get` regenerates them (`generate: true`). | Keeps diffs clean; ARB files are the source. |
| D-011 | **Platform check** (the stage 1 spike) is a dev-flavor-only screen: Settings → Developer → Platform check. It writes `/_platformChecks/{uid}` (rules allow only the caller's own document) and checks sign-in, write, server read, live listener, offline write, cache read and resync. It goes through the repository interfaces like any feature. | Repeatable on every device, and the "Copy report" button produces the text for the results table below. |
| D-012 | All five tabs are visible in stage 1, including **Team**. Role-based hiding arrives with memberships in stage 3. | No roles exist yet. |
| D-013 | Deployment targets: iOS 15.0, macOS 12.0 (Flutter 3.47 defaults); Android `minSdk` from Flutter (≥ 24). | Satisfy current Firebase SDK minimums. |
| D-014 | **License:** proprietary, all rights reserved (`LICENSE`). | The product is a commercial SaaS; open-sourcing can be decided later. |
| D-015 | macOS entitlements: App Sandbox with `network.client` and `keychain-access-groups` (`$(AppIdentifierPrefix)com.sonderling.standwise`). | Required for Google sign-in and Firebase Auth's keychain storage; the group needs a signing team when run locally (docs/SETUP.md). |

### Stage 1 spike results (spec §2.1)

Fill in by running **Settings → Developer → Platform check** on each device with the dev flavor and pasting the copied report.

| Platform | Sign-in | Write | Read | Listener | Offline write | Cache read | Resync | Outcome |
|---|---|---|---|---|---|---|---|---|
| Windows | pending | pending | pending | pending | pending | pending | pending | — |
| macOS | pending | pending | pending | pending | pending | pending | pending | — |
| Android | pending | pending | pending | pending | pending | pending | pending | — |
| iOS | pending | pending | pending | pending | pending | pending | pending | — |

If any Windows step fails, implement `lib/data/windows/` (Firestore REST with the user's ID token plus a small local cache) behind the same repository interfaces, as spec §2.1.3 describes, and record it here.
