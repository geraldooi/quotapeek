import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("Claude quota")
struct ClaudeQuotaTests {
    @Test("Parses official five-hour and seven-day status-line limits")
    func parsesOfficialRateLimits() throws {
        let payload = Data(
            """
            {
              "rate_limits": {
                "five_hour": {
                  "used_percentage": 42.5,
                  "resets_at": 1786543200
                },
                "seven_day": {
                  "used_percentage": 68,
                  "resets_at": 1787025600
                }
              }
            }
            """.utf8
        )

        let capture = try #require(
            ClaudeQuotaCaptureParser.parse(
                data: payload,
                capturedAt: Date(timeIntervalSince1970: 1_786_500_000)
            )
        )

        #expect(capture.capturedAt == Date(timeIntervalSince1970: 1_786_500_000))
        #expect(capture.fiveHour?.usedPercent == 42.5)
        #expect(capture.fiveHour?.resetAt == Date(timeIntervalSince1970: 1_786_543_200))
        #expect(capture.sevenDay?.usedPercent == 68)
        #expect(capture.sevenDay?.resetAt == Date(timeIntervalSince1970: 1_787_025_600))
    }

    @Test("Accepts independently available Claude quota windows")
    func acceptsPartialRateLimits() throws {
        let payload = Data(
            """
            {"rate_limits":{"seven_day":{"used_percentage":68,"resets_at":1787025600}}}
            """.utf8
        )

        let capture = try #require(ClaudeQuotaCaptureParser.parse(data: payload))

        #expect(capture.fiveHour == nil)
        #expect(capture.sevenDay?.usedPercent == 68)
    }

    @Test("Rejects booleans in Claude quota numeric fields")
    func rejectsBooleanNumericFields() {
        let booleanPercentage = Data(
            """
            {"rate_limits":{"five_hour":{"used_percentage":true,"resets_at":1786543200}}}
            """.utf8
        )
        let booleanReset = Data(
            """
            {"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":true}}}
            """.utf8
        )

        #expect(ClaudeQuotaCaptureParser.parse(data: booleanPercentage) == nil)
        #expect(ClaudeQuotaCaptureParser.parse(data: booleanReset) == nil)
    }

    @Test("Distinguishes absent limits from malformed limits")
    func distinguishesUnavailableAndInvalidLimits() {
        let unavailable = Data("{\"model\":{\"id\":\"claude\"}}".utf8)
        let invalid = Data(
            """
            {"rate_limits":{"five_hour":{"used_percentage":true,"resets_at":1786543200}}}
            """.utf8
        )

        #expect(ClaudeQuotaCaptureParser.result(data: unavailable) == .unavailable)
        #expect(ClaudeQuotaCaptureParser.result(data: invalid) == .invalid)
    }

    @Test("Reads cached Claude quota as percentage windows")
    func readsCachedQuotaWindows() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = root.appendingPathComponent("claude-rate-limits.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let capture = ClaudeQuotaCapture(
            capturedAt: Date(timeIntervalSince1970: 1_786_500_000),
            fiveHour: ClaudeQuotaWindow(
                usedPercent: 42.5,
                resetAt: Date(timeIntervalSince1970: 1_786_543_200)
            ),
            sevenDay: ClaudeQuotaWindow(
                usedPercent: 68,
                resetAt: Date(timeIntervalSince1970: 1_787_025_600)
            )
        )
        try ClaudeQuotaStore(cacheURL: cacheURL).save(capture)

        let snapshot = ClaudeQuotaReader(
            cacheURL: cacheURL,
            integrationEnabled: true
        ).load(now: Date(timeIntervalSince1970: 1_786_500_100))

        #expect(snapshot.health == .ready)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].label == "5 hours")
        #expect(snapshot.windows[0].usedPercent == 42.5)
        #expect(snapshot.windows[0].resetAt == Date(timeIntervalSince1970: 1_786_543_200))
        #expect(snapshot.windows[1].label == "Weekly")
        #expect(snapshot.windows[1].usedPercent == 68)
        #expect(snapshot.windows[1].resetAt == Date(timeIntervalSince1970: 1_787_025_600))
    }

    @Test("Explains how to enable Claude quota capture")
    func explainsDisabledIntegration() {
        let snapshot = ClaudeQuotaReader(
            cacheURL: URL(fileURLWithPath: "/unused"),
            integrationEnabled: false
        ).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.issue?.kind == .quotaLimitsUnavailable)
        #expect(snapshot.statusMessage == "Claude quota bars are not enabled")
        #expect(snapshot.windows.isEmpty)
    }

    @Test("Reports a malformed Claude quota cache")
    func reportsMalformedCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = root.appendingPathComponent("claude-rate-limits.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not valid JSON".utf8).write(to: cacheURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeQuotaReader(
            cacheURL: cacheURL,
            integrationEnabled: true
        ).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.issue?.kind == .unsupportedFormat)
        #expect(snapshot.statusMessage == "Claude quota cache is invalid")
    }

    @Test("Reports semantically invalid Claude quota cache values")
    func reportsInvalidCacheValues() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = root.appendingPathComponent("claude-rate-limits.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(
            """
            {"capturedAt":1786500000,"fiveHour":{"resetAt":1893456000,"usedPercent":250}}
            """.utf8
        ).write(to: cacheURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeQuotaReader(
            cacheURL: cacheURL,
            integrationEnabled: true
        ).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.issue?.kind == .unsupportedFormat)
        #expect(snapshot.statusMessage == "Claude quota cache is invalid")
    }

    @Test("Reports an unreadable Claude quota cache")
    func reportsUnreadableCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = root.appendingPathComponent("claude-rate-limits.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: cacheURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: cacheURL.path
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeQuotaReader(
            cacheURL: cacheURL,
            integrationEnabled: true
        ).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.issue?.kind == .permissionDenied)
        #expect(snapshot.statusMessage == "Claude quota cache could not be accessed")
    }

    @Test("Reports a Claude quota cache write failure")
    func reportsCacheWriteFailure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = root.appendingPathComponent("claude-rate-limits.json")
        let statusURL = root.appendingPathComponent("claude-capture-status")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let statusStore = ClaudeQuotaCaptureStatusStore(statusURL: statusURL)
        try statusStore.ensureExists()
        try statusStore.record(.writeFailure)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeQuotaReader(
            cacheURL: cacheURL,
            captureStatusURL: statusURL,
            integrationEnabled: true
        ).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.issue?.kind == .readError)
        #expect(snapshot.statusMessage == "Claude quota data could not be saved")
    }

    @Test("Reports a Claude quota cache permission failure")
    func reportsCachePermissionFailure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = root.appendingPathComponent("claude-rate-limits.json")
        let statusURL = root.appendingPathComponent("claude-capture-status")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let statusStore = ClaudeQuotaCaptureStatusStore(statusURL: statusURL)
        try statusStore.ensureExists()
        try statusStore.record(.permissionFailure)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeQuotaReader(
            cacheURL: cacheURL,
            captureStatusURL: statusURL,
            integrationEnabled: true
        ).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.issue?.kind == .permissionDenied)
        #expect(snapshot.statusMessage == "Claude quota data could not be saved")
    }

    @Test("Reports malformed Claude status-line quota data")
    func reportsInvalidCapture() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cacheURL = root.appendingPathComponent("claude-rate-limits.json")
        let statusURL = root.appendingPathComponent("claude-capture-status")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let statusStore = ClaudeQuotaCaptureStatusStore(statusURL: statusURL)
        try statusStore.ensureExists()
        try statusStore.record(.invalidPayload)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeQuotaReader(
            cacheURL: cacheURL,
            captureStatusURL: statusURL,
            integrationEnabled: true
        ).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.issue?.kind == .unsupportedFormat)
        #expect(snapshot.statusMessage == "Claude quota data is invalid")
    }
}
