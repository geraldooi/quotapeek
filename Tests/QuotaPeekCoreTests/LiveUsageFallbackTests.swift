import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("Live usage fallback")
struct LiveUsageFallbackTests {
    @Test("Prefers current account limits over a different local value")
    func prefersLiveLimits() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let local = snapshot(provider: .codex, percent: 42, at: now.addingTimeInterval(-60))
        let live = snapshot(provider: .codex, percent: 61, at: now)

        let selected = LiveUsageFallback.select(live: live, local: local, now: now)

        #expect(selected.windows.first?.usedPercent == 61)
        #expect(selected.health == .ready)
    }

    @Test("Marks a local capture limited when the live read fails")
    func marksFallbackLimited() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let local = snapshot(provider: .claude, percent: 42, at: now.addingTimeInterval(-90))
        let live = UsageSnapshot.unavailable(.claude, message: "Live Claude limits unavailable")

        let selected = LiveUsageFallback.select(live: live, local: local, now: now)

        #expect(selected.health == .limited)
        #expect(selected.windows.first?.usedPercent == 42)
        #expect(selected.updatedAt == local.updatedAt)
        #expect(selected.issue?.title == "Live Claude Code limits unavailable")
    }

    @Test("Never falls back to an expired local quota window")
    func excludesExpiredLocalWindow() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let local = UsageSnapshot(
            provider: .codex,
            windows: [UsageWindow(
                kind: .weekly,
                label: "7 days",
                usedPercent: 42,
                resetAt: now.addingTimeInterval(-1)
            )],
            updatedAt: now.addingTimeInterval(-90)
        )
        let live = UsageSnapshot.unavailable(.codex, message: "Live Codex limits unavailable")

        let selected = LiveUsageFallback.select(live: live, local: local, now: now)

        #expect(selected == live)
    }

    @Test("Does not treat a local window without a reset time as current")
    func excludesUnverifiableLocalWindow() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let local = UsageSnapshot(
            provider: .claude,
            windows: [UsageWindow(kind: .weekly, label: "Weekly", usedPercent: 42)],
            updatedAt: now.addingTimeInterval(-90)
        )
        let live = UsageSnapshot.unavailable(.claude, message: "Live Claude limits unavailable")

        #expect(LiveUsageFallback.select(live: live, local: local, now: now) == live)
    }

    private func snapshot(provider: Provider, percent: Double, at date: Date) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            windows: [UsageWindow(
                kind: .weekly,
                label: "7 days",
                usedPercent: percent,
                resetAt: date.addingTimeInterval(3_600)
            )],
            updatedAt: date
        )
    }
}
