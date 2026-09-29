import Foundation
import Testing
@testable import QuotaPeekCore

@Suite("Codex live usage")
struct CodexLiveUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Missing local executable does not invent quota values")
    func missingExecutableIsActionable() {
        let snapshot = CodexLiveUsageReader(
            executableURL: URL(fileURLWithPath: "/definitely/not/codex"),
            now: { now }
        ).load()

        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.updatedAt == now)
        #expect(snapshot.issue?.kind == .readError)
    }

    @Test("Uses the codex bucket and maps windows by duration")
    func parsesCodexBucket() throws {
        let data = try #require("""
        {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1800000001}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":1,"windowDurationMins":300}},"codex":{"primary":{"usedPercent":37.5,"windowDurationMins":10080,"resetsAt":1800000100},"secondary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1800000200}}}}}
        """.data(using: .utf8))

        let snapshot = CodexLiveUsageReader.parse(data: data, now: now)
        #expect(snapshot.health == .ready)
        #expect(snapshot.source == .live)
        #expect(snapshot.windows.map(\.kind) == [.weekly, .fiveHour])
        #expect(snapshot.windows.map(\.usedPercent) == [37.5, 12])
        #expect(snapshot.updatedAt == now)
    }

    @Test("Rejects invalid percentages and reports unavailable limits")
    func rejectsInvalidValues() throws {
        let data = try #require(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":101,"windowDurationMins":300,"resetsAt":0}}}}"#.data(using: .utf8))
        let snapshot = CodexLiveUsageReader.parse(data: data, now: now)
        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.issue?.kind == .quotaLimitsUnavailable)
    }

    @Test("Rejects non-finite or unsafe window durations")
    func rejectsUnsafeDuration() throws {
        let data = try #require(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":1e100,"resetsAt":1800000001}}}}"#.data(using: .utf8))
        let snapshot = CodexLiveUsageReader.parse(data: data, now: now)
        #expect(snapshot.health == .needsAttention)
        #expect(snapshot.windows.isEmpty)
    }

    @Test("Rejects boolean quota fields without discarding one percent")
    func distinguishesBooleanFromOne() throws {
        let valid = try #require(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":10080}}}}"#.data(using: .utf8))
        let invalid = try #require(#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":true,"windowDurationMins":10080}}}}"#.data(using: .utf8))
        #expect(CodexLiveUsageReader.parse(data: valid, now: now).windows.first?.usedPercent == 1)
        #expect(CodexLiveUsageReader.parse(data: invalid, now: now).windows.isEmpty)
    }

    @Test("Completes the app-server request sequence")
    func readsAppServer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotapeek-codex-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        let script = #"""
        #!/bin/sh
        read initialize
        printf '%s\n' '{"id":1,"result":{}}'
        read initialized
        read limits
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":31,"windowDurationMins":10080,"resetsAt":1800000100}}}}'
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let snapshot = CodexLiveUsageReader(executableURL: executable, now: { now }).load()

        #expect(snapshot.health == .ready)
        #expect(snapshot.windows.first?.kind == .weekly)
        #expect(snapshot.windows.first?.usedPercent == 31)
    }
}
