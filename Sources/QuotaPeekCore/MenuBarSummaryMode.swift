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

    public func summaryText(
        visibility: ProviderVisibility,
        codex: UsageSnapshot,
        claude: UsageSnapshot
    ) -> String? {
        let selectedProviders = providers(in: visibility)
        guard !selectedProviders.isEmpty else { return nil }

        return selectedProviders.map { provider in
            let snapshot = provider == .codex ? codex : claude
            let prefix = provider == .codex ? "C" : "A"

            if provider == .codex, let used = snapshot.windows.first?.usedPercent {
                return "\(prefix) \(Int(used.rounded()))%"
            }
            if let tokens = snapshot.windows.first?.tokens {
                return "\(prefix) \(UsageFormatting.tokens(tokens))"
            }
            return "\(prefix) —"
        }
        .joined(separator: " · ")
    }
}
