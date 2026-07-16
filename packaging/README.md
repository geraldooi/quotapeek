# Homebrew release

QuotaPeek is distributed as a Homebrew cask so installation remains a single command.

1. Build the release app on macOS:

   ```sh
   make app
   ditto -c -k --keepParent dist/QuotaPeek.app QuotaPeek-0.1.0.zip
   shasum -a 256 QuotaPeek-0.1.0.zip
   ```

2. Notarize the app for public distribution, then attach the zip to a `v0.1.0` GitHub release.

3. Copy `packaging/Casks/quotapeek.rb.template` into a Homebrew tap repository as `Casks/quotapeek.rb`.

4. Replace `OWNER` and `REPLACE_WITH_RELEASE_SHA256`.

Users can then install or upgrade with:

```sh
brew install --cask geraldooi/tap/quotapeek
brew upgrade --cask quotapeek
```
