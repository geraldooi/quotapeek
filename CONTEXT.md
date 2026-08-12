# QuotaPeek

QuotaPeek presents trustworthy usage information from local AI coding tools in
a glanceable macOS menu-bar interface.

## Language

**Provider**:
An AI coding tool whose usage QuotaPeek can inspect, currently Codex or Claude Code.
_Avoid_: Service, account

**Usage source**:
Provider-owned local data from which QuotaPeek obtains trustworthy usage
information, including records and official status-line quota fields.
_Avoid_: Account API, telemetry feed

**Usage snapshot**:
QuotaPeek's latest trustworthy interpretation of one provider's usage source,
including its usage windows, health, and any diagnostic context.
_Avoid_: Account balance, all-time usage

**Usage window**:
A provider-defined or observation-defined period represented in a usage snapshot.
_Avoid_: Session, billing cycle

**Used percentage**:
The portion of a provider-reported quota window that has been consumed.
It is shown only when the usage source supports that value.
_Avoid_: Token percentage, estimated quota

**Reset time**:
The provider-reported time when a quota window is expected to renew.
_Avoid_: Forecast, refresh time

**Reset forecast**:
An explicitly unofficial external estimate of the chance that Codex quotas will
reset within the next 48 hours.
_Avoid_: Reset time, guaranteed reset

**Provider health**:
QuotaPeek's assessment of whether a usage source is loading, ready, inactive,
limited, or needs attention.
_Avoid_: Online status, account status

**Visible provider**:
A provider the user has chosen to include in the popover and eligible menu-bar
summary modes. At least one provider is always visible.
_Avoid_: Enabled account

**Menu-bar summary**:
The compact provider logo and trustworthy usage value shown in the macOS menu bar.
_Avoid_: Dashboard, status badge

**Release pull request**:
The cumulative Release Please pull request that proposes the next version and
changelog. Merging it is the deliberate act that publishes a release.
_Avoid_: Feature pull request, automatic release
