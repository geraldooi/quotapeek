---
status: accepted
---

# Capture Claude quota through its status line

QuotaPeek can obtain Claude's five-hour and seven-day percentages through an
opt-in bridge configured as Claude Code's status-line command. The
bridge preserves and forwards any existing status line and caches only quota
percentages, reset times, and capture time. The bridge remains a local fallback
when live limits cannot be read. Live Claude limits and the approved credential
boundary are described in ADR 0006.
