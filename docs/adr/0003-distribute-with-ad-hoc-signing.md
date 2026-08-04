---
status: accepted
---

# Distribute with ad-hoc signing

QuotaPeek ships as an Apple Silicon and Intel universal app with an ad-hoc code
signature through GitHub Releases and a Homebrew cask. The project deliberately
does not require the paid Apple Developer Program, Developer ID signing, or
notarization. We accept that Gatekeeper may require users to approve the first
launch in System Settings; release notes and installation documentation must
state that limitation clearly rather than implying a notarized experience.
