# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/) and the project uses [Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Added
- Stage 1 skeleton: Flutter app for Android, iOS, Windows and macOS with `dev`/`prod` entry points, Material 3 light/dark theme, responsive navigation (bottom bar / rail), English ARB localization.
- `domain/`: integer money maths, rate parsing, duration formatting, midnight-crossing manual entries, report ranges, name validation — with unit tests.
- Repository interfaces with FlutterFire implementations; Google sign-in via `google_sign_in` (Android/iOS/macOS) and desktop OAuth with PKCE + loopback (Windows).
- Dev-only Platform check screen for the Windows/macOS spike.
- CI: format, analyze, tests, and Android/Windows/macOS/iOS builds.
