# QuotaPeek

A small, native macOS menu-bar app for seeing Codex and Claude Code quota usage at a glance.

## What it shows

- **Codex:** rolling usage percentage, remaining percentage, reset time, and next-48-hour reset forecast.
- **Claude Code:** official five-hour and weekly usage percentages and reset times.
- A configurable menu-bar summary for all visible providers, one provider, or an icon-only mode.
- A subtle release-page link when a newer stable QuotaPeek version is available.
- Actionable recovery states with privacy-safe diagnostics when local usage cannot be read.
- VoiceOver-friendly usage summaries and refresh motion that respects macOS Reduce Motion.
- A native SwiftUI popover that refreshes automatically every minute.

QuotaPeek reads usage records locally from:

- `~/.codex/sessions`
- `~/.codex/archived_sessions`

Claude quota bars use an opt-in local status-line bridge. QuotaPeek preserves
and forwards any existing Claude Code status-line command, then stores only the
official five-hour and seven-day percentages and reset times that Claude Code
provides after an API response. It does not read Claude credentials or call an
authenticated Anthropic endpoint.

It does not read prompt or response text, send analytics, or access credentials.
To show the Codex reset forecast, QuotaPeek makes an unauthenticated HTTPS GET
request to `www.willcodexquotareset.com` at launch and when that source says its
forecast is due to refresh. The request has no payload and does not include
local usage data.
To check for updates, QuotaPeek also makes an unauthenticated HTTPS GET request
to GitHub's public latest-release endpoint at launch and then at most once every
six hours after a successful check. This request also has no payload and does
not include local usage data.

> Enable **Claude quota bars** from QuotaPeek settings, then send one Claude
> Code message so Claude can provide current quota data.

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
