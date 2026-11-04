# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/) and the project uses [Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Added
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
