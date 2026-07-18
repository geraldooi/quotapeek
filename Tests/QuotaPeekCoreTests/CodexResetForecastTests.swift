import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("Codex reset forecast")
struct CodexResetForecastTests {
    @Test("Parses the public forecast response")
    func parsesForecastResponse() throws {
        let data = try #require(
            """
            {
              "fetchedAt": "2026-07-18T05:32:04Z",
              "nextRefreshAt": "2026-07-18T06:02:04Z",
              "forecast": { "score": 53 }
            }
            """.data(using: .utf8)
        )

        let forecast = try #require(CodexResetForecastParser.parse(data: data))

        #expect(forecast.score == 53)
        #expect(forecast.fetchedAt == ISO8601DateFormatter().date(from: "2026-07-18T05:32:04Z"))
        #expect(forecast.nextRefreshAt == ISO8601DateFormatter().date(from: "2026-07-18T06:02:04Z"))
    }

    @Test("Parses public forecast timestamps with fractional seconds")
    func parsesFractionalSecondTimestamps() throws {
        let data = try #require(
            """
            {
              "fetchedAt": "2026-07-18T07:32:08.628Z",
              "nextRefreshAt": "2026-07-18T08:02:08.628Z",
              "forecast": { "score": 88 }
            }
            """.data(using: .utf8)
        )

        let forecast = try #require(CodexResetForecastParser.parse(data: data))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        #expect(forecast.score == 88)
        #expect(forecast.fetchedAt == formatter.date(from: "2026-07-18T07:32:08.628Z"))
        #expect(forecast.nextRefreshAt == formatter.date(from: "2026-07-18T08:02:08.628Z"))
    }

    @Test("Rejects scores outside the probability range")
    func rejectsInvalidScore() throws {
        let data = try #require(
            """
            {
              "fetchedAt": "2026-07-18T05:32:04Z",
              "forecast": { "score": 101 }
            }
            """.data(using: .utf8)
        )

        #expect(CodexResetForecastParser.parse(data: data) == nil)
    }

    @Test("Rejects responses without a forecast")
    func rejectsMissingForecast() throws {
        let data = try #require(
            #"{"fetchedAt":"2026-07-18T05:32:04Z"}"#.data(using: .utf8)
        )

        #expect(CodexResetForecastParser.parse(data: data) == nil)
    }

    @Test("Accepts only recent source data")
    func checksFreshness() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-18T07:00:00Z"))
        let recent = CodexResetForecast(score: 53, fetchedAt: now.addingTimeInterval(-30 * 60))
        let stale = CodexResetForecast(score: 53, fetchedAt: now.addingTimeInterval(-3 * 60 * 60))
        let future = CodexResetForecast(score: 53, fetchedAt: now.addingTimeInterval(10 * 60))

        #expect(recent.isFresh(at: now))
        #expect(!stale.isFresh(at: now))
        #expect(!future.isFresh(at: now))
    }
}
