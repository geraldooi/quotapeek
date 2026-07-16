import Foundation

public enum ClaudeUsageParser {
    public static func aggregate(
        lines: [String],
        now: Date,
        calendar: Calendar = .current
    ) -> UsageSnapshot {
        let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)
        let startOfDay = calendar.startOfDay(for: now)
        var seenMessageIDs = Set<String>()
        var recentTokens = 0
        var today = TokenBreakdown()
        var newestDate: Date?

        for line in lines {
            guard
                let record = parse(line: line),
                record.timestamp <= now,
                seenMessageIDs.insert(record.id).inserted
            else {
                continue
            }

            if record.timestamp >= fiveHoursAgo {
                recentTokens += record.tokens.total
            }
            if record.timestamp >= startOfDay {
                today.input += record.tokens.input
                today.cachedInput += record.tokens.cachedInput
                today.output += record.tokens.output
                today.total += record.tokens.total
            }
            newestDate = max(newestDate ?? record.timestamp, record.timestamp)
        }

        guard !seenMessageIDs.isEmpty else {
            return .unavailable(.claude, message: "No Claude Code usage found")
        }

        return UsageSnapshot(
            provider: .claude,
            tokens: today,
            windows: [
                UsageWindow(label: "5 hours", tokens: recentTokens),
                UsageWindow(label: "Today", tokens: today.total)
            ],
            updatedAt: newestDate
        )
    }

    private struct Record {
        let id: String
        let timestamp: Date
        let tokens: TokenBreakdown
    }

    private static func parse(line: String) -> Record? {
        guard
            let root = JSONValue.object(from: line),
            let message = JSONValue.dictionary(root["message"]),
            let usage = JSONValue.dictionary(message["usage"]),
            let id = message["id"] as? String,
            let timestampString = root["timestamp"] as? String,
            let timestamp = ISO8601DateFormatter().date(from: timestampString)
        else {
            return nil
        }

        let input = JSONValue.int(usage["input_tokens"])
        let cached = JSONValue.int(usage["cache_read_input_tokens"])
            + JSONValue.int(usage["cache_creation_input_tokens"])
        let output = JSONValue.int(usage["output_tokens"])
        return Record(
            id: id,
            timestamp: timestamp,
            tokens: TokenBreakdown(
                input: input,
                cachedInput: cached,
                output: output,
                total: input + cached + output
            )
        )
    }
}

public struct ClaudeUsageReader {
    private let homeDirectory: URL
    private let fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    public func load(now: Date = Date()) -> UsageSnapshot {
        let projects = homeDirectory
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
        let cutoff = Calendar.current.startOfDay(for: now.addingTimeInterval(-24 * 60 * 60))
        var lines: [String] = []

        guard let paths = try? fileManager.subpathsOfDirectory(atPath: projects.path) else {
            return .unavailable(.claude, message: "Claude Code data folder not found")
        }

        for path in paths {
            let url = projects.appendingPathComponent(path)
            guard url.pathExtension == "jsonl" else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            guard modified >= cutoff, let content = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            lines.append(contentsOf: content.split(separator: "\n").map(String.init))
        }

        return ClaudeUsageParser.aggregate(lines: lines, now: now)
    }
}
