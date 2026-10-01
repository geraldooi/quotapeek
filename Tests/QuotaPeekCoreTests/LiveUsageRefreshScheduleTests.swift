import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("Live usage refresh schedule")
struct LiveUsageRefreshScheduleTests {
    @Test("Schedules another live read before a five-minute snapshot becomes stale")
    func refreshesBeforeStale() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let nextRead = LiveUsageRefreshSchedule.nextRead(after: startedAt)

        #expect(nextRead == startedAt.addingTimeInterval(210))
        #expect(nextRead < startedAt.addingTimeInterval(5 * 60))
    }

    @Test("A provider hidden during another provider read retains its own deadline")
    func hiddenProviderKeepsDeadline() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let codexDeadline = LiveUsageRefreshSchedule.nextRead(after: startedAt.addingTimeInterval(240))
        let claudeDeadline = LiveUsageRefreshSchedule.nextRead(after: startedAt)
        let reenabledAt = startedAt.addingTimeInterval(250)

        #expect(!LiveUsageRefreshSchedule.shouldRead(at: reenabledAt, deadline: codexDeadline))
        #expect(LiveUsageRefreshSchedule.shouldRead(at: reenabledAt, deadline: claudeDeadline))
    }
}
