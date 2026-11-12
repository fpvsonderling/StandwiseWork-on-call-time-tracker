# Prompt: Standwise — work & on-call time tracker (Flutter + Firebase, multi-company SaaS)

> This is the original product specification, kept in the repo as the source of truth for every build stage.
> Decisions that fill gaps in it are recorded in [`DECISIONS.md`](DECISIONS.md).

You are an experienced Flutter and Firebase developer. Build **Standwise** from scratch in the GitHub repository **https://github.com/fpvsonderling/StandwiseWork-on-call-time-tracker**, following this specification. Work in stages (see "Build order"). After every stage the app must build, run and pass CI. When the spec leaves something open, choose the simplest sensible option and record the decision in `docs/DECISIONS.md`.

Everything is in **English**: app UI, code, comments, commit messages, README, docs, issue templates and store listings. Keep all user-facing strings in ARB files (`lib/l10n/app_en.arb`) so other languages (Polish first) can be added later without code changes.

> Working name: **Standwise**. A search of Google Play and the App Store (Nov 2026) found no app with this name. Before publishing, check again in both stores, in trademark registers (EUIPO, USPTO) and for a domain (e.g. `standwise.app`). Keep the name in one config place so it is easy to change.

---

## 1. Goal

A time tracking app sold to **many companies** (SaaS). Each company is an isolated **organization** with its own employees, projects, rates and reports. Target: small teams (up to ~50 people per organization) whose staff work both regular hours and standby (on-call) duty.

- Everyone signs in with **Google**. After the first sign-in every user (employee and admin) must enter their **first name and last name**; these names are used everywhere in the app and in reports.
- Employees track time with a timer or add entries manually.
- Every entry has a rate type: **Work** (`work`) or **Standby** (`standby`, on-call/readiness).
- Every employee enters their own hourly rates for Work and Standby, per project.
- Employees see, edit and delete **only their own** hours.
- Admins see reports for **all** employees of **their** organization.
- One organization can never see another organization's data.
- Platforms: **Android, iOS, Windows, macOS** (native apps only). No Web version and no Firebase Hosting for now; keep the code free of platform assumptions so Web can be added later.

Regional settings are per organization: currency (default `EUR`), timezone (default `Europe/Warsaw`), first day of week (default Monday), 24-hour time (default on), CSV format. Number, date and currency formatting follow the device locale via `intl`.

---

## 2. Tech stack

- **Flutter** (current stable), **Dart 3**, null safety, `flutter analyze` clean (`very_good_analysis` or `flutter_lints`).
- **State:** Riverpod. **Routing:** go_router (with auth/onboarding redirects).
- **Firebase** (official FlutterFire packages):
  - **Firebase Authentication** with the Google provider only.
  - **Cloud Firestore** in an EU location (e.g. `eur3` or `europe-west3`), with offline persistence (default on Android/iOS/macOS; verify on Windows).
  - **Cloud Functions for Firebase** (2nd gen, TypeScript, Node LTS, region `europe-west3` or `europe-west1`) for trusted operations. Requires the Blaze plan.
  - **Firebase App Check** (Play Integrity on Android, App Attest/DeviceCheck on iOS and macOS; debug provider in dev; document the Windows situation).
  - **Crashlytics** on Android, iOS and macOS. No advertising or analytics SDKs that track users.
- **Google Sign-In:**
  - Android, iOS, macOS: `google_sign_in`, then `FirebaseAuth.signInWithCredential(GoogleAuthProvider.credential(...))`. On Android pass the Firebase Web client ID as `serverClientId`. On macOS enable the App Sandbox entitlements for outgoing network connections and keychain access.
  - Windows: OAuth 2.0 for desktop apps with PKCE and a loopback redirect (`http://127.0.0.1:<port>`): open the browser with `url_launcher`, receive the code on a local `HttpServer`, exchange it for tokens, then `signInWithCredential(GoogleAuthProvider.credential(idToken: ..., accessToken: ...))`. Separate OAuth client of type "Desktop app".
- **Charts:** fl_chart. **Localization:** `flutter_localizations` + `intl` with ARB files.
- **CSV:** `csv` package. Saving: `file_selector` (Windows, macOS), `share_plus` (Android/iOS).
- **Deep links:** custom URL scheme `standwise://` for invite links (no web domain needed).
- **Tests:** `flutter_test` (unit and widget), `integration_test`, Firestore rules tests with the **Firebase Emulator Suite** (`@firebase/rules-unit-testing`), Functions unit tests (Jest/Vitest).
- **CI/CD:** GitHub Actions.

### 2.1 Windows strategy (must be done in stage 1)
FlutterFire support on Windows is less mature than on mobile and macOS. Therefore:
1. **Data access only through repository interfaces** (`lib/data/repositories/*.dart`). Features never import Firebase packages directly.
2. **Windows spike in stage 1:** on Windows verify Google sign-in → Firebase Auth, Firestore read, write, real-time listener and offline cache. Record the result in `docs/DECISIONS.md`.
3. If something does not work on Windows, implement a Windows-only repository (Firestore REST API with the user's ID token, or `firedart`) behind the same interfaces, with a small local cache (e.g. drift) for offline use. No other code changes.
4. Run the same spike on macOS (sandbox entitlements, keychain, sign-in) so both desktop platforms are proven before feature work starts.

---

## 3. Organizations, roles and permissions

### 3.1 Roles (per organization)
| Role | Can |
|---|---|
| **Employee** (`employee`) | Track time; add, edit and delete **own** entries. Set **own** Work/Standby rates. View **own** reports and export them to CSV. See active projects. Edit own profile (first/last name). Leave the organization. |
| **Admin** (`admin`) | Everything an employee can do for their own hours, plus: create, edit, archive and delete projects; invite people, change roles (except owner), disable members; view team reports and export them; edit organization settings. Admins **do not edit** other people's entries (read-only). |
| **Owner** (`owner`) | Everything an admin can do, plus: transfer ownership, manage subscription, delete the organization. Exactly one owner per organization. |

A user can belong to several organizations (e.g. works for two companies) and switches between them; each membership has its own role and rates.

### 3.2 Security rules (mandatory)
- All permissions are enforced by **Firestore Security Rules** and **Cloud Functions**. Hiding a button in the app is only a convenience.
- Identity comes only from Firebase Auth (`request.auth.uid`, verified email). Never trust a `uid`, role or org ID sent by the client.
- Membership documents (roles) are written **only by Cloud Functions** (Admin SDK). A user can never create a membership or change their own role.
- An employee cannot read another member's entries, rates or timer, in any query.
- A member of org A cannot read or write anything in org B.
- Disabled members and suspended organizations lose write access (rules check `members/{uid}.status == 'active'` and `orgs/{orgId}.status in ['trial', 'active']`).
- Rules validate every written field: types, allowed keys, `uid == request.auth.uid`, `end > start`, duration ≤ 24 h, rate 0–1 000 000 minor units, description ≤ 500 chars, `createdAt`/`uid` immutable after create.
- Every list query by an employee must be constrained (`where('uid', '==', myUid)`), and rules reject unconstrained ones.
- App Check enforced on Firestore and Functions in production.
- Budget alerts in Google Cloud from day one; document them in `docs/SETUP.md`.

---

## 4. Sign-in, profile and onboarding

1. **Sign in with Google** (only provider). The welcome screen explains what the app does and links to the privacy policy.
2. **Profile (required):** if `users/{uid}` has no `firstName` or `lastName`, show the "Your name" screen before anything else.
   - Fields: **First name**, **Last name** (both required, trimmed, 1–50 chars, letters, spaces, hyphens and apostrophes; Unicode letters allowed, e.g. "Łukasz", "O'Neil").
   - Prefill from the Google display name (split on the last space), but the user must confirm or correct it.
   - The Google account email is shown read-only.
   - Names can be changed later in Settings → Profile. A Cloud Function copies the new name to every `members` document of that user, so admins see the current name in reports.
   - Reports, CSV and the Team view always show "First Last" from the profile, never the Google display name.
3. **Organization choice:**
   - **Join with an invite:** type the invite code from the email (primary way, works on every platform) or open the invite link `standwise://join?code=<code>` on a device with the app installed. The callable function `acceptInvite` checks that the signed-in, verified email matches the invited email, creates the membership and marks the invite used.
   - **Create an organization:** company name, currency, timezone. The callable function `createOrganization` creates the org (status `trial`) and makes the user its **owner**.
4. If the user has several memberships, an organization switcher sits in the header; the last used one is remembered.
5. **Account deletion** (required by both stores): Settings → Delete account. Callable function `deleteAccount` removes the profile and memberships, anonymizes the user's entries in each organization (keeps hours for the employer's records, removes name and email, unless the org owner opted to delete them), signs out. An owner must transfer ownership or delete the organization first.

---

## 5. Features and screens

Navigation: **Timer**, **My reports**, **Projects & rates**, **Team** (admins/owner), **Settings**. Bottom navigation bar on phones; `NavigationRail` on wide screens (≥ 900 px). Header: organization name/switcher, role badge (Employee/Admin/Owner), sync status (Saved / Saving… / Offline: changes will sync).

### 5.1 Timer
- **Tracker bar** at the top: "What are you working on?" field, project picker (with color dot), rate type **Work/Standby**, preview of the user's own rate for that choice, clock `H:MM:SS`, **Start/Stop** button.
- Mode switch: **timer** / **manual entry** (date, from, to, calculated duration, Add button).
- Enter in the description field starts the timer.
- The running timer is a Firestore document (`timers/{uid}`): it survives closing the app and shows up on the same user's other devices in real time. At most one running timer per person. Starting a new one stops the previous one and saves it as an entry (one batched write).
- The clock is computed from the stored `start` (not by counting ticks), so it stays correct after the phone wakes up and while offline.
- **Week summary:** week total (live), Work and Standby separately, 7 bars for the days of the week (Work and Standby in different colors).
- **Entry list** grouped by day (Today, Yesterday, then "Tuesday, 3 November"), with total time and amount per day.
  - Wide screens: inline-editable rows: description, project, type, rate, from–to, date, duration, "Continue", delete.
  - Phones: entry cards; tapping opens an edit bottom sheet with the same fields.
  - Delete with a SnackBar "Undo".
- Entries across midnight: if "to" ≤ "from", the end is on the next day.
- Last 14 days by default, "Show earlier days" button (paginated query).
- Empty state with instructions. Admins get "Load sample data" (projects prefixed "Sample:", removable in one click).

### 5.2 Rates
- Each member has two own rates per project: **Work** and **Standby** (per hour, 2 decimals, accept comma and dot).
- An entry stores the **rate at the time it was created** (`rateMinor`). Changing a project rate affects new entries only.
- Changing an entry's project or type fills in the member's current rate. The rate of a single entry can also be typed in manually.
- Entry amount = `rateMinor × durationMinutes / 60`. Store and compute money in **minor units (int)**, never `double`.
- Rates are visible only to their owner and to admins/owner of the organization.

### 5.3 My reports
- Ranges: This week, Last week, This month, Last month, Custom range. Project filter (including "No project").
- Tiles: Total (h:mm, decimal hours, entry count), Work, Standby, Amount.
- Bar chart (fl_chart) of time per day (per week above 62 days), stacked by project, Y axis in hours, value tooltip.
- Project table: project, client, Work, Standby, Total, share %, Amount.
- **CSV** export (UTF-8 with BOM). Separator and decimal mark follow organization settings (`,` + `.` by default; `;` + `,` for European Excel). Columns: Date, Start, End, Duration (h:mm), Hours, Type, Rate, Amount, Project, Client, Description.

### 5.4 Projects & rates
- Employees: active projects (color, name, client) with two rate fields and their own total time.
- Admins also: add a project (name, client, color from a 10-color palette), edit name/client/color, Archive/Restore, Delete (with confirmation; entries remain as "No project (deleted)"). Archived projects disappear from pickers but stay in reports.

### 5.5 Team (admins/owner)
- Same ranges and project filter as reports, plus a person filter.
- Tiles with team totals.
- People table: **first and last name**, Work, Standby, Total, entries, Amount, and a "Total" row. Selecting a person shows their entries (date, times, project, type, description, duration, rate, amount).
- Chart and project table for the whole team.
- Team CSV with extra first columns "First name", "Last name", "Email".
- All active members appear, even with zero hours.
- Totals come from the `summaries` documents (section 6), entry details from `entries` queries.

### 5.6 Members and invites (admins/owner)
- Members list: first name, last name, email, role, status, joined date. Change role, disable/enable, remove. The owner cannot be demoted; use "Transfer ownership".
- Invite: email + role (employee/admin). Callable `createInvite` stores the invite (7-day expiry) and sends an email with the invite code (short, easy to type, e.g. `K7M2-9QXP`), the `standwise://` link and store download links (Firebase "Trigger Email" extension with an SMTP provider, or an equivalent). Pending invites can be resent or revoked.
- Invited people still enter their own first and last name on first sign-in (section 4).

### 5.7 Settings
- **Profile** (everyone): first name, last name (editable), email (read-only), sign out, delete account.
- **Organization** (admins/owner): company name, currency, timezone, first day of week, CSV format.
- **Subscription** (owner, phase 2, see section 9).
- **About:** app version, link to the GitHub repo, privacy policy, terms.

### 5.8 Look and feel
- Material 3 with a custom `ColorScheme`; light and dark theme following the system. Green accent for Start/Work, amber for Standby, red for Stop/delete. Original design, no imitation of existing brands.
- Tabular figures for time digits (`FontFeature.tabularFigures()`).
- Responsive from 360 px (`LayoutBuilder`, breakpoints 600 and 900 px). Tables scroll horizontally inside their own container.
- Accessibility: `Semantics`, labeled fields, keyboard support and shortcuts on Windows/macOS (Enter = Start, Esc = close editor), native menu bar on macOS, large touch targets on phones.
- Reference for features and layout: the existing web prototype "Licznik Godzin" (Claude artifact). Reproduce the features and layout in English; write all code from scratch in Flutter.

---

## 6. Firestore data model

Timestamps are Firestore `Timestamp` (UTC). IDs of entries and projects are generated client-side (`doc().id`), so offline writes are idempotent. Money in minor units (`int`).

```
users/{uid}
  firstName, lastName, email, photoUrl?, lastOrgId?, createdAt, updatedAt

orgs/{orgId}
  name, status: 'trial'|'active'|'suspended', plan, trialEndsAt,
  settings: { currency, timezone, weekStart, use24h, csvSeparator, csvDecimal },
  ownerUid, memberCount, createdAt, updatedAt

orgs/{orgId}/members/{uid}                 # written only by Cloud Functions
  role: 'owner'|'admin'|'employee', status: 'active'|'disabled',
  firstName, lastName, email,              # copied from users/{uid}
  joinedAt, updatedAt

orgs/{orgId}/members/{uid}/rates/{projectId}
  workRateMinor, standbyRateMinor, updatedAt

orgs/{orgId}/projects/{projectId}
  name, client, color, archived, deleted, createdAt, updatedAt

orgs/{orgId}/entries/{entryId}
  uid, projectId?, type: 'work'|'standby', rateMinor,
  start, end, durationMin, description, monthKey: 'YYYY-MM',
  deleted, createdAt, updatedAt

orgs/{orgId}/timers/{uid}
  projectId?, type, description, start, updatedAt

orgs/{orgId}/summaries/{uid}_{YYYY-MM}     # written only by Cloud Functions
  uid, monthKey,
  days: { 'DD': { workMin, standbyMin, amountMinor,
                  byProject: { projectId: { workMin, standbyMin, amountMinor } } } },
  updatedAt

orgs/{orgId}/invites/{inviteId}            # written only by Cloud Functions
  email, role, codeHash, expiresAt, status: 'pending'|'accepted'|'revoked', createdBy

orgs/{orgId}/auditLog/{id}                 # written only by Cloud Functions
  at, actorUid, action, entity, entityId, details
```

Rules and behavior:
- Employees read/write `entries` only where `uid == request.auth.uid`; admins/owner read all entries of their org and may change other people's entries only as a signed edit (D-050).
- `rates` under `members/{uid}` are writable only by that member; readable by that member and by admins/owner.
- **Summaries:** a Firestore trigger on `entries` writes recomputes the affected `{uid}_{YYYY-MM}` summary **from that month's entries** (not with increments, because triggers run at least once). Team reports read one summary per member per month instead of every entry.
- Deleting an entry sets `deleted = true` (hidden everywhere, instantly undoable). A scheduled function hard-deletes soft-deleted entries after 30 days.
- Composite indexes in `firestore.indexes.json`: `entries (uid, start)`, `entries (deleted, start)`, `entries (uid, deleted, start)`.
- Keep Firestore reads low: use listeners only for the current week, today's timer and small collections (projects, members); paginate history; never listen to all entries of an organization.

---

## 7. Cloud Functions

TypeScript in `functions/`, each in its own module, all with input validation (zod), auth and role checks, App Check enforcement, and audit log entries.

| Function | Type | Who | Purpose |
|---|---|---|---|
| `createOrganization` | callable | signed-in user with profile | create org (status `trial`), owner membership |
| `createInvite` / `resendInvite` / `revokeInvite` | callable | admin/owner | manage invites, send email |
| `acceptInvite` | callable | invited user (email must match) | create membership |
| `setMemberRole` / `setMemberStatus` / `removeMember` | callable | admin/owner (owner rules apply) | manage members |
| `transferOwnership` | callable | owner | move owner role |
| `leaveOrganization` | callable | member (not owner) | remove own membership |
| `deleteOrganization` | callable | owner | delete org data (batched, recursive) |
| `deleteAccount` | callable | user | see section 4 |
| `onUserProfileUpdated` | Firestore trigger | – | copy first/last name to all memberships |
| `onEntryWritten` | Firestore trigger | – | recompute summary for that user and month |
| `purgeDeletedEntries` | scheduled daily | – | hard-delete soft-deleted entries older than 30 days |
| `exportOrgCsv` | callable | admin/owner | (optional) large CSV exports generated server-side |

Everyday user actions (timer, entries, rates, projects) are plain Firestore writes protected by rules, so they work offline. Only org/member/invite/account operations use callables (online only; the UI says so).

---

## 8. Offline and sync

- Use Firestore's built-in offline cache and write queue. All everyday writes are idempotent (client-generated IDs, full-document `set` with `updatedAt`).
- The sync indicator uses `snapshot.metadata.hasPendingWrites` / `isFromCache` and connectivity (`connectivity_plus`).
- Timer start/stop offline works (batched write), and syncs later.
- Conflict policy: last write wins per document; editing the same entry on two devices offline is acceptable.
- On Windows, if Firestore offline persistence turns out unreliable (stage 1 spike), the Windows repository adds a small local cache (e.g. drift) behind the same interfaces.

---

## 9. Subscriptions (phase 2, design hooks now)

- `orgs/{orgId}.status` and `plan` drive access; rules already block writes for `suspended`.
- New organizations get a free trial (e.g. 30 days, `trialEndsAt`). A scheduled function moves expired trials to `suspended` (read-only, data kept; export still possible).
- Billing behind a `BillingRepository` interface, priced per active member. Candidate providers: in-app subscriptions through the App Store (iOS/macOS) and Google Play (Android), e.g. unified with RevenueCat; on Windows a Stripe-hosted Checkout page opened in the browser (no own hosting needed) or the Microsoft Store. Follow the current Apple App Review Guidelines (section 3.1), Google Play payments policy and Microsoft Store policy — verify before implementing.
- Optional later feature: export team hours to the customer's own Google Sheet (needs Google OAuth verification for the Sheets scope).

---

## 10. Repository and environments

Repository: **https://github.com/fpvsonderling/StandwiseWork-on-call-time-tracker**. Description: "Work & on-call (standby) time tracker for teams — Flutter app with a Firebase backend." Topics: `flutter`, `firebase`, `time-tracking`, `timesheet`, `on-call`, `dart`, `saas`.

Two Firebase projects: **`standwise-dev`** and **`standwise-prod`** (Flutter flavors `dev`/`prod`, generated with `flutterfire configure`). Firebase config files are identifiers, not secrets; restrict the API keys in Google Cloud and rely on App Check and rules. Real secrets (signing keys, SMTP, Stripe, CI service account) live in GitHub Secrets / Secret Manager. Deploy from CI with **Workload Identity Federation** (no JSON key files in the repo).

```
StandwiseWork-on-call-time-tracker/
├─ lib/
│  ├─ main_dev.dart, main_prod.dart
│  ├─ app/                 # router (auth/profile/org redirects), theme, l10n, flavors
│  ├─ core/                # auth (google_sign_in on Android/iOS/macOS, Windows desktop OAuth), errors, money, time
│  ├─ data/
│  │  ├─ repositories/     # interfaces
│  │  ├─ firebase/         # FlutterFire implementations
│  │  └─ windows/          # fallback implementations if needed (REST/firedart)
│  ├─ domain/              # pure models and functions: durations, money, ranges, CSV, summaries
│  ├─ features/            # auth, profile, onboarding, org, timer, entries, reports, projects, team, members, settings
│  └─ l10n/                # app_en.arb (later app_pl.arb …)
├─ test/  integration_test/
├─ android/  ios/  macos/  windows/
├─ functions/              # TypeScript Cloud Functions + tests
├─ firestore.rules  firestore.indexes.json  firebase.json  .firebaserc
├─ rules-tests/            # security rules tests (emulator)
├─ store/                  # store texts, keywords, screenshots per platform/locale
├─ docs/
│  ├─ SETUP.md             # step by step from zero (non-technical friendly)
│  ├─ ARCHITECTURE.md      # diagram, data model, security model
│  ├─ PRIVACY.md  TERMS.md # must be reachable at a public URL (see section 11)
│  └─ DECISIONS.md
├─ .github/
│  ├─ workflows/
│  │  ├─ ci.yml            # flutter analyze/test, functions lint/test, rules tests on emulator, store text limits
│  │  ├─ deploy-dev.yml    # on main: rules, indexes, functions → standwise-dev
│  │  ├─ deploy-prod.yml   # on tag v*: same → standwise-prod (manual approval environment)
│  │  └─ release.yml       # on tag v*: AAB/APK, Windows zip/MSIX, macOS .app/.dmg and iOS build (macOS runner; signing when secrets exist)
│  ├─ ISSUE_TEMPLATE/  pull_request_template.md
├─ README.md  CONTRIBUTING.md  CHANGELOG.md  LICENSE
```

- Git-ignored: `key.properties`, keystores, `.env*`, service account files, `google-services.json`/`GoogleService-Info.plist` for prod if you prefer to inject them in CI (document the choice).
- Application ID / bundle ID: `com.<yourdomain>.standwise` (set during setup).
- `docs/SETUP.md`: create both Firebase projects, enable Blaze + budget alerts, Auth (Google provider), Firestore (EU), Functions, App Check, OAuth clients (Web client auto-created by Firebase and used as `serverClientId`, Android with SHA-1/SHA-256, iOS/macOS with bundle IDs, Desktop for Windows), email extension, `flutterfire configure`, run on each platform, emulator usage, deploy, macOS signing and notarization (Developer ID or Mac App Store), Windows packaging (MSIX), publish to stores.
- Conventional Commits. Protected `main`, changes via PRs.

---

## 11. App Store and Google Play discoverability (ASO)

Put all texts in `store/` and keep them under the limits (CI checks lengths).

- **App name / title** (max 30, both stores): `Standwise: Hours & Standby`
- **iOS subtitle** (max 30): `Work & on-call time tracker`
- **iOS keywords** (max 100, comma-separated, no spaces, no words from the title): `timesheet,on-call,oncall,shift,work,log,clock,in,out,overtime,payroll,team,tracker,timer,rate`
- **Google Play short description** (max 80): `Track work and standby (on-call) hours, rates and team reports. Works offline.`
- **Full description** (max 4000): first 2 lines state the value; then features; natural keywords: time tracker, timesheet, work hours, standby, on-call, hourly rate, team reports, CSV export, offline, multiple companies.
- **Category:** Business (primary), Productivity (secondary).
- **Screenshots:** 6–8 per platform with benefit captions ("Track work and standby in one tap", "Your hours, your rates", "Team reports for admins"), light and dark, phone, tablet and Mac sizes; generated by an integration test with sample data.
- **Stores:** Google Play, App Store (iOS) and Mac App Store (same listing texts; macOS category Business). Windows: direct download from GitHub Releases first, Microsoft Store optional later.
- **App icon:** simple, recognizable at 48 px, original (e.g. a clock face half work, half standby).
- **Localized listings** later (Polish first) in `store/<locale>/`.
- **Privacy:** both stores require a public privacy policy URL. Without own hosting, publish `docs/PRIVACY.md` at a public address (e.g. the file on a public GitHub repo or a public Gist; if the repo stays private, use a separate public location) and link it in the app; App Store privacy labels and Play Data safety filled in honestly (name, email, work time data; no ads, no tracking); in-app account deletion.
- "StandBy" is also an iOS feature name, so searches for "standby" alone show widget apps. Rely on "timesheet", "on-call" and "work hours" as main keywords.

---

## 12. Build order

1. Flutter skeleton (Android, iOS, Windows, macOS), flavors, CI, theme, navigation, l10n, `domain/` with tests. Firebase dev project, `flutterfire configure`. **Windows and macOS spike** (section 2.1).
2. Auth on all platforms, **profile screen with first/last name**, router redirects, `users` docs, Functions skeleton, rules + rules tests, emulator setup.
3. Organizations: `createOrganization`, invites (`createInvite`, `acceptInvite`, email), members, org switcher.
4. Projects & rates.
5. Timer and entries (timer doc, manual entries, list, edit, soft delete with Undo), offline indicator.
6. My reports: ranges, tiles, chart, table, CSV on every platform.
7. Summaries trigger, Team view, team CSV, members management, settings, account deletion, audit log.
8. App Check, Crashlytics, prod project, deploy workflows, release workflow, icons/splash, screenshots, `store/` texts, privacy policy, terms, polished README.
9. (Phase 2) Trials, subscriptions, optional Google Sheets export, Polish localization.

---

## 13. Acceptance criteria

- Rules tests prove: a member of org A cannot read or write any document of org B; an employee cannot read another member's entries, rates or timer; nobody can create a membership or change a role from the client; disabled members and suspended orgs cannot write; invalid entries (end ≤ start, > 24 h, wrong `uid`, extra fields) are rejected.
- A new user cannot reach any screen except sign-in, privacy policy and "Your name" until first and last name are saved. Names appear correctly in Team, member lists and CSV, and a name change shows up there after the trigger runs.
- `acceptInvite` fails when the signed-in email differs from the invited email or the invite is expired/revoked.
- Team totals equal the sum of the member's entries (summary recomputation tested, including duplicate trigger delivery).
- Amount = rate × time with integer minor units; no floating-point errors; rounding only for display.
- Entries across midnight are correct; daily reports assign an entry to its start day in the org timezone.
- A timer started on a phone is visible and can be stopped on Windows and on macOS.
- Entries created offline sync without duplicates.
- CSV opens correctly in Excel with both CSV format settings.
- Works at 360 px width, on wide screens and in dark mode; no hard-coded user-facing strings outside ARB files.
- Account deletion works and meets App Store and Google Play requirements.
- `flutter analyze`, `flutter test`, Functions tests, rules tests and CI pass; Android, iOS, Windows and macOS builds are produced by GitHub Actions; store texts are within limits.

Start with stage 1. After each stage, briefly describe what you did, how to verify it and what comes next.
