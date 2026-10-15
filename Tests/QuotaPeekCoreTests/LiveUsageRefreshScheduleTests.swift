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

    @Test("Manual refreshes honor provider retry deadlines without losing normal refresh")
    func respectsProviderRetryAfter() {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let normalDeadline = startedAt.addingTimeInterval(210)
        let retryAfter = startedAt.addingTimeInterval(900)

        #expect(LiveUsageRefreshSchedule.shouldRead(
            at: startedAt,
            deadline: normalDeadline,
            manuallyRequested: true
        ))
        #expect(!LiveUsageRefreshSchedule.shouldRead(
            at: startedAt.addingTimeInterval(300),
            deadline: normalDeadline,
            manuallyRequested: true,
            retryAfter: retryAfter
        ))
        #expect(!LiveUsageRefreshSchedule.shouldRead(
            at: startedAt.addingTimeInterval(300),
            deadline: normalDeadline,
            retryAfter: retryAfter
        ))
        #expect(LiveUsageRefreshSchedule.shouldRead(
            at: retryAfter,
            deadline: normalDeadline,
            retryAfter: retryAfter
        ))
    }
}
