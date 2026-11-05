# Standwise

Work & on-call (standby) time tracker for teams — Flutter app with a Firebase backend.

Employees track **Work** and **Standby** hours with a timer or manual entries, each with their own hourly rates per project. Admins get team reports for their organization. Many companies share one backend, each fully isolated. Native apps for **Android, iOS, Windows and macOS**; works offline.

> **Status:** stage 7 of 9 (timer, entries, projects and rates, reports and CSV, team view, member management, organization settings, account deletion). See the [build order](docs/SPEC.md#12-build-order).

## Docs

- [Specification](docs/SPEC.md) — what is being built
- [Decisions](docs/DECISIONS.md) — choices made where the spec was open, and spike results
- [Setup](docs/SETUP.md) — Firebase, Google sign-in and running on each platform
- [Contributing](CONTRIBUTING.md)

## Quick start

```sh
flutter pub get
flutter test
flutter run -t lib/main_dev.dart                    # macOS / Windows / iOS
flutter run --flavor dev -t lib/main_dev.dart       # Android

# Backend (needs Node 22, Java 21, `npm i -g firebase-tools`)
(cd functions && npm ci && npm test && npm run test:emulator)
(cd rules-tests && npm ci && npm test)
```

Without Firebase configured the app runs in a "not configured" mode. Follow [SETUP.md](docs/SETUP.md) to connect it.

## Layout

```
lib/
  app/          bootstrap, flavors, router, theme, l10n helpers, brand name
  core/         auth (google_sign_in, Windows desktop OAuth), errors
  data/         repository interfaces, FlutterFire implementations
  domain/       pure Dart: money, durations, ranges, names, models
  features/     screens
  l10n/         app_en.arb
functions/      Cloud Functions (TypeScript)
rules-tests/    Firestore security rules tests (emulator)
```

## License

MIT — see [LICENSE](LICENSE).
