# Release and Homebrew packaging

QuotaPeek uses GitHub Actions to build, publish, and update its Homebrew cask.
The workflow runs manually from `main`; merging a pull request does not release
automatically.

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

Add this Actions repository secret to `geraldooi/quotapeek`:

| Secret | Value |
| --- | --- |
| `TAP_GITHUB_TOKEN` | Fine-grained token that can write repository contents to `geraldooi/homebrew-tap` |

No Apple signing or notarization credentials are required.

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

If the GitHub release succeeds but updating the tap fails, rerun the Release
workflow with the same version. It detects the existing release and retries the
Homebrew publication without replacing the artifact.

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
