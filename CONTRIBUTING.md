# Contributing

1. Read [`docs/SPEC.md`](docs/SPEC.md) and [`docs/DECISIONS.md`](docs/DECISIONS.md).
2. Branch from `main`; open a pull request. `main` is protected and CI must pass.
3. Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:` …).
4. Before pushing:
   ```sh
   dart format lib test
   flutter analyze
   flutter test
   ```
5. Rules for code:
   - Features never import Firebase packages; go through `lib/data/repositories/`.
   - Money is `int` minor units, never `double`.
   - Every user-facing string goes in `lib/l10n/app_en.arb`.
   - When the spec is open, choose the simplest option and add a row to `docs/DECISIONS.md`.
