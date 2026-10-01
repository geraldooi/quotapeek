import Foundation
import Darwin
import CoreFoundation

/// Reads the authenticated Codex quota snapshot through Codex's official
/// app-server protocol. The Codex executable owns authentication; QuotaPeek
/// never opens or parses Codex credentials.
public struct CodexLiveUsageReader {
    private let executableURL: URL?
    private let now: () -> Date

    public init(executableURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.executableURL = executableURL
        self.now = now
    }

    /// Synchronously asks `codex app-server` for the current rate limits.
    /// This is intended to be called from a detached/background task.
    public func load() -> UsageSnapshot {
        let timestamp = now()
        guard let executable = executableURL ?? Self.findExecutable() else {
            return failure(
                kind: .readError,
                title: "Codex app-server was not found",
                message: "QuotaPeek could not find the Codex command-line app-server.",
                recovery: "Install Codex or make its command available, then refresh.",
                at: timestamp
            )
        }

        guard let data = Self.run(executable: executable),
              let response = Self.response(from: data),
              let snapshot = Self.snapshot(from: response, now: timestamp)
        else {
            return failure(
                kind: .readError,
                title: "Codex quota could not be read",
                message: "QuotaPeek could not obtain a valid response from the Codex app-server.",
                recovery: "Open Codex once, then refresh QuotaPeek.",
                at: timestamp
            )
        }

        return snapshot
    }

    /// Parses an app-server response without launching a process. Kept public
    /// so callers and tests can validate protocol fixtures deterministically.
    public static func parse(data: Data, now: Date = Date()) -> UsageSnapshot {
        guard let response = response(from: data) else {
            return failure(
                kind: .unsupportedFormat,
                title: "Codex quota format is not supported",
                message: "Codex returned a response that QuotaPeek could not recognize.",
                recovery: "Update Codex, then refresh QuotaPeek.",
                at: now
            )
        }
        return snapshot(from: response, now: now) ?? failure(
            kind: .quotaLimitsUnavailable,
            title: "Codex quota is unavailable",
            message: "Codex did not provide usable rolling quota limits.",
            recovery: "Use Codex once, then refresh QuotaPeek.",
            at: now
        )
    }

    private static func findExecutable() -> URL? {
        var candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                String($0) + "/codex"
            })
        }
        let nvmRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(
            at: nvmRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: versions.map {
                $0.appendingPathComponent("bin/codex").path
            })
        }
        candidates.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/codex").path)
        return candidates.lazy.map(URL.init(fileURLWithPath:)).first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private static func run(executable: URL) -> Data? {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executable.deletingLastPathComponent().path
            + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }

        let collector = ResponseCollector(output: output)
        collector.start()
        func send(_ line: String) {
            input.fileHandleForWriting.write(Data((line + "\n").utf8))
        }

        send("{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"quotapeek\",\"title\":\"QuotaPeek\",\"version\":\"1\"},\"capabilities\":{\"experimentalApi\":true}}}")
        guard collector.wait(for: 1, timeout: 4), process.isRunning else {
            stop(process)
            return nil
        }
        send("{\"method\":\"initialized\",\"params\":{}}")
        send("{\"method\":\"account/rateLimits/read\",\"id\":2}")
        guard collector.wait(for: 2, timeout: 5) else {
            stop(process)
            return nil
        }

        let result = collector.data
        stop(process)
        return result
    }

    private static func stop(_ process: Process) {
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < deadline { usleep(10_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }

    private final class ResponseCollector: @unchecked Sendable {
        private let output: Pipe
        private let lock = NSLock()
        private var responseData = Data()
        private var pendingLine = Data()
        private let signals: [Int: DispatchSemaphore] = [
            1: DispatchSemaphore(value: 0),
            2: DispatchSemaphore(value: 0)
        ]

        init(output: Pipe) { self.output = output }

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return responseData
        }

        func start() {
            DispatchQueue.global(qos: .utility).async { [self] in
                let handle = output.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    lock.lock()
                    if responseData.count < 1_048_576 {
                        responseData.append(chunk.prefix(1_048_576 - responseData.count))
                    }
                    if pendingLine.count < 1_048_576 {
                        pendingLine.append(chunk.prefix(1_048_576 - pendingLine.count))
                    }
                    while let newline = pendingLine.firstIndex(of: 0x0A) {
                        let line = pendingLine.prefix(upTo: newline)
                        pendingLine.removeSubrange(...newline)
                        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                              let id = (object["id"] as? NSNumber)?.intValue,
                              let signal = signals[id] else { continue }
                        signal.signal()
                    }
                    lock.unlock()
                }
            }
        }

        func wait(for id: Int, timeout: TimeInterval) -> Bool {
            signals[id]?.wait(timeout: .now() + timeout) == .success
        }
    }

    private static func response(from data: Data) -> [String: Any]? {
        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  (object["id"] as? NSNumber)?.intValue == 2,
                  object["error"] == nil,
                  let result = object["result"] as? [String: Any]
            else { continue }
            return result
        }
        return nil
    }

    private static func snapshot(from response: [String: Any], now: Date) -> UsageSnapshot? {
        let source: [String: Any]?
        if let buckets = response["rateLimitsByLimitId"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any] {
            source = codex
        } else {
            source = response["rateLimits"] as? [String: Any]
        }
        guard let source else { return nil }

        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let value = source[key] as? [String: Any],
                  let used = number(value["usedPercent"]),
                  used.isFinite,
                  (0...100).contains(used)
            else { continue }

            let duration: Double?
            if let rawDuration = value["windowDurationMins"], !(rawDuration is NSNull) {
                guard let parsed = number(rawDuration),
                      parsed.isFinite,
                      parsed > 0,
                      parsed <= 10_000_000,
                      parsed.rounded() == parsed else { continue }
                duration = parsed
            } else {
                duration = nil
            }

            let kind: UsageWindowKind
            let label: String
            if let duration {
                let durationMinutes = Int(duration)
                switch durationMinutes {
                case 300:
                    kind = .fiveHour
                    label = "5 hours"
                case 10_080:
                    kind = .weekly
                    label = "7 days"
                default:
                    kind = .other
                    label = duration >= 60 ? "\(durationMinutes / 60) hours" : "\(durationMinutes) minutes"
                }
            } else {
                kind = .other
                label = "Quota window"
            }

            let resetAt = number(value["resetsAt"]).flatMap { seconds -> Date? in
                guard seconds.isFinite, seconds > 0 else { return nil }
                return Date(timeIntervalSince1970: seconds)
            }
            windows.append(UsageWindow(kind: kind, label: label, usedPercent: used, resetAt: resetAt))
        }

        guard !windows.isEmpty else { return nil }
        return UsageSnapshot(provider: .codex, source: .live, health: .ready, windows: windows, updatedAt: now)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.doubleValue
        }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func failure(kind: UsageIssueKind, title: String, message: String, recovery: String, at date: Date) -> UsageSnapshot {
        Self.failure(kind: kind, title: title, message: message, recovery: recovery, at: date)
    }

    private static func failure(kind: UsageIssueKind, title: String, message: String, recovery: String, at date: Date) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            source: .live,
            health: .needsAttention,
            issue: UsageIssue(kind: kind, title: title, message: message, recoverySuggestion: recovery),
            updatedAt: date
        )
    }
}
