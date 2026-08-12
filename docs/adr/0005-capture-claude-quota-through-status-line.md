---
status: accepted
---

# Capture Claude quota through its status line

QuotaPeek obtains Claude's authoritative five-hour and seven-day percentages
through an opt-in bridge configured as Claude Code's status-line command. The
bridge preserves and forwards any existing status line and caches only quota
percentages, reset times, and capture time. This small, reversible settings
change avoids reading Claude credentials or depending on Anthropic's
undocumented authenticated usage endpoint; quota data becomes available only
after Claude Code receives an API response.
