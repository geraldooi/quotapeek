import Foundation

public struct ClaudeQuotaWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let resetAt: Date

    public init(usedPercent: Double, resetAt: Date) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
    }
}

public struct ClaudeQuotaCapture: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let fiveHour: ClaudeQuotaWindow?
    public let sevenDay: ClaudeQuotaWindow?

    public init(
        capturedAt: Date,
        fiveHour: ClaudeQuotaWindow?,
        sevenDay: ClaudeQuotaWindow?
    ) {
        self.capturedAt = capturedAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

public enum ClaudeQuotaCaptureParseResult: Equatable, Sendable {
    case unavailable
    case invalid
    case capture(ClaudeQuotaCapture)
}

public enum ClaudeQuotaCaptureParser {
    public static func parse(
        data: Data,
        capturedAt: Date = Date()
    ) -> ClaudeQuotaCapture? {
        guard case .capture(let capture) = result(
            data: data,
            capturedAt: capturedAt
        ) else {
            return nil
        }
        return capture
    }

    public static func result(
        data: Data,
        capturedAt: Date = Date()
    ) -> ClaudeQuotaCaptureParseResult {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .invalid
        }
        guard let rawLimits = root["rate_limits"] else {
            return .unavailable
        }
        guard let limits = rawLimits as? [String: Any] else {
            return .invalid
        }

        let fiveHour = window(from: limits["five_hour"])
        let sevenDay = window(from: limits["seven_day"])
        guard fiveHour != nil || sevenDay != nil else { return .invalid }

        return .capture(
            ClaudeQuotaCapture(
                capturedAt: capturedAt,
                fiveHour: fiveHour,
                sevenDay: sevenDay
            )
        )
    }

    private static func window(from value: Any?) -> ClaudeQuotaWindow? {
        guard
            let object = value as? [String: Any],
            !isBoolean(object["used_percentage"]),
            let usedPercent = JSONValue.double(object["used_percentage"]),
            (0...100).contains(usedPercent),
            !isBoolean(object["resets_at"]),
            let resetTimestamp = JSONValue.double(object["resets_at"]),
            resetTimestamp > 0
        else {
            return nil
        }

        return ClaudeQuotaWindow(
            usedPercent: usedPercent,
            resetAt: Date(timeIntervalSince1970: resetTimestamp)
        )
    }

    private static func isBoolean(_ value: Any?) -> Bool {
        value is Bool
    }
}

public struct ClaudeQuotaStore: Sendable {
    public let cacheURL: URL

    public init(cacheURL: URL) {
        self.cacheURL = cacheURL
    }

    public func save(_ capture: ClaudeQuotaCapture) throws {
        let directory = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(capture).write(to: cacheURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: cacheURL.path
        )
    }

    public func load() throws -> ClaudeQuotaCapture? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: cacheURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let capture: ClaudeQuotaCapture
        do {
            capture = try decoder.decode(ClaudeQuotaCapture.self, from: data)
        } catch {
            throw ClaudeQuotaStoreError.invalidCapture
        }
        let windows = [capture.fiveHour, capture.sevenDay].compactMap { $0 }
        guard
            capture.capturedAt.timeIntervalSince1970.isFinite,
            !windows.isEmpty,
            windows.allSatisfy({ window in
                window.usedPercent.isFinite
                    && (0...100).contains(window.usedPercent)
                    && window.resetAt.timeIntervalSince1970.isFinite
                    && window.resetAt.timeIntervalSince1970 > 0
            })
        else {
            throw ClaudeQuotaStoreError.invalidCapture
        }
        return capture
    }
}

public enum ClaudeQuotaStoreError: Error {
    case invalidCapture
}

public enum ClaudeQuotaCaptureStatus: String, Sendable {
    case ready
    case invalidPayload = "invalid-payload"
    case permissionFailure = "permission-failure"
    case writeFailure = "write-failure"

    public static func failure(for error: Error) -> ClaudeQuotaCaptureStatus {
        UsageReaderSupport.isPermissionError(error)
            ? .permissionFailure
            : .writeFailure
    }
}

public struct ClaudeQuotaCaptureStatusStore: Sendable {
    public let statusURL: URL

    private static let recordSize = 32

    public init(statusURL: URL) {
        self.statusURL = statusURL
    }

    public func ensureExists() throws {
        guard !FileManager.default.fileExists(atPath: statusURL.path) else {
            return
        }
        try FileManager.default.createDirectory(
            at: statusURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try paddedData(for: .ready).write(to: statusURL, options: .withoutOverwriting)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: statusURL.path
        )
    }

    public func record(_ status: ClaudeQuotaCaptureStatus) throws {
        let handle = try FileHandle(forWritingTo: statusURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: paddedData(for: status))
        try handle.synchronize()
    }

    public func load() throws -> ClaudeQuotaCaptureStatus? {
        guard FileManager.default.fileExists(atPath: statusURL.path) else {
            return nil
        }
        let rawValue = String(decoding: try Data(contentsOf: statusURL), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }
        guard let status = ClaudeQuotaCaptureStatus(rawValue: rawValue) else {
            throw ClaudeQuotaCaptureStatusError.invalidStatus
        }
        return status
    }

    private func paddedData(for status: ClaudeQuotaCaptureStatus) -> Data {
        let value = status.rawValue + "\n"
        let padding = max(0, Self.recordSize - value.utf8.count)
        return Data((value + String(repeating: " ", count: padding)).utf8)
    }
}

public enum ClaudeQuotaCaptureStatusError: Error {
    case invalidStatus
}

public struct ClaudeQuotaReader: Sendable {
    private let cacheURL: URL
    private let captureStatusURL: URL
    private let integrationEnabled: Bool

    public init(
        cacheURL: URL,
        captureStatusURL: URL? = nil,
        integrationEnabled: Bool
    ) {
        self.cacheURL = cacheURL
        self.captureStatusURL = captureStatusURL
            ?? cacheURL.deletingLastPathComponent()
                .appendingPathComponent("claude-capture-status")
        self.integrationEnabled = integrationEnabled
    }

    public func load(now: Date = Date()) -> UsageSnapshot {
        guard integrationEnabled else {
            return unavailable(
                title: "Claude quota bars are not enabled",
                message: "QuotaPeek needs Claude Code's official status-line data to show account usage percentages.",
                recoverySuggestion: "Enable Claude quota bars, then use Claude Code once."
            )
        }

        do {
            let status = try ClaudeQuotaCaptureStatusStore(
                statusURL: captureStatusURL
            ).load()
            if status == .permissionFailure {
                return captureWriteFailure(permissionDenied: true)
            }
            if status == .writeFailure {
                return captureWriteFailure(permissionDenied: false)
            }
            if status == .invalidPayload {
                return unavailable(
                    kind: .unsupportedFormat,
                    title: "Claude quota data is invalid",
                    message: "Claude Code supplied quota limits in an unexpected format.",
                    recoverySuggestion: "Update Claude Code, send one message, then refresh QuotaPeek."
                )
            }
        } catch where UsageReaderSupport.isPermissionError(error) {
            return unavailable(
                kind: .permissionDenied,
                title: "Claude quota status could not be accessed",
                message: "macOS did not allow QuotaPeek to read its Claude capture status.",
                recoverySuggestion: "Check file permissions for QuotaPeek, then refresh."
            )
        } catch {
            return unavailable(
                kind: .readError,
                title: "Claude quota status could not be read",
                message: "QuotaPeek could not determine whether Claude quota capture succeeded.",
                recoverySuggestion: "Disable and re-enable Claude quota bars, then try again."
            )
        }

        let capture: ClaudeQuotaCapture
        do {
            guard let loaded = try ClaudeQuotaStore(cacheURL: cacheURL).load() else {
                return unavailable(
                    title: "Waiting for Claude quota data",
                    message: "Claude Code has not supplied its five-hour and weekly limits yet.",
                    recoverySuggestion: "Send one Claude Code message, then refresh QuotaPeek."
                )
            }
            capture = loaded
        } catch is ClaudeQuotaStoreError {
            return unavailable(
                kind: .unsupportedFormat,
                title: "Claude quota cache is invalid",
                message: "QuotaPeek found Claude quota data, but it was not in the expected format.",
                recoverySuggestion: "Disable and re-enable Claude quota bars, then use Claude Code once.",
                filesFound: 1
            )
        } catch where UsageReaderSupport.isPermissionError(error) {
            return unavailable(
                kind: .permissionDenied,
                title: "Claude quota cache could not be accessed",
                message: "macOS did not allow QuotaPeek to read the Claude quota cache.",
                recoverySuggestion: "Check file permissions for QuotaPeek, then refresh.",
                filesFound: 1
            )
        } catch {
            return unavailable(
                kind: .readError,
                title: "Claude quota cache could not be read",
                message: "QuotaPeek found the Claude quota cache but could not read it.",
                recoverySuggestion: "Disable and re-enable Claude quota bars, then try again.",
                filesFound: 1
            )
        }

        let candidates = [
            capture.fiveHour.map { window in UsageWindow(
                label: "5 hours",
                usedPercent: window.usedPercent,
                resetAt: window.resetAt
            ) },
            capture.sevenDay.map { window in UsageWindow(
                label: "Weekly",
                usedPercent: window.usedPercent,
                resetAt: window.resetAt
            ) }
        ].compactMap { $0 }
        let windows = candidates.filter { ($0.resetAt ?? .distantPast) > now }

        guard !windows.isEmpty else {
            return unavailable(
                title: "Claude quota data is stale",
                message: "The last Claude quota windows have already reset.",
                recoverySuggestion: "Send one Claude Code message, then refresh QuotaPeek."
            )
        }

        let diagnostics = UsageDiagnostics(
            dataPath: "Claude Code status-line quota cache",
            filesFound: 1,
            readableRecords: 1,
            latestActivity: capture.capturedAt
        )
        if windows.count < 2 {
            return UsageSnapshot(
                provider: .claude,
                health: .limited,
                issue: UsageIssue(
                    kind: .quotaLimitsUnavailable,
                    title: "Some Claude quota data is unavailable",
                    message: "QuotaPeek is showing only the current quota window Claude Code supplied.",
                    recoverySuggestion: "Send one Claude Code message to update both windows."
                ),
                diagnostics: diagnostics,
                windows: windows,
                updatedAt: capture.capturedAt
            )
        }

        return UsageSnapshot(
            provider: .claude,
            diagnostics: diagnostics,
            windows: windows,
            updatedAt: capture.capturedAt
        )
    }

    private func unavailable(
        kind: UsageIssueKind = .quotaLimitsUnavailable,
        title: String,
        message: String,
        recoverySuggestion: String,
        filesFound: Int = 0
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claude,
            health: .needsAttention,
            issue: UsageIssue(
                kind: kind,
                title: title,
                message: message,
                recoverySuggestion: recoverySuggestion
            ),
            diagnostics: UsageDiagnostics(
                dataPath: "Claude Code status-line quota cache",
                filesFound: filesFound
            )
        )
    }

    private func captureWriteFailure(permissionDenied: Bool) -> UsageSnapshot {
        unavailable(
            kind: permissionDenied ? .permissionDenied : .readError,
            title: "Claude quota data could not be saved",
            message: permissionDenied
                ? "macOS did not allow the Claude quota bridge to update QuotaPeek's cache."
                : "The Claude quota bridge could not update QuotaPeek's cache.",
            recoverySuggestion: permissionDenied
                ? "Check file permissions for QuotaPeek, then use Claude Code again."
                : "Check available storage, then disable and re-enable Claude quota bars.",
            filesFound: FileManager.default.fileExists(atPath: cacheURL.path) ? 1 : 0
        )
    }
}
