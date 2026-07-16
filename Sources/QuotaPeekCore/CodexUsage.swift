import Foundation

public enum CodexUsageParser {
    public static func parse(line: String) -> UsageSnapshot? {
        guard
            let root = JSONValue.object(from: line),
            let payload = JSONValue.dictionary(root["payload"]),
            payload["type"] as? String == "token_count"
        else {
            return nil
        }

        let info = JSONValue.dictionary(payload["info"])
        let totals = JSONValue.dictionary(info?["total_token_usage"])
        let limits = JSONValue.dictionary(payload["rate_limits"])

        let tokens = TokenBreakdown(
            input: JSONValue.int(totals?["input_tokens"]),
            cachedInput: JSONValue.int(totals?["cached_input_tokens"]),
            output: JSONValue.int(totals?["output_tokens"]),
            total: JSONValue.int(totals?["total_tokens"])
        )

        var windows: [UsageWindow] = []
        if let primary = window(from: limits?["primary"]) {
            windows.append(primary)
        }
        if let secondary = window(from: limits?["secondary"]) {
            windows.append(secondary)
        }

        return UsageSnapshot(
            provider: .codex,
            tokens: tokens,
            contextWindow: JSONValue.int(info?["model_context_window"]),
            windows: windows,
            updatedAt: parseDate(root["timestamp"] as? String)
        )
    }

    private static func window(from value: Any?) -> UsageWindow? {
        guard
            let object = JSONValue.dictionary(value),
            let usedPercent = JSONValue.double(object["used_percent"])
        else {
            return nil
        }

        let minutes = JSONValue.int(object["window_minutes"])
        let label: String
        switch minutes {
        case 300: label = "5 hours"
        case 10_080: label = "7 days"
        case let value where value >= 1_440: label = "\(value / 1_440) days"
        case let value where value >= 60: label = "\(value / 60) hours"
        default: label = "\(minutes) minutes"
        }

        let resetAt = JSONValue.double(object["resets_at"]).map {
            Date(timeIntervalSince1970: $0)
        }
        return UsageWindow(label: label, usedPercent: usedPercent, resetAt: resetAt)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

public struct CodexUsageReader {
    private let homeDirectory: URL
    private let fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    public func load() -> UsageSnapshot {
        let codexDirectory = homeDirectory.appendingPathComponent(".codex")
        let roots = [
            codexDirectory.appendingPathComponent("sessions"),
            codexDirectory.appendingPathComponent("archived_sessions")
        ]

        let files = roots.flatMap { recentJSONLFiles(in: $0) }
            .map { ($0, modificationDate(for: $0)) }
            .sorted { $0.1 > $1.1 }
        var newestSnapshot: UsageSnapshot?

        for (file, modifiedAt) in files {
            if let updatedAt = newestSnapshot?.updatedAt, modifiedAt <= updatedAt {
                break
            }
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n").reversed() {
                if let snapshot = CodexUsageParser.parse(line: String(line)) {
                    if newestSnapshot?.updatedAt == nil
                        || (snapshot.updatedAt ?? .distantPast) > (newestSnapshot?.updatedAt ?? .distantPast) {
                        newestSnapshot = snapshot
                    }
                    break
                }
            }
        }

        return newestSnapshot ?? .unavailable(.codex, message: "No Codex usage found")
    }

    private func recentJSONLFiles(in root: URL) -> [URL] {
        guard let paths = try? fileManager.subpathsOfDirectory(atPath: root.path) else {
            return []
        }

        return paths.compactMap { path in
            let url = root.appendingPathComponent(path)
            return url.pathExtension == "jsonl" ? url : nil
        }
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
