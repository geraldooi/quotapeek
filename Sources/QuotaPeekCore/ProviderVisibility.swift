public struct ProviderVisibility: Equatable, Sendable {
    public let showsCodex: Bool
    public let showsClaude: Bool

    public init(showsCodex: Bool = true, showsClaude: Bool = true) {
        if showsCodex || showsClaude {
            self.showsCodex = showsCodex
            self.showsClaude = showsClaude
        } else {
            self.showsCodex = true
            self.showsClaude = false
        }
    }

    public var visibleProviders: [Provider] {
        var providers: [Provider] = []
        if showsCodex {
            providers.append(.codex)
        }
        if showsClaude {
            providers.append(.claude)
        }
        return providers
    }

    public var subtitle: String {
        switch (showsCodex, showsClaude) {
        case (true, true): "Codex and Claude Code"
        case (true, false): "Codex"
        case (false, true): "Claude Code"
        case (false, false): "Codex"
        }
    }

    public func contains(_ provider: Provider) -> Bool {
        switch provider {
        case .codex: showsCodex
        case .claude: showsClaude
        }
    }

    public func setting(_ provider: Provider, isVisible: Bool) -> ProviderVisibility {
        let showsCodex = provider == .codex ? isVisible : showsCodex
        let showsClaude = provider == .claude ? isVisible : showsClaude

        guard showsCodex || showsClaude else {
            return self
        }
        return ProviderVisibility(showsCodex: showsCodex, showsClaude: showsClaude)
    }
}
