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

public enum ClaudeQuotaCaptureParser {
    public static func parse(
        data: Data,
        capturedAt: Date = Date()
    ) -> ClaudeQuotaCapture? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let limits = root["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        let fiveHour = window(from: limits["five_hour"])
        let sevenDay = window(from: limits["seven_day"])
        guard fiveHour != nil || sevenDay != nil else { return nil }

        return ClaudeQuotaCapture(
            capturedAt: capturedAt,
            fiveHour: fiveHour,
            sevenDay: sevenDay
        )
    }

    private static func window(from value: Any?) -> ClaudeQuotaWindow? {
        guard
            let object = value as? [String: Any],
            let usedPercent = JSONValue.double(object["used_percentage"]),
            (0...100).contains(usedPercent),
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

    public func load() -> ClaudeQuotaCapture? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(ClaudeQuotaCapture.self, from: data)
    }
}

public struct ClaudeQuotaReader: Sendable {
    private let cacheURL: URL
    private let integrationEnabled: Bool

    public init(cacheURL: URL, integrationEnabled: Bool) {
        self.cacheURL = cacheURL
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

        guard let capture = ClaudeQuotaStore(cacheURL: cacheURL).load() else {
            return unavailable(
                title: "Waiting for Claude quota data",
                message: "Claude Code has not supplied its five-hour and weekly limits yet.",
                recoverySuggestion: "Send one Claude Code message, then refresh QuotaPeek."
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
        title: String,
        message: String,
        recoverySuggestion: String
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claude,
            health: .needsAttention,
            issue: UsageIssue(
                kind: .quotaLimitsUnavailable,
                title: title,
                message: message,
                recoverySuggestion: recoverySuggestion
            ),
            diagnostics: UsageDiagnostics(
                dataPath: "Claude Code status-line quota cache"
            )
        )
    }
}
