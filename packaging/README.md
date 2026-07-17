# Release and Homebrew packaging

QuotaPeek uses Release Please and GitHub Actions to version, build, publish, and
update its Homebrew cask. Feature and fix merges update a cumulative release
pull request. Merging that release pull request automatically publishes the
version it contains.

## Signing and Gatekeeper

Releases use an ad-hoc code signature and are not notarized by Apple. This keeps
distribution independent of the paid Apple Developer Program.

Homebrew can install the app normally, but Gatekeeper may block its first
launch. A user who trusts the release can:

1. Try to open QuotaPeek.
2. Open **System Settings → Privacy & Security**.
3. Click **Open Anyway** for QuotaPeek.

The release notes and Homebrew cask repeat this notice so users see it before
launching the app.

## GitHub repository secret

Add these Actions repository secrets to `geraldooi/quotapeek`:

| Secret | Value |
| --- | --- |
| `RELEASE_PLEASE_TOKEN` | Fine-grained token scoped to `geraldooi/quotapeek` with read/write access to contents, issues, and pull requests |
| `TAP_GITHUB_TOKEN` | Fine-grained token that can write repository contents to `geraldooi/homebrew-tap` |

`RELEASE_PLEASE_TOKEN` is required so CI runs automatically on the generated
release pull request. The Release workflow fails with setup guidance if it is
absent. Keep the two tokens separate and grant each access only to its named
repository. No Apple signing or notarization credentials are required.

## Automated release flow

1. Merge feature and fix pull requests with Conventional Commit titles.
2. Release Please creates or updates its release pull request with the proposed
   `VERSION` and generated `CHANGELOG.md`.
3. Merge the release pull request when the accumulated changes are ready.
4. The Release workflow creates the tag and GitHub release, uploads the
   universal archive, and publishes the Homebrew cask.

## Homebrew tap

The public tap repository is named `geraldooi/homebrew-tap`. Homebrew maps that
repository to the short tap name `geraldooi/tap`.

The release workflow writes:

```text
Casks/quotapeek.rb
```

After the first successful release:

```sh
brew install --cask geraldooi/tap/quotapeek
```

For later versions:

```sh
brew update
brew upgrade --cask quotapeek
```

## Manual recovery

If creating the GitHub release succeeds but packaging or updating the tap
fails, manually run the **Release** workflow with that existing version. It
rebuilds a missing archive and retries Homebrew publication without replacing
an archive that is already attached.

For manual recovery, download the release asset, calculate its checksum, and
replace the version and checksum in the tap:

```sh
shasum -a 256 QuotaPeek-0.1.0.zip
```

Then validate and push the cask from the tap checkout:

```sh
brew tap geraldooi/tap /path/to/homebrew-tap
brew audit --cask --online geraldooi/tap/quotapeek
```
