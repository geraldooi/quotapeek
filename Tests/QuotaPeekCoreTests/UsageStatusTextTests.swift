import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("Usage status text")
struct UsageStatusTextTests {
    @Test("Identifies a fresh Claude account reading as live in sight and speech")
    func labelsLiveClaudeReading() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot(
            provider: .claude,
            source: .live,
            windows: [UsageWindow(kind: .weekly, label: "Weekly", usedPercent: 25)],
            updatedAt: now
        )

        let text = snapshot.statusText(at: now)

        #expect(text.label == "Live now")
        #expect(text.accessibilityLabel == "Claude Code live quota: Live now")
        #expect(text.help.contains("live"))
    }

    @Test("Keeps local Claude capture wording for fallback data")
    func labelsLocalClaudeCapture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot(
            provider: .claude,
            source: .localCapture,
            health: .limited,
            windows: [UsageWindow(kind: .weekly, label: "Weekly", usedPercent: 25)],
            updatedAt: now
        )

        let text = snapshot.statusText(at: now)

        #expect(text.label == "Limited · Captured now")
        #expect(text.accessibilityLabel == "Claude Code quota capture: Limited · Captured now")
        #expect(text.help.contains("captured"))
    }

    @Test("Retains the live source as a reading ages")
    func labelsAgingLiveClaudeReading() {
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot(
            provider: .claude,
            source: .live,
            updatedAt: checkedAt
        )

        let text = snapshot.statusText(at: checkedAt.addingTimeInterval(2 * 60))

        #expect(text.label == "Live · 2m old")
        #expect(text.accessibilityLabel == "Claude Code live quota: Live · 2m old")
    }
}
