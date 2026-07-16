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
    public let isAvailable: Bool
    public let statusMessage: String?
    public let tokens: TokenBreakdown
    public let contextWindow: Int?
    public let windows: [UsageWindow]
    public let updatedAt: Date?

    public init(
        provider: Provider,
        isAvailable: Bool = true,
        statusMessage: String? = nil,
        tokens: TokenBreakdown = TokenBreakdown(),
        contextWindow: Int? = nil,
        windows: [UsageWindow] = [],
        updatedAt: Date? = nil
    ) {
        self.provider = provider
        self.isAvailable = isAvailable
        self.statusMessage = statusMessage
        self.tokens = tokens
        self.contextWindow = contextWindow
        self.windows = windows
        self.updatedAt = updatedAt
    }

    public static func unavailable(_ provider: Provider, message: String) -> UsageSnapshot {
        UsageSnapshot(provider: provider, isAvailable: false, statusMessage: message)
    }
}
