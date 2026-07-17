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

4. Push the branch and open a pull request into `main`. Use a Conventional
   Commit title such as `feat(ui): add compact usage cards` or
   `fix(refresh): keep rotation centered`.
5. Merge only after the required CI check passes.
6. Use **Squash and merge**, preserving the pull request title as the squash
   commit subject.

The required CI workflow validates the pull request title, runs the tests, and
verifies that packaging produces an ad-hoc-signed universal app bundle. Use
`feat` for a backward-compatible feature, `fix` for a bug fix, and add `!`
before the colon for a breaking change.

The repository must allow squash merging only and use the pull request title as
the default squash commit message. Release Please reads the resulting commit
subjects from `main`, so merge commits or rewritten subjects bypass its semantic
version classification.

## Versioning

QuotaPeek uses semantic versions stored in the top-level `VERSION` file:

- Patch, such as `0.1.1`: backward-compatible fixes.
- Minor, such as `0.2.0`: backward-compatible features.
- Major, such as `1.0.0`: stable or compatibility-breaking releases.

Release Please reads the conventional titles merged into `main` and maintains
one release pull request. That pull request updates `VERSION` and
`CHANGELOG.md` automatically:

- `fix` proposes a patch version.
- `feat` proposes a minor version.
- A title containing `!`, such as `feat!: replace the usage format`, proposes a
  major version.

Additional feature and fix merges update the same release pull request, so
several enhancements can be shipped together without editing `VERSION`
manually.

## Creating a release

Review and merge the Release Please pull request when its accumulated changes
are ready to ship. Its required CI check must pass like any other pull request.

The workflow:

1. Creates the semantic version tag and GitHub release.
2. Runs the test suite.
3. Builds an `arm64` and `x86_64` universal app.
4. Applies an ad-hoc code signature.
5. Publishes `QuotaPeek-<version>.zip` in the GitHub release.
6. Updates `Casks/quotapeek.rb` in `geraldooi/homebrew-tap`.

Tags and release artifacts are immutable outputs. Never replace an existing
version. The manual **Release** workflow input is only a recovery path for an
existing version whose build or Homebrew publication needs to be retried.

See [packaging/README.md](packaging/README.md) for the required Homebrew token
and release details.
