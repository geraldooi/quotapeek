import Foundation

public enum ClaudeUsageParser {
    public static func aggregate(
        lines: [String],
        now: Date,
        calendar: Calendar = .current
    ) -> UsageSnapshot {
        let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)
        let startOfDay = calendar.startOfDay(for: now)
        let displayCutoff = min(fiveHoursAgo, startOfDay)
        var seenMessageIDs = Set<String>()
        var activeRecordCount = 0
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
            if record.timestamp >= displayCutoff {
                activeRecordCount += 1
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
            if lines.isEmpty {
                return .unavailable(.claude, message: "No Claude Code usage found")
            }
            return UsageSnapshot(
                provider: .claude,
                health: .needsAttention,
                issue: UsageIssue(
                    kind: .unsupportedFormat,
                    title: "Claude Code usage format not supported",
                    message: "QuotaPeek found recent Claude Code activity but could not recognize a usage record.",
                    recoverySuggestion: "Copy the diagnostic report when opening an issue."
                ),
                diagnostics: UsageDiagnostics(
                    dataPath: "~/.claude/projects",
                    recordsScanned: lines.count
                )
            )
        }

        guard activeRecordCount > 0 else {
            return UsageSnapshot(
                provider: .claude,
                health: .needsAttention,
                issue: UsageIssue(
                    kind: .noRecentActivity,
                    title: "No recent Claude Code activity",
                    message: "Claude Code usage records were found, but they are outside the displayed time windows.",
                    recoverySuggestion: "Use Claude Code, then refresh QuotaPeek."
                ),
                diagnostics: UsageDiagnostics(
                    dataPath: "~/.claude/projects",
                    recordsScanned: lines.count,
                    readableRecords: seenMessageIDs.count,
                    latestActivity: newestDate
                ),
                updatedAt: newestDate
            )
        }

        return UsageSnapshot(
            provider: .claude,
            diagnostics: UsageDiagnostics(
                dataPath: "~/.claude/projects",
                recordsScanned: lines.count,
                readableRecords: seenMessageIDs.count,
                latestActivity: newestDate
            ),
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
            let timestamp = parseDate(timestampString)
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

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
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
        let displayPath = "~/.claude/projects"
        let cutoff = Calendar.current.startOfDay(for: now.addingTimeInterval(-24 * 60 * 60))
        var lines: [String] = []

        switch UsageReaderSupport.directoryState(for: projects, fileManager: fileManager) {
        case .directory:
            break
        case .missing:
            return unavailable(
                kind: .dataFolderNotFound,
                title: "Claude Code data folder not found",
                message: "QuotaPeek could not find local Claude Code project data.",
                recoverySuggestion: "Use Claude Code once on this Mac, then refresh.",
                diagnostics: UsageDiagnostics(dataPath: displayPath)
            )
        case .failure(let error):
            let permissionDenied = UsageReaderSupport.isPermissionError(error)
            return unavailable(
                kind: permissionDenied ? .permissionDenied : .readError,
                title: permissionDenied
                    ? "Claude Code data folder could not be accessed"
                    : "Claude Code data folder could not be read",
                message: permissionDenied
                    ? "macOS did not allow QuotaPeek to inspect the Claude Code data folder."
                    : "QuotaPeek could not inspect the Claude Code data folder.",
                recoverySuggestion: permissionDenied
                    ? "Check file permissions, then refresh."
                    : "Try refreshing. If the problem continues, copy the diagnostic report.",
                diagnostics: UsageDiagnostics(dataPath: displayPath)
            )
        }

        let paths: [String]
        do {
            paths = try fileManager.subpathsOfDirectory(atPath: projects.path)
        } catch {
            let permissionDenied = UsageReaderSupport.isPermissionError(error)
            return unavailable(
                kind: permissionDenied ? .permissionDenied : .readError,
                title: permissionDenied
                    ? "Claude Code files could not be accessed"
                    : "Claude Code data folder could not be read",
                message: permissionDenied
                    ? "macOS did not allow QuotaPeek to inspect the Claude Code data folder."
                    : "QuotaPeek could not inspect the contents of the Claude Code data folder.",
                recoverySuggestion: permissionDenied
                    ? "Check file permissions, then refresh."
                    : "Try refreshing. If the problem continues, copy the diagnostic report.",
                diagnostics: UsageDiagnostics(dataPath: displayPath)
            )
        }

        let files = paths.compactMap { path -> (URL, Date?)? in
            let file = projects.appendingPathComponent(path)
            guard file.pathExtension == "jsonl" else { return nil }
            return (file, UsageReaderSupport.modificationDate(for: file))
        }
        let latestActivity = files.compactMap(\.1).max()

        guard !files.isEmpty else {
            return unavailable(
                kind: .noRecentActivity,
                title: "No Claude Code usage yet",
                message: "The Claude Code folder exists, but it does not contain any project records.",
                recoverySuggestion: "Use Claude Code once on this Mac, then refresh.",
                diagnostics: UsageDiagnostics(dataPath: displayPath)
            )
        }

        let recentFiles = files.filter { modifiedAt in
            modifiedAt.1 == nil || modifiedAt.1! >= cutoff
        }
        guard !recentFiles.isEmpty else {
            return unavailable(
                kind: .noRecentActivity,
                title: "No recent Claude Code activity",
                message: "Claude Code data was found, but none of it was updated recently.",
                recoverySuggestion: "Use Claude Code, then refresh QuotaPeek.",
                diagnostics: UsageDiagnostics(
                    dataPath: displayPath,
                    filesFound: files.count,
                    latestActivity: latestActivity
                )
            )
        }

        var readableFiles = 0
        var permissionFailures = 0
        var otherReadFailures = 0
        for (url, _) in recentFiles {
            let content: String
            do {
                content = try String(contentsOf: url, encoding: .utf8)
            } catch {
                if UsageReaderSupport.isPermissionError(error) {
                    permissionFailures += 1
                } else {
                    otherReadFailures += 1
                }
                continue
            }
            readableFiles += 1
            lines.append(contentsOf: content.split(separator: "\n").map(String.init))
        }

        guard readableFiles > 0 else {
            let permissionDenied = permissionFailures > 0 && otherReadFailures == 0
            return unavailable(
                kind: permissionDenied ? .permissionDenied : .readError,
                title: permissionDenied
                    ? "Claude Code files could not be accessed"
                    : "Claude Code files could not be read",
                message: permissionDenied
                    ? "macOS did not allow QuotaPeek to open the Claude Code files."
                    : "QuotaPeek found Claude Code files but could not read their contents.",
                recoverySuggestion: permissionDenied
                    ? "Check file permissions, then refresh."
                    : "Try refreshing. If the problem continues, copy the diagnostic report.",
                diagnostics: UsageDiagnostics(
                    dataPath: displayPath,
                    filesFound: recentFiles.count,
                    latestActivity: latestActivity
                )
            )
        }

        let snapshot = ClaudeUsageParser.aggregate(lines: lines, now: now)
        let diagnostics = UsageDiagnostics(
            dataPath: displayPath,
            filesFound: recentFiles.count,
            recordsScanned: lines.count,
            readableRecords: snapshot.diagnostics?.readableRecords ?? 0,
            latestActivity: snapshot.updatedAt ?? latestActivity
        )
        if permissionFailures > 0 || otherReadFailures > 0 {
            let permissionDenied = permissionFailures > 0 && otherReadFailures == 0
            if snapshot.isAvailable {
                return snapshot
                    .reporting(
                        health: .limited,
                        issue: UsageIssue(
                            kind: permissionDenied ? .permissionDenied : .readError,
                            title: "Some Claude Code usage could not be read",
                            message: "The displayed usage may be incomplete because some local Claude Code data was inaccessible.",
                            recoverySuggestion: permissionDenied
                                ? "Check file permissions, then refresh."
                                : "Try refreshing. If the problem continues, copy the diagnostic report."
                        )
                    )
                    .attaching(diagnostics: diagnostics)
            }
            return unavailable(
                kind: permissionDenied ? .permissionDenied : .readError,
                title: "Claude Code usage could not be read completely",
                message: "QuotaPeek could not inspect all recent Claude Code data.",
                recoverySuggestion: permissionDenied
                    ? "Check file permissions, then refresh."
                    : "Try refreshing. If the problem continues, copy the diagnostic report.",
                diagnostics: diagnostics
            )
        }

        return snapshot.attaching(diagnostics: diagnostics)
    }

    private func unavailable(
        kind: UsageIssueKind,
        title: String,
        message: String,
        recoverySuggestion: String,
        diagnostics: UsageDiagnostics
    ) -> UsageSnapshot {
        UsageReaderSupport.unavailable(
            provider: .claude,
            kind: kind,
            title: title,
            message: message,
            recoverySuggestion: recoverySuggestion,
            diagnostics: diagnostics
        )
    }
}
