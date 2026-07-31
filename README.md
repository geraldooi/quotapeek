# QuotaPeek

A small, native macOS menu-bar app for seeing Codex and Claude Code token usage at a glance.

## What it shows

- **Codex:** rolling usage percentage, remaining percentage, reset time, next-48-hour reset forecast, and current-session token totals.
- **Claude Code:** tokens used in the last five hours, tokens used today, and input/cache/output totals.
- A compact menu-bar summary with Codex's rolling percentage (or session tokens when limits are unavailable) and Claude's five-hour token count.
- A subtle release-page link when a newer stable QuotaPeek version is available.
- Actionable recovery states with privacy-safe diagnostics when local usage cannot be read.
- A native SwiftUI popover that refreshes automatically every minute.

QuotaPeek reads usage records locally from:

- `~/.codex/sessions`
- `~/.codex/archived_sessions`
- `~/.claude/projects`

It does not read prompt or response text, send analytics, or access credentials.
To show the Codex reset forecast, QuotaPeek makes an unauthenticated HTTPS GET
request to `www.willcodexquotareset.com` at launch and when that source says its
forecast is due to refresh. The request has no payload and does not include
local usage data.
To check for updates, QuotaPeek also makes an unauthenticated HTTPS GET request
to GitHub's public latest-release endpoint at launch and then at most once every
six hours after a successful check. This request also has no payload and does
not include local usage data.

> Claude Code's local records do not contain a reliable subscription quota percentage. QuotaPeek reports observed Claude token usage rather than guessing how much of a plan remains.

## Requirements

- macOS 13 Ventura or newer
- Xcode Command Line Tools
- Codex and/or Claude Code used at least once

## Build and run

```sh
make app
open dist/QuotaPeek.app
```

`make app` creates an ad-hoc-signed universal Apple Silicon and Intel app
bundle.

To install the local build:

```sh
make install
```

This copies the app to `~/Applications`, so administrator access is not needed.

## Homebrew distribution

Stable releases are versioned and published through GitHub Actions. Release
Please keeps a release pull request updated from conventional feature and fix
titles. Merging that release pull request publishes the app and updates the
cask in
[`geraldooi/homebrew-tap`](https://github.com/geraldooi/homebrew-tap), after
which users can install with:

```sh
brew install --cask geraldooi/tap/quotapeek
```

Releases are ad-hoc signed and are not notarized by Apple, so macOS may require
first-launch approval under **System Settings → Privacy & Security → Open
Anyway**.

See [packaging/README.md](packaging/README.md) for the release steps.

## Development

```sh
make test
make verify
```

The project is a dependency-free Swift Package with separate core parsing logic and SwiftUI presentation.

Changes are developed on branches and merged into `main` through pull requests.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the development and release flow.
