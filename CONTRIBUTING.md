# Contributing to QuotaPeek

## Branch and pull request flow

`main` is the production-ready source branch. Do not develop directly on it.

1. Update local `main`:

   ```sh
   git switch main
   git pull
   ```

2. Create a focused branch:

   ```sh
   git switch -c codex/short-description
   ```

3. Make the change and run:

   ```sh
   make verify
   ```

4. Push the branch and open a pull request into `main`.
5. Merge only after the required CI check passes.

The CI workflow runs the tests and verifies that packaging produces a signed
universal app bundle.

## Versioning

QuotaPeek uses semantic versions stored in the top-level `VERSION` file:

- Patch, such as `0.1.1`: backward-compatible fixes.
- Minor, such as `0.2.0`: backward-compatible features.
- Major, such as `1.0.0`: stable or compatibility-breaking releases.

Merging into `main` does not automatically create a release. When the changes
on `main` are ready to ship, first merge a pull request that updates `VERSION`.

## Creating a release

From the GitHub repository:

1. Open **Actions**.
2. Select **Release**.
3. Choose **Run workflow** on `main`.
4. Enter the exact value from `VERSION`, without a `v` prefix.

The workflow:

1. Runs the test suite.
2. Builds an `arm64` and `x86_64` universal app.
3. Signs the app with a Developer ID Application certificate.
4. Submits the app to Apple's notarization service and staples the ticket.
5. Publishes `QuotaPeek-<version>.zip` in a `v<version>` GitHub release.
6. Updates `Casks/quotapeek.rb` in `geraldooi/homebrew-tap`.

Tags and release artifacts are immutable outputs. Never replace an existing
version; increment `VERSION` and create a new release instead.

See [packaging/README.md](packaging/README.md) for the required secrets and
first-time signing setup.
