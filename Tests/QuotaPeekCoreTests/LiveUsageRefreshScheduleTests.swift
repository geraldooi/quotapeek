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
}
