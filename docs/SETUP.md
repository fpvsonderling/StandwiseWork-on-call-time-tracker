# Setup

Step by step from zero. Each stage of the build adds to this file; this version covers **stage 1** (dev Firebase project, Google sign-in on every platform, running the app and the platform check).

> You need a Google account, a credit card for the Firebase Blaze plan (Cloud Functions require it; small teams stay in the free tier in practice), and for Apple platforms a Mac with Xcode.

---

## 1. Install the tools

| Tool | Version | Notes |
|---|---|---|
| Flutter | 3.47.9 stable | <https://docs.flutter.dev/get-started/install>. Run `flutter doctor` until the platforms you want are green. |
| Node.js | 22 LTS | Needed for the Firebase CLI (and Cloud Functions from stage 2). |
| Firebase CLI | latest | `npm install -g firebase-tools`, then `firebase login`. |
| FlutterFire CLI | latest | `dart pub global activate flutterfire_cli` |
| Windows | Visual Studio 2022 with "Desktop development with C++" | For Windows builds. |
| macOS / iOS | Xcode (current) | For Apple builds; an Apple Developer account for signing. |

Clone the repository and fetch packages:

```sh
git clone https://github.com/fpvsonderling/StandwiseWork-on-call-time-tracker.git
cd StandwiseWork-on-call-time-tracker
flutter pub get
flutter test
```

The app already runs at this point, in "Firebase is not configured" mode.

---

## 2. Create the dev Firebase project

1. Open <https://console.firebase.google.com> → **Add project** → name it **`standwise-dev`**. Google Analytics: **off** (the app uses no analytics).
2. **Upgrade to Blaze** (bottom-left "Spark" → Upgrade).
3. **Budget alert right away:** Google Cloud console → **Billing → Budgets & alerts → Create budget**, scope: project `standwise-dev`, amount e.g. €10/month, alerts at 50 %, 90 %, 100 % by email. Do the same later for `standwise-prod`.
4. **Authentication** → Get started → Sign-in method → **Google** → Enable → choose a support email → Save.
   Open the Google provider again and expand **Web SDK configuration**: copy the **Web client ID** (it ends in `.apps.googleusercontent.com`). This is your `GOOGLE_SERVER_CLIENT_ID`.
5. **Firestore Database** → Create database → **Production mode** → location **`eur3 (Europe)`** (multi-region) or `europe-west3 (Frankfurt)`. The location cannot be changed later.

## 3. Connect the app to Firebase

From the repository folder:

```sh
flutterfire configure --project=standwise-dev \
  --out=lib/app/firebase/firebase_options_dev.dart \
  --platforms=android,ios,macos,windows \
  --android-package-name=com.sonderling.standwise.dev \
  --ios-bundle-id=com.sonderling.standwise \
  --macos-bundle-id=com.sonderling.standwise
```

This registers the apps in Firebase and overwrites the placeholder `firebase_options_dev.dart`. It may also write `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`; these are identifiers, not secrets, and can be committed (docs/DECISIONS.md D-004).

> If you change the bundle ID (D-003), use your ID here and in the native projects.

Deploy the stage 1 security rules and indexes:

```sh
firebase deploy --only firestore --project standwise-dev
```

## 4. Google sign-in per platform

Copy the config template and fill it in as you go:

```sh
cp config/dev.example.json config/dev.json
```

### Android
1. Get the debug signing fingerprints: `cd android && ./gradlew signingReport` (look for the `devDebug` variant: SHA1 and SHA-256).
2. Firebase console → Project settings → your Android app (`com.sonderling.standwise.dev`) → **Add fingerprint** → paste both.
3. Put the Web client ID from step 2.4 into `GOOGLE_SERVER_CLIENT_ID`.

### iOS and macOS
1. Firebase console → Project settings → your Apple app → download `GoogleService-Info.plist` and open it. Copy `CLIENT_ID` into `GOOGLE_APPLE_CLIENT_ID`.
2. In Xcode open `ios/Runner.xcworkspace` → Runner target → **Info → URL Types → +** and paste the plist's `REVERSED_CLIENT_ID` as the URL scheme. Repeat for `macos/Runner.xcworkspace`.
3. macOS only: Runner target → **Signing & Capabilities** → choose your team. The Keychain Sharing group (`com.sonderling.standwise`) is already in the entitlements; it needs a team to run.

### Windows
1. Google Cloud console (project `standwise-dev`) → **APIs & Services → Credentials → Create credentials → OAuth client ID** → Application type **Desktop app** → name "Standwise Windows".
2. Copy the client ID and client secret into `GOOGLE_DESKTOP_CLIENT_ID` and `GOOGLE_DESKTOP_CLIENT_SECRET`.
3. Same screen → **OAuth consent screen**: app name Standwise, support email, scopes `openid`, `email`, `profile` (no verification needed for these), add yourself as a test user while in "Testing".

How it works: the app opens your browser on Google's sign-in page and listens on `http://127.0.0.1:<random port>` for the redirect; PKCE protects the code exchange. No redirect URI needs to be registered for desktop clients.

## 5. Run the app

Always pass the config file:

```sh
# Android (flavor required)
flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=config/dev.json

# iOS, macOS, Windows
flutter run -t lib/main_dev.dart --dart-define-from-file=config/dev.json -d macos
flutter run -t lib/main_dev.dart --dart-define-from-file=config/dev.json -d windows
flutter run -t lib/main_dev.dart --dart-define-from-file=config/dev.json -d <iphone>
```

## 6. Run the platform check (stage 1 spike)

On each device: **Settings → Developer → Platform check → Run all checks**. It signs in with Google and tests Firestore write, read, live listener, offline write, offline cache read and resync. Tap **Copy report** and paste the result into the table in `docs/DECISIONS.md`.

To check cross-device sync, run it on two devices with the same Google account: the "Live value" on the first updates when the second runs.

Priorities: **Windows and macOS** (spec §2.1). If a Windows step fails, the fallback in spec §2.1.3 is implemented before stage 2 continues.

---

Later stages add: Cloud Functions and the emulator suite (stage 2), the invite email extension (stage 3), App Check, Crashlytics, the prod project, deploy and release workflows, signing and store publishing (stage 8).
