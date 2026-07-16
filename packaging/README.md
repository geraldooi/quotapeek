# Release and Homebrew packaging

QuotaPeek uses GitHub Actions to build, sign, notarize, publish, and update its
Homebrew cask. The workflow runs manually from `main`; merging a pull request
does not release automatically.

## One-time Apple setup

Public macOS distribution requires an active Apple Developer Program
membership.

1. Install full Xcode and sign in with the Apple developer account.
2. Create or install a **Developer ID Application** certificate.
3. Export the certificate and private key from Keychain Access as a
   password-protected `.p12` file.
4. Create an App Store Connect API key with access to notarization and download
   its `.p8` file. Record its key ID and issuer ID.

Local `make app` builds use ad-hoc signing and do not require these credentials.

## GitHub repository secrets

Add these Actions secrets to `geraldooi/quotapeek`:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64-encoded Developer ID `.p12` file |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_API_KEY_P8` | Base64-encoded App Store Connect `.p8` file |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID |
| `TAP_GITHUB_TOKEN` | Repository secret containing a fine-grained token that can write contents to `geraldooi/homebrew-tap` |

Encode the two credential files without copying their contents into the
repository:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_KEYID.p8 | pbcopy
```

Store the five Apple release secrets in a GitHub environment named
`production`. Store `TAP_GITHUB_TOKEN` as a repository secret because it is
used by the separate Homebrew publication job. An optional required reviewer
can be added to the environment to provide a manual approval gate before
signing and publishing.

## Homebrew tap

The public tap repository must be named `geraldooi/homebrew-tap`. Homebrew maps
that repository to the short tap name `geraldooi/tap`.

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
Homebrew publication without replacing the signed artifact.

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
