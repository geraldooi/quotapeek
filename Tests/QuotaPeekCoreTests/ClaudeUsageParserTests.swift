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

    @Test("Returns inactive when no usage exists")
    func returnsInactiveSnapshotWhenNoUsageExists() {
        let snapshot = ClaudeUsageParser.aggregate(lines: [], now: Date())

        #expect(!snapshot.isAvailable)
        #expect(snapshot.health == .inactive)
        #expect(!snapshot.needsAttention)
        #expect(snapshot.issue?.kind == .noRecentActivity)
        #expect(snapshot.statusMessage == "No Claude Code usage found")
    }

    @Test("Keeps unrecognized Claude Code records as needing attention")
    func keepsUnrecognizedRecordsAsNeedingAttention() {
        let snapshot = ClaudeUsageParser.aggregate(lines: ["{}"], now: Date())

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.needsAttention)
        #expect(snapshot.issue?.kind == .unsupportedFormat)
    }

    @Test("Returns no recent activity when readable records are outside display windows")
    func returnsNoRecentActivityForOldRecords() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z"))
        let lines = [
            claudeLine(
                id: "old",
                timestamp: "2026-07-22T11:00:00.000Z",
                input: 100,
                output: 20,
                cached: 30
            )
        ]

        let snapshot = ClaudeUsageParser.aggregate(
            lines: lines,
            now: now,
            calendar: utcCalendar
        )

        #expect(snapshot.health == .inactive)
        #expect(!snapshot.needsAttention)
        #expect(snapshot.issue?.kind == .noRecentActivity)
        #expect(snapshot.updatedAt == ISO8601DateFormatter().date(from: "2026-07-22T11:00:00Z"))
    }

    @Test("Accepts fractional-second timestamps written by Claude Code")
    func acceptsFractionalSecondTimestamps() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z"))
        let lines = [
            claudeLine(
                id: "fractional",
                timestamp: "2026-07-24T11:27:25.453Z",
                input: 100,
                output: 20,
                cached: 30
            )
        ]

        let snapshot = ClaudeUsageParser.aggregate(
            lines: lines,
            now: now,
            calendar: utcCalendar
        )

        #expect(snapshot.isAvailable)
        #expect(snapshot.health == .ready)
        #expect(snapshot.windows.first?.tokens == 150)
    }

    @Test("Reader explains when the Claude Code data folder is missing")
    func readerExplainsMissingDataFolder() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let snapshot = ClaudeUsageReader(homeDirectory: root).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.issue?.kind == .dataFolderNotFound)
        #expect(snapshot.diagnostics?.dataPath == "~/.claude/projects")
    }

    @Test("Reader treats an empty Claude Code data folder as inactive")
    func readerTreatsEmptyDataFolderAsInactive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let projects = root
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeUsageReader(homeDirectory: root).load()

        #expect(snapshot.health == .inactive)
        #expect(!snapshot.needsAttention)
        #expect(snapshot.issue?.kind == .noRecentActivity)
    }

    @Test("Reader treats stale Claude Code project files as inactive")
    func readerTreatsStaleProjectFilesAsInactive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let projects = root
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = projects.appendingPathComponent("old.jsonl")
        try "{}".write(to: file, atomically: true, encoding: .utf8)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-07-24T12:00:00Z"))
        let oldDate = try #require(ISO8601DateFormatter().date(from: "2026-07-20T12:00:00Z"))
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)

        let snapshot = ClaudeUsageReader(homeDirectory: root).load(now: now)

        #expect(snapshot.health == .inactive)
        #expect(!snapshot.needsAttention)
        #expect(snapshot.issue?.kind == .noRecentActivity)
    }

    @Test("Reader keeps permission failures as needing attention")
    func readerKeepsPermissionFailuresAsNeedingAttention() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let projects = root
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = ClaudeUsageReader(
            homeDirectory: root,
            fileManager: PermissionDeniedFileManager()
        ).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.needsAttention)
        #expect(snapshot.issue?.kind == .permissionDenied)
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

private final class PermissionDeniedFileManager: FileManager, @unchecked Sendable {
    override func subpathsOfDirectory(atPath path: String) throws -> [String] {
        throw CocoaError(.fileReadNoPermission)
    }
}
