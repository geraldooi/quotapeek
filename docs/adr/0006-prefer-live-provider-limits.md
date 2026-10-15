---
status: accepted
---

# Prefer live provider limits over local captures

Local Codex records and Claude Code status-line captures may lag behind usage
from another device. QuotaPeek therefore prefers live five-hour and weekly
quota percentages when the provider exposes them. The popover and menu-bar
presentation remain unchanged.

For Codex, QuotaPeek uses the installed Codex CLI's read-only
`account/rateLimits/read` app-server method, leaving Codex authentication to
the CLI. For Claude Code, QuotaPeek reads the existing local OAuth credential
and sends a bearer token only to `https://api.anthropic.com/api/oauth/usage`
over HTTPS. It does not persist, log, display, or transmit the token to a
QuotaPeek or third-party server. This endpoint is not a stable public API, so
authentication and schema failures must be visible as limited or unavailable
states, never as zero usage.

Live reads are throttled. If a live read fails, QuotaPeek may show a still-valid
local capture, marked limited with its original capture time. Expired local
windows are not used as a fallback. Neither live path reads prompts or
responses, and neither sends local usage records to a provider.
