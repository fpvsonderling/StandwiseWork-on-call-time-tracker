# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/) and the project uses [Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Removed
- Settings → About no longer links to the source code.

### Added
- New app icon ("split ring": work and standby arcs around clock hands) on Android, iOS, macOS and Windows.
- Privacy Policy and Terms of Use, readable in the app from the welcome screen and Settings → About.
- Team: "Export team CSV" now exports the People table (per-person totals and a Total row); "Export all entries" keeps the detailed export.
- Signed iOS and macOS builds uploaded to TestFlight from CI on every push to `main`; Google sign-in URL scheme on iOS and macOS.
- Stage 7: Team view for admins (totals, people table, one person's entries, chart, projects, team CSV); member actions (make admin/employee, disable, enable, remove, transfer ownership); organization settings (name, currency, timezone, week start, 24-hour clock, CSV format); activity log; leave organization, delete organization, delete account.
- Cloud Functions `setMemberRole`, `setMemberStatus`, `removeMember`, `transferOwnership`, `leaveOrganization`, `deleteOrganization`, `deleteAccount`; `onEntryWritten` keeps monthly summaries; `purgeDeletedEntries` (daily) removes deleted entries after 30 days.
- Stage 6: My reports with ranges (this/last week and month, custom), project filter, totals, daily chart, project table and CSV export.
- Stage 5: timer (start, stop, switch, continue, at most one per person), manual entries across midnight, edit, delete with undo, week summary, sync status in the header; works offline.
- Stage 4: projects with colors, archive/restore/delete, personal work and standby rates per project (and for "No project"), sample data.
- Stage 3: create an organization (30-day trial) or join one with an invite code; organization switcher in the header; read-only banner for suspended organizations; Settings → Members and invites for admins (invite by email, resend, revoke, copy code).
- Cloud Functions `createOrganization`, `createInvite`, `resendInvite`, `revokeInvite`, `acceptInvite`; invite emails queued for the Trigger Email extension.
- Stage 2: welcome screen with Google sign-in, required "Your name" screen (prefilled from the Google name), Settings → Profile and sign out, router redirects for sign-in and profile.
- Firestore security rules for the whole data model, with emulator tests in `rules-tests/`.
- Cloud Functions skeleton in `functions/` (TypeScript, `europe-west1`) with `onUserProfileUpdated`, which copies name changes to every membership.
- Emulator suite configuration and `USE_EMULATORS` app switch.
- CI: Functions and security rules jobs; Android signing fingerprints in the job summary.
- Stage 1 skeleton: Flutter app for Android, iOS, Windows and macOS with `dev`/`prod` entry points, Material 3 light/dark theme, responsive navigation (bottom bar / rail), English ARB localization.
- `domain/`: integer money maths, rate parsing, duration formatting, midnight-crossing manual entries, report ranges, name validation — with unit tests.
- Repository interfaces with FlutterFire implementations; Google sign-in via `google_sign_in` (Android/iOS/macOS) and desktop OAuth with PKCE + loopback (Windows).
- Dev-only Platform check screen for the Windows/macOS spike.
- CI: format, analyze, tests, and Android/Windows/macOS/iOS builds.

### Changed
- License: MIT (was proprietary); the repository is public.
