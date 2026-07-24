import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("Codex usage parser")
struct CodexUsageParserTests {
    @Test("Parses token counts and rolling limits")
    func parsesTokenCountAndRollingLimits() throws {
        let line = """
        {
          "timestamp": "2026-07-16T07:30:00.000Z",
          "type": "event_msg",
          "payload": {
            "type": "token_count",
            "info": {
              "total_token_usage": {
                "input_tokens": 1200,
                "cached_input_tokens": 400,
                "output_tokens": 300,
                "reasoning_output_tokens": 100,
                "total_tokens": 1600
              },
              "model_context_window": 258400
            },
            "rate_limits": {
              "limit_name": "codex",
              "plan_type": "plus",
              "primary": {
                "used_percent": 42.5,
                "window_minutes": 300,
                "resets_at": 1784196000
              },
              "secondary": {
                "used_percent": 18,
                "window_minutes": 10080,
                "resets_at": 1784714400
              }
            }
          }
        }
        """

        let snapshot = try #require(CodexUsageParser.parse(line: line))

        #expect(snapshot.provider == .codex)
        #expect(snapshot.tokens.input == 1_200)
        #expect(snapshot.tokens.cachedInput == 400)
        #expect(snapshot.tokens.output == 300)
        #expect(snapshot.tokens.total == 1_600)
        #expect(snapshot.contextWindow == 258_400)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.windows[0].label == "5 hours")
        #expect(snapshot.windows[0].usedPercent == 42.5)
        #expect(snapshot.windows[1].label == "7 days")
        #expect(snapshot.windows[1].remainingPercent == 82)
    }

    @Test("Ignores unrelated events")
    func ignoresUnrelatedCodexEvents() {
        let line = #"{"timestamp":"2026-07-16T07:30:00Z","type":"event_msg","payload":{"type":"task_started"}}"#

        #expect(CodexUsageParser.parse(line: line) == nil)
    }

    @Test("Ignores empty token events so older usable records remain discoverable")
    func ignoresTokenEventsWithoutUsageOrLimits() {
        let line = #"{"timestamp":"2026-07-24T11:30:00Z","payload":{"type":"token_count","info":null,"rate_limits":null}}"#

        #expect(CodexUsageParser.parse(line: line) == nil)
    }

    @Test("Reader chooses newest event rather than newest file modification")
    func readerChoosesNewestEventTimestamp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let sessions = root
            .appendingPathComponent(".codex")
            .appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let staleFile = sessions.appendingPathComponent("stale.jsonl")
        let freshFile = sessions.appendingPathComponent("fresh.jsonl")
        try codexLine(timestamp: "2026-07-16T07:00:00Z", usedPercent: 80)
            .write(to: staleFile, atomically: true, encoding: .utf8)
        try codexLine(timestamp: "2026-07-16T08:00:00Z", usedPercent: 25)
            .write(to: freshFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: try #require(ISO8601DateFormatter().date(from: "2026-07-16T09:00:00Z"))],
            ofItemAtPath: staleFile.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: try #require(ISO8601DateFormatter().date(from: "2026-07-16T08:30:00Z"))],
            ofItemAtPath: freshFile.path
        )
        #expect(CodexUsageParser.parse(line: try String(contentsOf: staleFile))?.windows.first?.usedPercent == 80)
        #expect(CodexUsageParser.parse(line: try String(contentsOf: freshFile))?.windows.first?.usedPercent == 25)
        let snapshot = CodexUsageReader(homeDirectory: root, fileManager: .default).load()

        #expect(snapshot.isAvailable)
        #expect(snapshot.windows.first?.usedPercent == 25)
    }

    @Test("Reader shows session tokens when quota limits are unavailable")
    func readerShowsSessionTokensWithoutQuotaLimits() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let sessions = root
            .appendingPathComponent(".codex")
            .appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let line = """
        {"timestamp":"2026-07-24T11:27:25.453Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":20,"total_tokens":120},"model_context_window":258400},"rate_limits":{}}}
        """
        try line.write(
            to: sessions.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = CodexUsageReader(homeDirectory: root).load()

        #expect(snapshot.isAvailable)
        #expect(snapshot.health == .limited)
        #expect(snapshot.issue?.kind == .quotaLimitsUnavailable)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows.first?.label == "Current session")
        #expect(snapshot.windows.first?.tokens == 120)
        #expect(snapshot.diagnostics?.readableRecords == 1)
    }

    @Test("Reader explains when the Codex data folder is missing")
    func readerExplainsMissingDataFolder() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let snapshot = CodexUsageReader(homeDirectory: root).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.issue?.kind == .dataFolderNotFound)
        #expect(snapshot.diagnostics?.dataPath.contains("~/.codex") == true)
    }

    private func codexLine(timestamp: String, usedPercent: Double) -> String {
        #"{"timestamp":"\#(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100}},"rate_limits":{"primary":{"used_percent":\#(usedPercent),"window_minutes":300,"resets_at":1784196000}}}}"#
    }
}
