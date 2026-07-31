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

        guard totals != nil || !windows.isEmpty else {
            return nil
        }

        let health: UsageHealth
        let issue: UsageIssue?
        if windows.isEmpty {
            windows.append(UsageWindow(label: "Current session", tokens: tokens.total))
            health = .limited
            issue = UsageIssue(
                kind: .quotaLimitsUnavailable,
                title: "Quota percentage unavailable",
                message: "Token activity was found, but this Codex login did not provide quota limits.",
                recoverySuggestion: "Session tokens are shown instead. View diagnostics when reporting this issue."
            )
        } else {
            health = .ready
            issue = nil
        }

        return UsageSnapshot(
            provider: .codex,
            health: health,
            issue: issue,
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
        let displayPath = "~/.codex/sessions and ~/.codex/archived_sessions"
        var existingRoots: [URL] = []
        var directoryPermissionFailures = 0
        var directoryOtherFailures = 0
        for root in roots {
            switch UsageReaderSupport.directoryState(for: root, fileManager: fileManager) {
            case .directory:
                existingRoots.append(root)
            case .missing:
                break
            case .failure(let error):
                if UsageReaderSupport.isPermissionError(error) {
                    directoryPermissionFailures += 1
                } else {
                    directoryOtherFailures += 1
                }
            }
        }

        guard !existingRoots.isEmpty else {
            if directoryPermissionFailures > 0 || directoryOtherFailures > 0 {
                let permissionDenied = directoryPermissionFailures > 0
                    && directoryOtherFailures == 0
                return unavailable(
                    kind: permissionDenied ? .permissionDenied : .readError,
                    title: permissionDenied
                        ? "Codex data folder could not be accessed"
                        : "Codex data folder could not be read",
                    message: permissionDenied
                        ? "macOS did not allow QuotaPeek to inspect the Codex data folder."
                        : "QuotaPeek could not inspect the Codex data folder.",
                    recoverySuggestion: permissionDenied
                        ? "Check file permissions, then refresh."
                        : "Try refreshing. If the problem continues, copy the diagnostic report.",
                    diagnostics: UsageDiagnostics(dataPath: displayPath)
                )
            }
            return unavailable(
                kind: .dataFolderNotFound,
                title: "Codex data folder not found",
                message: "QuotaPeek could not find local Codex session data.",
                recoverySuggestion: "Use Codex once on this Mac, then refresh.",
                diagnostics: UsageDiagnostics(dataPath: displayPath)
            )
        }

        var enumerationPermissionFailures = 0
        var enumerationOtherFailures = 0
        let files = existingRoots.flatMap { root in
            do {
                return try recentJSONLFiles(in: root)
            } catch {
                if UsageReaderSupport.isPermissionError(error) {
                    enumerationPermissionFailures += 1
                } else {
                    enumerationOtherFailures += 1
                }
                return []
            }
        }
            .map { ($0, UsageReaderSupport.modificationDate(for: $0)) }
            .sorted { ($0.1 ?? .distantFuture) > ($1.1 ?? .distantFuture) }

        guard !files.isEmpty else {
            let diagnostics = UsageDiagnostics(dataPath: displayPath)
            if enumerationPermissionFailures > 0 || enumerationOtherFailures > 0 {
                let permissionDenied = enumerationPermissionFailures > 0
                    && enumerationOtherFailures == 0
                return unavailable(
                    kind: permissionDenied ? .permissionDenied : .readError,
                    title: permissionDenied
                        ? "Codex files could not be accessed"
                        : "Codex data folder could not be read",
                    message: permissionDenied
                        ? "macOS did not allow QuotaPeek to inspect the Codex data folder."
                        : "QuotaPeek could not inspect the contents of the Codex data folder.",
                    recoverySuggestion: permissionDenied
                        ? "Check file permissions, then refresh."
                        : "Try refreshing. If the problem continues, copy the diagnostic report.",
                    diagnostics: diagnostics
                )
            }
            return inactive(
                title: "No Codex usage yet",
                message: "The Codex folder exists, but it does not contain any session records.",
                recoverySuggestion: "Use Codex once on this Mac, then refresh.",
                diagnostics: diagnostics
            )
        }

        var newestSnapshot: UsageSnapshot?
        var recordsScanned = 0
        var readableRecords = 0
        var readableFiles = 0
        var permissionFailures = 0
        var otherReadFailures = 0

        for (file, modifiedAt) in files {
            if let updatedAt = newestSnapshot?.updatedAt,
               let modifiedAt,
               modifiedAt <= updatedAt {
                break
            }
            let content: String
            do {
                content = try String(contentsOf: file, encoding: .utf8)
            } catch {
                if UsageReaderSupport.isPermissionError(error) {
                    permissionFailures += 1
                } else {
                    otherReadFailures += 1
                }
                continue
            }
            readableFiles += 1
            for line in content.split(separator: "\n").reversed() {
                recordsScanned += 1
                if let snapshot = CodexUsageParser.parse(line: String(line)) {
                    readableRecords += 1
                    if newestSnapshot?.updatedAt == nil
                        || (snapshot.updatedAt ?? .distantPast) > (newestSnapshot?.updatedAt ?? .distantPast) {
                        newestSnapshot = snapshot
                    }
                }
            }
        }

        let diagnostics = UsageDiagnostics(
            dataPath: displayPath,
            filesFound: files.count,
            recordsScanned: recordsScanned,
            readableRecords: readableRecords,
            latestActivity: newestSnapshot?.updatedAt ?? files.compactMap(\.1).max()
        )
        let totalPermissionFailures = directoryPermissionFailures
            + enumerationPermissionFailures
            + permissionFailures
        let totalOtherFailures = directoryOtherFailures
            + enumerationOtherFailures
            + otherReadFailures

        if let newestSnapshot {
            if totalPermissionFailures > 0 || totalOtherFailures > 0 {
                let permissionDenied = totalPermissionFailures > 0 && totalOtherFailures == 0
                return newestSnapshot
                    .reporting(
                        health: .limited,
                        issue: UsageIssue(
                            kind: permissionDenied ? .permissionDenied : .readError,
                            title: "Some Codex usage could not be read",
                            message: "The displayed usage may be incomplete because some local Codex data was inaccessible.",
                            recoverySuggestion: permissionDenied
                                ? "Check file permissions, then refresh."
                                : "Try refreshing. If the problem continues, copy the diagnostic report."
                        )
                    )
                    .attaching(diagnostics: diagnostics)
            }
            return newestSnapshot.attaching(diagnostics: diagnostics)
        }

        if readableFiles == 0 {
            let permissionDenied = permissionFailures > 0 && otherReadFailures == 0
            return unavailable(
                kind: permissionDenied ? .permissionDenied : .readError,
                title: permissionDenied
                    ? "Codex files could not be accessed"
                    : "Codex files could not be read",
                message: permissionDenied
                    ? "macOS did not allow QuotaPeek to open the Codex session files."
                    : "QuotaPeek found Codex session files but could not read their contents.",
                recoverySuggestion: permissionDenied
                    ? "Check file permissions, then refresh."
                    : "Try refreshing. If the problem continues, copy the diagnostic report.",
                diagnostics: diagnostics
            )
        }

        if totalPermissionFailures > 0 || totalOtherFailures > 0 {
            let permissionDenied = totalPermissionFailures > 0 && totalOtherFailures == 0
            return unavailable(
                kind: permissionDenied ? .permissionDenied : .readError,
                title: "Codex usage could not be read completely",
                message: "QuotaPeek could not inspect all available Codex session data.",
                recoverySuggestion: permissionDenied
                    ? "Check file permissions, then refresh."
                    : "Try refreshing. If the problem continues, copy the diagnostic report.",
                diagnostics: diagnostics
            )
        }

        if recordsScanned == 0 {
            return inactive(
                title: "No Codex usage found",
                message: "Codex session files exist, but they do not contain any activity.",
                recoverySuggestion: "Use Codex, then refresh QuotaPeek.",
                diagnostics: diagnostics
            )
        }

        return unavailable(
            kind: .unsupportedFormat,
            title: "Codex usage format not supported",
            message: "QuotaPeek found Codex activity but could not recognize a usage record.",
            recoverySuggestion: "Copy the diagnostic report when opening an issue.",
            diagnostics: diagnostics
        )
    }

    private func recentJSONLFiles(in root: URL) throws -> [URL] {
        try fileManager.subpathsOfDirectory(atPath: root.path).compactMap { path in
            let url = root.appendingPathComponent(path)
            return url.pathExtension == "jsonl" ? url : nil
        }
    }

    private func inactive(
        title: String,
        message: String,
        recoverySuggestion: String,
        diagnostics: UsageDiagnostics
    ) -> UsageSnapshot {
        UsageReaderSupport.inactive(
            provider: .codex,
            title: title,
            message: message,
            recoverySuggestion: recoverySuggestion,
            diagnostics: diagnostics
        )
    }

    private func unavailable(
        kind: UsageIssueKind,
        title: String,
        message: String,
        recoverySuggestion: String,
        diagnostics: UsageDiagnostics
    ) -> UsageSnapshot {
        UsageReaderSupport.unavailable(
            provider: .codex,
            kind: kind,
            title: title,
            message: message,
            recoverySuggestion: recoverySuggestion,
            diagnostics: diagnostics
        )
    }
}
