import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("Claude usage parser")
struct ClaudeUsageParserTests {
    @Test("Aggregates unique assistant messages within time windows")
    func aggregatesUniqueAssistantMessagesWithinTimeWindows() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-16T08:00:00Z"))
        let lines = [
            claudeLine(id: "recent", timestamp: "2026-07-16T07:00:00Z", input: 100, output: 20, cached: 30),
            claudeLine(id: "recent", timestamp: "2026-07-16T07:00:01Z", input: 100, output: 20, cached: 30),
            claudeLine(id: "today", timestamp: "2026-07-16T01:00:00Z", input: 200, output: 40, cached: 50),
            claudeLine(id: "old", timestamp: "2026-07-15T20:00:00Z", input: 900, output: 90, cached: 0)
        ]

        let snapshot = ClaudeUsageParser.aggregate(
            lines: lines,
            now: now,
            calendar: utcCalendar
        )

        #expect(snapshot.provider == .claude)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].label == "5 hours")
        #expect(snapshot.windows[0].tokens == 150)
        #expect(snapshot.windows[1].label == "Today")
        #expect(snapshot.windows[1].tokens == 440)
        #expect(snapshot.tokens.total == 440)
    }

    @Test("Returns unavailable when no usage exists")
    func returnsUnavailableSnapshotWhenNoUsageExists() {
        let snapshot = ClaudeUsageParser.aggregate(lines: [], now: Date())

        #expect(!snapshot.isAvailable)
        #expect(snapshot.statusMessage == "No Claude Code usage found")
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func claudeLine(
        id: String,
        timestamp: String,
        input: Int,
        output: Int,
        cached: Int
    ) -> String {
        """
        {
          "timestamp": "\(timestamp)",
          "type": "assistant",
          "message": {
            "id": "\(id)",
            "role": "assistant",
            "model": "claude-sonnet",
            "usage": {
              "input_tokens": \(input),
              "output_tokens": \(output),
              "cache_read_input_tokens": \(cached)
            }
          }
        }
        """
    }
}
