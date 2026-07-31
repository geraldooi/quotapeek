import Foundation

public enum Provider: String, Equatable, Sendable {
    case codex
    case claude

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }
}

public enum UsageHealth: Equatable, Sendable {
    case loading
    case ready
    case inactive
    case limited
    case needsAttention
}

public enum UsageIssueKind: String, Equatable, Sendable {
    case dataFolderNotFound
    case noRecentActivity
    case unsupportedFormat
    case permissionDenied
    case quotaLimitsUnavailable
    case readError
}

public struct UsageIssue: Equatable, Sendable {
    public let kind: UsageIssueKind
    public let title: String
    public let message: String
    public let recoverySuggestion: String

    public init(
        kind: UsageIssueKind,
        title: String,
        message: String,
        recoverySuggestion: String
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}

public struct UsageDiagnostics: Equatable, Sendable {
    public let dataPath: String
    public let filesFound: Int
    public let recordsScanned: Int
    public let readableRecords: Int
    public let latestActivity: Date?

    public init(
        dataPath: String,
        filesFound: Int = 0,
        recordsScanned: Int = 0,
        readableRecords: Int = 0,
        latestActivity: Date? = nil
    ) {
        self.dataPath = dataPath
        self.filesFound = filesFound
        self.recordsScanned = recordsScanned
        self.readableRecords = readableRecords
        self.latestActivity = latestActivity
    }

    public func report(
        provider: Provider,
        health: UsageHealth,
        issue: UsageIssue?,
        appVersion: String
    ) -> String {
        let latest = latestActivity.map {
            ISO8601DateFormatter().string(from: $0)
        } ?? "Not available"
        let status: String
        switch health {
        case .loading: status = "Loading"
        case .ready: status = "Working"
        case .inactive: status = "Inactive"
        case .limited: status = "Limited"
        case .needsAttention: status = "Needs attention"
        }

        return """
        QuotaPeek \(appVersion)
        Provider: \(provider.displayName)
        Status: \(status)
        Reason: \(issue?.title ?? "None")
        Data folder: \(dataPath)
        Files found: \(filesFound)
        Records scanned: \(recordsScanned)
        Readable usage records: \(readableRecords)
        Latest activity: \(latest)

        Privacy: This report does not include prompts, responses, credentials, or usernames.
        """
    }
}

public struct TokenBreakdown: Equatable, Sendable {
    public var input: Int
    public var cachedInput: Int
    public var output: Int
    public var total: Int

    public init(input: Int = 0, cachedInput: Int = 0, output: Int = 0, total: Int = 0) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.total = total
    }
}

public struct UsageWindow: Equatable, Sendable {
    public let label: String
    public let usedPercent: Double?
    public let resetAt: Date?
    public let tokens: Int?

    public init(label: String, usedPercent: Double? = nil, resetAt: Date? = nil, tokens: Int? = nil) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.tokens = tokens
    }

    public var remainingPercent: Double? {
        usedPercent.map { max(0, 100 - $0) }
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let provider: Provider
    public let health: UsageHealth
    public let issue: UsageIssue?
    public let diagnostics: UsageDiagnostics?
    public let tokens: TokenBreakdown
    public let contextWindow: Int?
    public let windows: [UsageWindow]
    public let updatedAt: Date?

    public init(
        provider: Provider,
        health: UsageHealth = .ready,
        issue: UsageIssue? = nil,
        diagnostics: UsageDiagnostics? = nil,
        tokens: TokenBreakdown = TokenBreakdown(),
        contextWindow: Int? = nil,
        windows: [UsageWindow] = [],
        updatedAt: Date? = nil
    ) {
        self.provider = provider
        self.health = health
        self.issue = issue
        self.diagnostics = diagnostics
        self.tokens = tokens
        self.contextWindow = contextWindow
        self.windows = windows
        self.updatedAt = updatedAt
    }

    public var isAvailable: Bool {
        health == .ready || health == .limited
    }

    public var needsAttention: Bool {
        health == .limited || health == .needsAttention
    }

    public var statusMessage: String? {
        issue?.title
    }

    public static func loading(_ provider: Provider) -> UsageSnapshot {
        UsageSnapshot(provider: provider, health: .loading)
    }

    public static func unavailable(_ provider: Provider, message: String) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            health: .needsAttention,
            issue: UsageIssue(
                kind: .readError,
                title: message,
                message: "QuotaPeek could not read usage for this provider.",
                recoverySuggestion: "Try refreshing. If the problem continues, view diagnostics."
            )
        )
    }

    public func attaching(diagnostics: UsageDiagnostics) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            health: health,
            issue: issue,
            diagnostics: diagnostics,
            tokens: tokens,
            contextWindow: contextWindow,
            windows: windows,
            updatedAt: updatedAt
        )
    }

    public func reporting(health: UsageHealth, issue: UsageIssue) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            health: health,
            issue: issue,
            diagnostics: diagnostics,
            tokens: tokens,
            contextWindow: contextWindow,
            windows: windows,
            updatedAt: updatedAt
        )
    }
}
