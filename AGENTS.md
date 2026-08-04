# QuotaPeek agent guidance

## Read first

- Read `CONTEXT.md` before naming or changing domain concepts.
- Read the relevant records in `docs/adr/` before changing privacy boundaries,
  architecture, distribution, or releases.
- Read `README.md` for product behavior and `CONTRIBUTING.md` for the current
  development and release workflow.

## Product boundaries

- Keep QuotaPeek a lightweight, read-only, glanceable macOS menu-bar utility.
- Do not add account login, credential access, prompt or response collection,
  analytics, or historical dashboards without explicit product approval.
- Report only usage that a provider's source can support. Do not invent a
  quota percentage to make providers look symmetrical.
- New network integrations must send no local usage data, prompt content,
  credentials, or user identifiers. Disclose every integration in `README.md`.
- Preserve actionable unavailable, inactive, limited, and error states instead
  of silently presenting missing data as zero usage.
- Preserve accessibility behavior, including VoiceOver labels and Reduce Motion.

## Architecture

- Keep provider parsing, models, and formatting in `QuotaPeekCore`; it must not
  depend on SwiftUI or AppKit.
- Keep menu-bar and popover presentation in the `QuotaPeek` executable target.
- Prefer Foundation and system frameworks. Adding a package dependency requires
  a clear reason and explicit approval.
- Treat provider data files as untrusted input: tolerate malformed records,
  partial reads, missing directories, and permission failures.
- Do not expose private paths or record contents in user-facing diagnostics.

## Working agreement

- Fetch `origin/main` and create each branch from the freshly fetched remote
  branch. Use the `codex/` prefix unless the user requests another name.
- Keep each pull request focused. Never develop directly on `main`.
- Show the user the proposed changes and exact Conventional Commit message
  before committing. Do not commit until the user approves.
- Before every commit, inspect the staged diff and scan it for credentials,
  tokens, private keys, personal data, and unrelated files.
- Run `make verify` before opening a pull request. If the local Apple toolchain
  prevents a test, report the exact mismatch and still run every viable check.
- Use a ready-for-review pull request with a Conventional Commit title of at
  most 72 characters. Never add an agent prefix to the title.
- Resolve CI failures and actionable review findings on the same branch. Reply
  with fix details and resolve addressed review threads.
- Merge only when CI and review are clean. Use squash merge and preserve the PR
  title as the squash commit subject.
- Never use Computer Use to inspect QuotaPeek's macOS menu-bar item; it cannot
  observe the status bar reliably. Build and install the app, then let the user
  confirm the visible result.

## Versioning and releases

- `main` is the production-ready source branch, not a signal to publish every
  merged change immediately.
- Do not edit `VERSION` or `CHANGELOG.md` in ordinary feature and fix pull
  requests. Release Please owns those files.
- Feature and fix merges accumulate in one Release Please pull request. The
  user decides when to merge it and publish a release.
- Releases remain universal, ad-hoc signed, and not notarized unless the user
  explicitly revisits the Apple Developer Program decision.
- Never replace an existing tag or release artifact. Use the manual release
  workflow only to recover publication of an existing version.

## Common commands

```sh
make test
make app
make verify
make install
```
