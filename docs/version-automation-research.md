# Automatic versioning and release automation

## Recommendation

Use **Release Please** to maintain one release pull request from `main`. Do not
bump `VERSION` independently in every feature pull request.

Release Please reads Conventional Commits, keeps a release PR updated as more
changes reach the default branch, and performs the version/tag/GitHub Release
step only after that release PR is merged. Its documented mapping is `fix` to a
patch release, `feat` to a minor release, and a breaking change to a major
release. This matches QuotaPeek's preferred model: `main` remains protected and
production-ready, multiple enhancements can be batched, and the maintainer
chooses the release moment by merging a normal reviewed PR. [Release Please:
release PRs and commit semantics](https://github.com/googleapis/release-please#whats-a-release-pr)

The resulting flow would be:

1. A feature or fix PR targets `main`; its squash title uses the repository's
   existing Conventional Commit format, such as
   `feat(ui): size popover to usage content`.
2. After merge, Release Please creates or updates one release PR. That PR shows
   the proposed next version and generated changelog, but does not ship yet.
3. Additional feature PRs continue updating that same release PR.
4. When the batch is ready, merge the release PR after the existing required CI
   check passes.
5. The same release workflow builds the universal macOS app, uploads it to the
   newly created GitHub Release, and updates the Homebrew tap.

This is versioning **on a release PR after merges**, not versioning inside every
development PR. It avoids conflicting edits to the single `VERSION` file and
does not assign a version to code that has not reached `main`.

## Why it fits this repository

QuotaPeek is a single Swift/macOS product with a top-level `VERSION` file and an
existing workflow that tests, packages, publishes a GitHub Release, and updates
Homebrew. Release Please's language-neutral `simple` release type is intended
for a plain version file and `CHANGELOG.md`. Its manifest configuration exposes
`version-file`, so the existing file can remain named `VERSION`, and it supports
arbitrary extra version files if QuotaPeek later needs them. [Release Please
Action: supported release types and configuration](https://github.com/googleapis/release-please-action#release-types-supported),
[Release Please: updating arbitrary files](https://github.com/googleapis/release-please/blob/main/docs/customizing.md#updating-arbitrary-files)

Release Please also recommends squash merges and a linear history. That is a
good fit for a protected `main`, but it makes the final squash commit important:
the PR title that lands on `main` must remain conventional. For example, a merge
title such as `Animate the refresh button (#3)` does not communicate the
`feat`/`fix` release impact. Add a required PR-title check before adopting the
automation. [Release Please: linear history](https://github.com/googleapis/release-please#linear-git-commit-history-use-squash-merge)

GitHub branch protection can require PR review and status checks, so the release
PR can obey the same production controls as feature PRs. The workflow should not
push a version commit directly to protected `main`. [GitHub: protected
branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

## Suggested architecture

Use one workflow triggered by pushes to `main`:

- The Release Please action opens or refreshes the release PR.
- When its `release_created` output is true after the release PR is merged, the
  existing macOS packaging and Homebrew jobs run in that **same workflow**.
- Replace the current manual `gh release create` step with upload/update logic,
  because Release Please will already have created the tag and GitHub Release.
- Keep `workflow_dispatch` as a recovery path for rerunning packaging/Homebrew
  against an existing release.
- Pin third-party actions to full commit SHAs, matching the repository's current
  workflow practice.

Keeping release creation and packaging in one workflow is important. GitHub
documents that events produced with the repository `GITHUB_TOKEN` normally do
not trigger another workflow, and Release Please explicitly warns that its
bot-created PRs/tags/releases have this limitation. Chaining a separate workflow
from a bot-created tag or release would therefore be fragile. [GitHub:
`GITHUB_TOKEN` event behavior](https://docs.github.com/en/actions/concepts/security/github_token#when-github_token-triggers-workflow-runs),
[Release Please Action: other actions on release PRs](https://github.com/googleapis/release-please-action#other-actions-on-release-please-prs)

The Release Please job needs only the documented repository permissions:
`contents: write`, `pull-requests: write`, and `issues: write` for lifecycle
labels. GitHub may also require enabling **Allow GitHub Actions to create and
approve pull requests**. Keep the build/test job at `contents: read`, and keep
the Homebrew token available only to the Homebrew publishing job. [Release
Please Action: workflow permissions](https://github.com/googleapis/release-please-action#workflow-permissions),
[GitHub: configuring workflow permissions](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#configuring-the-default-github_token-permissions)

For fully unattended CI, use a dedicated GitHub App installation token or a
narrowly scoped fine-grained personal access token. GitHub recommends an App
token or PAT when workflow-created PRs must trigger workflows without manual
approval. Do not reuse `TAP_GITHUB_TOKEN`; release automation and Homebrew tap
publication should have separate least-privilege credentials. [GitHub:
workflow-created PR behavior](https://docs.github.com/en/actions/concepts/security/github_token#when-github_token-triggers-workflow-runs)

## Initial migration

The repository is currently at `0.1.0`, and some post-release merge titles are
not Conventional Commits. A safe migration is:

1. Add the Release Please workflow, manifest/config, `CHANGELOG.md`, and a
   required conventional PR-title check through a normal PR.
2. Initialize the manifest at `0.1.0` and configure the `simple` strategy with
   `version-file: VERSION` and `include-v-in-tag: true` so tags retain the
   existing `v0.1.0` shape. Manifest mode supports a single artifact as well as
   monorepos. [Release Please: manifest configuration and bootstrapping](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md)
3. The existing `feat(ui): size popover to usage content (#4)` commit
   deterministically proposes `0.2.0` from the manifest's `0.1.0` baseline.
   Manually add the refresh animation to the initial changelog if Release
   Please cannot infer it from that change's earlier non-conventional merge
   title.
4. Test the full path once: merge a small conventional feature/fix PR, inspect
   the updated release PR, merge it, verify the universal archive, GitHub
   Release, and Homebrew cask, then test the manual recovery path.

## Alternatives considered

### semantic-release

semantic-release also infers the next version from commit messages, generates
notes, tags, and publishes. Its normal model runs after every successful build
on a release branch and releases qualifying changes whenever they reach that
branch. That is strong continuous delivery, but it conflicts with QuotaPeek's
stated desire to batch several enhancements before choosing when to release.
Adapting it to a manually approved batch would discard much of its main
workflow advantage. [semantic-release: triggering a release](https://github.com/semantic-release/semantic-release#triggering-a-release)

### Changesets

Changesets records an explicit changeset file alongside each contributor change
and combines those files into version and changelog updates. Its GitHub Action
can maintain a version PR until it is merged. This gives excellent per-PR
control, but introduces Node/package-oriented metadata and asks every QuotaPeek
PR author to choose and commit release intent. That is extra ceremony for one
small Swift application whose repository already standardizes Conventional
Commit messages. [Changesets: introduction](https://github.com/changesets/changesets/blob/main/docs/intro-to-using-changesets.md),
[Changesets Action](https://github.com/changesets/action)

### Custom version-bump script on every merge

A custom Action could parse the merged PR title, rewrite `VERSION`, and push a
commit after every merge. This is not recommended: it either bypasses the PR
rule on production `main` or creates a new bump PR for every change; concurrent
merges can race; and every qualifying merge becomes a release version even when
the maintainer wants a batch. Release Please already handles the accumulated
history, single release PR, tags, changelog, and retries as a maintained tool.

## Decision

Adopt Release Please with a continuously updated release PR and integrate the
existing macOS/Homebrew publishing steps behind its `release_created` output.
Keep merging the release PR as the explicit production-release approval. This
automates version selection and propagation while preserving protected `main`,
required CI, batched enhancements, and the existing release recovery path.
