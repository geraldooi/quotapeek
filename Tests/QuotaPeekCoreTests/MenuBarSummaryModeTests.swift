import Testing
@testable import QuotaPeekCore

@Suite("Menu-bar summary mode")
struct MenuBarSummaryModeTests {
    @Test("Displays every visible provider, including inactive providers")
    func displaysEveryVisibleProvider() {
        let codex = UsageSnapshot(
            provider: .codex,
            windows: [UsageWindow(label: "7 days", usedPercent: 69)]
        )
        let claude = UsageSnapshot(provider: .claude, health: .inactive)

        #expect(
            MenuBarSummaryMode.visibleProviders.summaryText(
                visibility: ProviderVisibility(),
                codex: codex,
                claude: claude
            ) == "C 69% · A —"
        )
        #expect(
            MenuBarSummaryMode.codexOnly.summaryText(
                visibility: ProviderVisibility(),
                codex: codex,
                claude: claude
            ) == "C 69%"
        )
        #expect(
            MenuBarSummaryMode.claudeOnly.summaryText(
                visibility: ProviderVisibility(),
                codex: codex,
                claude: claude
            ) == "A —"
        )
        #expect(
            MenuBarSummaryMode.iconOnly.summaryText(
                visibility: ProviderVisibility(),
                codex: codex,
                claude: claude
            ) == nil
        )
    }

    @Test("Formats every menu-bar mode distinctly")
    func formatsEveryModeDistinctly() {
        let visibility = ProviderVisibility()
        let codex = UsageSnapshot(
            provider: .codex,
            windows: [UsageWindow(label: "7 days", usedPercent: 69)]
        )
        let claude = UsageSnapshot(
            provider: .claude,
            windows: [UsageWindow(label: "Today", tokens: 12_500)]
        )

        #expect(
            MenuBarSummaryMode.visibleProviders.summaryText(
                visibility: visibility,
                codex: codex,
                claude: claude
            ) == "C 69% · A 12.5K"
        )
        #expect(
            MenuBarSummaryMode.codexOnly.summaryText(
                visibility: visibility,
                codex: codex,
                claude: claude
            ) == "C 69%"
        )
        #expect(
            MenuBarSummaryMode.claudeOnly.summaryText(
                visibility: visibility,
                codex: codex,
                claude: claude
            ) == "A 12.5K"
        )
        #expect(
            MenuBarSummaryMode.iconOnly.summaryText(
                visibility: visibility,
                codex: codex,
                claude: claude
            ) == nil
        )
    }

    @Test("Uses every visible provider by default")
    func usesVisibleProvidersByDefault() {
        let both = ProviderVisibility()
        let codexOnly = ProviderVisibility(showsCodex: true, showsClaude: false)

        #expect(MenuBarSummaryMode.visibleProviders.providers(in: both) == [.codex, .claude])
        #expect(MenuBarSummaryMode.visibleProviders.providers(in: codexOnly) == [.codex])
    }

    @Test("Provider-specific modes respect visibility")
    func providerModesRespectVisibility() {
        let both = ProviderVisibility()
        let claudeOnly = ProviderVisibility(showsCodex: false, showsClaude: true)

        #expect(MenuBarSummaryMode.codexOnly.providers(in: both) == [.codex])
        #expect(MenuBarSummaryMode.codexOnly.providers(in: claudeOnly).isEmpty)
        #expect(MenuBarSummaryMode.claudeOnly.providers(in: both) == [.claude])
    }

    @Test("Icon-only mode has no text providers")
    func iconOnlyHasNoProviders() {
        #expect(MenuBarSummaryMode.iconOnly.providers(in: ProviderVisibility()).isEmpty)
    }
}
