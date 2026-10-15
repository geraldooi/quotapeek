import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("Claude live usage")
struct ClaudeLiveUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Parses official five-hour and weekly usage windows")
    func parsesWindows() throws {
        let payload = Data(
            """
            {"five_hour":{"utilization":42.5,"resets_at":"2027-01-16T08:00:00.000Z"},"seven_day":{"utilization":68,"resets_at":"2027-01-20T08:00:00Z"}}
            """.utf8
        )
        let snapshot = try #require(ClaudeLiveUsageReader.parse(data: payload, now: now))
        #expect(snapshot.health == .ready)
        #expect(snapshot.source == .live)
        #expect(snapshot.windows.map(\.kind) == [.fiveHour, .weekly])
        #expect(snapshot.windows.map(\.usedPercent) == [42.5, 68])
        #expect(snapshot.updatedAt == now)
    }

    @Test("Keeps a valid window when the other is absent")
    func acceptsPartialResponse() throws {
        let payload = Data("{\"seven_day\":{\"utilization\":68,\"resets_at\":\"2027-01-20T08:00:00Z\"}}".utf8)
        let snapshot = try #require(ClaudeLiveUsageReader.parse(data: payload, now: now))
        #expect(snapshot.health == .limited)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.issue?.kind == .quotaLimitsUnavailable)
    }

    @Test("Rejects invalid percentages, dates, and empty responses")
    func rejectsInvalidData() {
        let invalid = Data("{\"five_hour\":{\"utilization\":101,\"resets_at\":\"2027-01-15T08:00:00Z\"}}".utf8)
        let expired = Data("{\"five_hour\":{\"utilization\":10,\"resets_at\":\"2020-01-15T08:00:00Z\"}}".utf8)
        #expect(ClaudeLiveUsageReader.parse(data: invalid, now: now) == nil)
        #expect(ClaudeLiveUsageReader.parse(data: expired, now: now) == nil)
        #expect(ClaudeLiveUsageReader.parse(data: Data("{}".utf8), now: now) == nil)
    }

    @Test("Treats an unavailable window as absent")
    func acceptsNullWindow() throws {
        let payload = Data("{\"five_hour\":null,\"seven_day\":{\"utilization\":68,\"resets_at\":\"2027-01-20T08:00:00Z\"}}".utf8)
        let snapshot = try #require(ClaudeLiveUsageReader.parse(data: payload, now: now))
        #expect(snapshot.health == .limited)
        #expect(snapshot.windows.map(\.kind) == [.weekly])
    }

    @Test("Accepts numeric reset timestamps")
    func acceptsNumericReset() throws {
        let payload = Data("{\"five_hour\":{\"utilization\":25,\"resets_at\":1800086400000}}".utf8)
        let snapshot = try #require(ClaudeLiveUsageReader.parse(data: payload, now: now))
        #expect(snapshot.windows.first?.usedPercent == 25)
        #expect(snapshot.windows.first?.resetAt != nil)
    }

    @Test("Accepts zero and one percent as numbers, not booleans")
    func acceptsLowPercentages() throws {
        let payload = Data("{\"five_hour\":{\"utilization\":0},\"seven_day\":{\"utilization\":1}}".utf8)
        let snapshot = try #require(ClaudeLiveUsageReader.parse(data: payload, now: now))
        #expect(snapshot.windows.map(\.usedPercent) == [0, 1])
    }

    @Test("Rejects a malformed utilization when it is present")
    func rejectsMalformedPresentWindow() {
        let payload = Data("{\"five_hour\":{\"utilization\":101},\"seven_day\":{\"utilization\":68}}".utf8)
        #expect(ClaudeLiveUsageReader.parse(data: payload, now: now) == nil)
    }

    @Test("Scopes custom Claude Code profiles to their hashed Keychain service")
    func scopesCustomProfileKeychainService() {
        let services = ClaudeLiveUsageReader.keychainServices(
            configDirectory: URL(fileURLWithPath: "/tmp/claude-profile"),
            environment: [:]
        )
        #expect(services.first?.hasPrefix("Claude Code-credentials-") == true)
        #expect(!services.contains("Claude Code-credentials"))
        #expect(!services.contains("Claude Code"))
    }

    @Test("Uses only the active base Keychain service for unset or empty selectors")
    func selectsDefaultCredentialStore() {
        #expect(ClaudeLiveUsageReader.keychainServices(configDirectory: nil, environment: [:])
            == ["Claude Code-credentials"])
        let pinnedDefault = ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "", "CLAUDE_CONFIG_DIR": "/tmp/other-profile"]
        #expect(ClaudeLiveUsageReader.keychainServices(configDirectory: nil, environment: pinnedDefault)
            == ["Claude Code-credentials"])
    }

    @Test("Hashes nonempty secure-storage selectors without expanding paths")
    func preservesVerbatimCredentialSelector() {
        let environment = ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "~/.claude", "CLAUDE_CONFIG_DIR": "/tmp/other-profile"]
        #expect(ClaudeLiveUsageReader.keychainServices(configDirectory: nil, environment: environment)
            == ["Claude Code-credentials-37e4f761"])
        let explicitDefault = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        #expect(ClaudeLiveUsageReader.keychainServices(configDirectory: explicitDefault, environment: [:])
            != ["Claude Code-credentials"])
    }

    @Test("Credential files follow the secure-storage selector and empty-string pin")
    func selectsCredentialFileFromSameStore() {
        let environment = ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "/tmp/selected-profile", "CLAUDE_CONFIG_DIR": "/tmp/other-profile"]
        #expect(ClaudeLiveUsageReader.credentialsFileURL(configDirectory: nil, environment: environment).path
            == "/tmp/selected-profile/.credentials.json")
        let pinnedDefault = ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "", "CLAUDE_CONFIG_DIR": "/tmp/other-profile"]
        let defaultFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        #expect(ClaudeLiveUsageReader.credentialsFileURL(configDirectory: nil, environment: pinnedDefault)
            == defaultFile)
    }

    @Test("Uses authorization guidance only for Claude authentication failures")
    func classifiesHTTPFailures() {
        for statusCode in [401, 403] {
            let issue = ClaudeLiveUsageReader.issue(forHTTPStatus: statusCode)
            #expect(issue.title == "Claude live quota authorization expired")
            #expect(issue.recoverySuggestion.contains("authorization"))
        }
        for statusCode in [429, 500, 503, 400] {
            let issue = ClaudeLiveUsageReader.issue(forHTTPStatus: statusCode)
            #expect(issue.title != "Claude live quota authorization expired")
            #expect(!issue.recoverySuggestion.contains("authorization"))
        }
        #expect(ClaudeLiveUsageReader.issue(forHTTPStatus: 429).recoverySuggestion.contains("Wait"))
        #expect(ClaudeLiveUsageReader.issue(forHTTPStatus: 503).recoverySuggestion.contains("later"))
    }

    @Test("Parses Retry-After delta seconds without truncating long backoffs")
    func parsesRetryAfterSeconds() {
        let retryAt = ClaudeLiveUsageReader.retryAfterDate(from: "900", now: now)
        #expect(retryAt == now.addingTimeInterval(900))
        #expect(ClaudeLiveUsageReader.retryAfterDate(from: "-1", now: now) == nil)
        #expect(ClaudeLiveUsageReader.retryAfterDate(from: "not-a-date", now: now) == nil)
    }

    @Test("Parses future HTTP-date Retry-After values")
    func parsesRetryAfterHTTPDate() {
        let retryAt = ClaudeLiveUsageReader.retryAfterDate(
            from: "Fri, 16 Jan 2027 08:00:00 GMT",
            now: now
        )
        #expect(retryAt == Date(timeIntervalSince1970: 1_800_086_400))
        #expect(ClaudeLiveUsageReader.retryAfterDate(
            from: "Fri, 16 Jan 2020 08:00:00 GMT",
            now: now
        ) == nil)
    }
}
