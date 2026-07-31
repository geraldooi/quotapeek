public enum MenuBarSummaryMode: String, CaseIterable, Equatable, Sendable {
    case visibleProviders
    case codexOnly
    case claudeOnly
    case iconOnly

    public var displayName: String {
        switch self {
        case .visibleProviders: "Visible providers"
        case .codexOnly: "Codex only"
        case .claudeOnly: "Claude Code only"
        case .iconOnly: "Icon only"
        }
    }

    public var fallbackText: String? {
        switch self {
        case .visibleProviders: "Tokens"
        case .codexOnly: "Codex"
        case .claudeOnly: "Claude"
        case .iconOnly: nil
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
}
