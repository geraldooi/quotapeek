---
status: accepted
---

# Keep usage collection local and private

QuotaPeek obtains provider usage from local records and, where available,
live provider limits. It does not read prompt or response text or send
analytics. For live Codex limits, QuotaPeek asks the local Codex app-server;
it does not read Codex credentials. For live Claude limits, QuotaPeek may read
Claude Code's existing local credential and send it only to Anthropic's usage
endpoint. It must not copy or store that credential on any other server.
Public reset-forecast and release-update checks may use unauthenticated HTTPS
GET requests only when they send no local usage data, content, credentials, or
user identifiers, and each integration must be disclosed in `README.md`. This
preserves a read-only privacy boundary. Local captures remain a clearly marked
fallback when live limits are unavailable.
