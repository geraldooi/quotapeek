---
status: accepted
---

# Accumulate automated releases

Changes reach the production-ready `main` branch through focused, conventionally
titled pull requests, while Release Please accumulates releasable changes in one
separate release pull request. Merging an ordinary pull request does not publish
a release; merging the release pull request is the deliberate release decision
and lets GitHub Actions create the immutable tag and archive and update the
Homebrew tap. Release Please owns `VERSION` and `CHANGELOG.md`, and the manual
release workflow is reserved for recovering publication of an existing version.
