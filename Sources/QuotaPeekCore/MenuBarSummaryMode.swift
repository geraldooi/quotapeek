public enum MenuBarSummaryValue: Equatable, Sendable {
    case percent(Int)
    case tokens(Int)
    case unavailable

    public var displayText: String {
        switch self {
        case let .percent(value): "\(value)%"
        case let .tokens(value): UsageFormatting.tokens(value)
        case .unavailable: "—"
        }
    }

    public var accessibilityText: String {
        switch self {
        case let .percent(value): "\(value) percent used"
        case let .tokens(value): "\(UsageFormatting.tokens(value)) tokens used"
        case .unavailable: "usage unavailable"
        }
    }
}

public struct MenuBarSummaryItem: Equatable, Sendable {
    public let provider: Provider
    public let value: MenuBarSummaryValue

    public init(provider: Provider, value: MenuBarSummaryValue) {
        self.provider = provider
        self.value = value
    }
}

public enum MenuBarSummaryMode: String, CaseIterable, Equatable, Sendable {
    case visibleProviders
    case codexOnly
    case claudeOnly
    case iconOnly

    public var displayName: String {
        switch self {
        case .visibleProviders: "All visible providers"
        case .codexOnly: "Codex only"
        case .claudeOnly: "Claude Code only"
        case .iconOnly: "Icon only"
        }
    }

    public func providers(in visibility: ProviderVisibility) -> [Provider] {
        switch self {
        case .visibleProviders:
            visibility.visibleProviders
        case .codexOnly:
            visibility.showsCodex ? [.codex] : []
        case .claudeOnly:
            visibility.showsClaude ? [.claude] : []
        case .iconOnly:
            []
        }
    }

    public func summaryItems(
        visibility: ProviderVisibility,
        codex: UsageSnapshot,
        claude: UsageSnapshot
    ) -> [MenuBarSummaryItem] {
        providers(in: visibility).map { provider in
            let snapshot = provider == .codex ? codex : claude
            let value: MenuBarSummaryValue

            if let used = snapshot.windows.first?.usedPercent {
                value = .percent(Int(used.rounded()))
            } else if let tokens = snapshot.windows.first?.tokens {
                value = .tokens(tokens)
            } else {
                value = .unavailable
            }

            return MenuBarSummaryItem(provider: provider, value: value)
        }
    }
}
