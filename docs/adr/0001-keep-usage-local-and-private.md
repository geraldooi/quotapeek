---
status: accepted
---

# Keep usage collection local and private

QuotaPeek obtains provider usage from local Codex records and Claude Code's
official status-line quota fields and does not read prompt or response text,
access credentials, or send analytics.
Public reset-forecast and release-update checks may use unauthenticated HTTPS
GET requests only when they send no local usage data, content, credentials, or
user identifiers, and each integration must be disclosed in `README.md`. This
preserves a read-only privacy boundary at the cost of depending on provider file
formats and handling missing, stale, partially readable, or inaccessible data.
