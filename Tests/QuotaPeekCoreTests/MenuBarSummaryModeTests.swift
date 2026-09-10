import Testing
@testable import QuotaPeekCore

@Suite("Menu-bar summary mode")
struct MenuBarSummaryModeTests {
    @Test("Codex-only summary uses weekly usage")
    func codexOnlyUsesWeeklyUsage() {
        let codex = UsageSnapshot(
            provider: .codex,
            windows: [
                UsageWindow(kind: .fiveHour, label: "5 hours", usedPercent: 28),
                UsageWindow(kind: .weekly, label: "7 days", usedPercent: 9)
            ]
        )

        #expect(
            MenuBarSummaryMode.codexOnly.summaryItems(
                visibility: ProviderVisibility(showsCodex: true, showsClaude: false),
                codex: codex,
                claude: .loading(.claude)
            ) == [MenuBarSummaryItem(provider: .codex, value: .percent(9))]
        )
        #expect(MenuBarSummaryValue.percent(9).displayText == "9%")
        #expect(MenuBarSummaryValue.percent(9).accessibilityText == "9 percent used")
    }

    @Test("Displays every visible provider, including inactive providers")
    func displaysEveryVisibleProvider() {
        let codex = UsageSnapshot(
            provider: .codex,
            windows: [UsageWindow(kind: .weekly, label: "7 days", usedPercent: 69)]
        )
        let claude = UsageSnapshot(provider: .claude, health: .inactive)

        #expect(
            MenuBarSummaryMode.visibleProviders.summaryItems(
                visibility: ProviderVisibility(),
                codex: codex,
                claude: claude
            ) == [
                MenuBarSummaryItem(provider: .codex, value: .percent(69)),
                MenuBarSummaryItem(provider: .claude, value: .unavailable)
            ]
        )
        #expect(
            MenuBarSummaryMode.codexOnly.summaryItems(
                visibility: ProviderVisibility(),
                codex: codex,
                claude: claude
            ) == [MenuBarSummaryItem(provider: .codex, value: .percent(69))]
        )
        #expect(
            MenuBarSummaryMode.claudeOnly.summaryItems(
                visibility: ProviderVisibility(),
                codex: codex,
                claude: claude
            ) == [MenuBarSummaryItem(provider: .claude, value: .unavailable)]
        )
        #expect(
            MenuBarSummaryMode.iconOnly.summaryItems(
                visibility: ProviderVisibility(),
                codex: codex,
                claude: claude
            ).isEmpty
        )
        #expect(MenuBarSummaryValue.unavailable.accessibilityText == "usage unavailable")
    }

    @Test("Formats every menu-bar mode distinctly")
    func formatsEveryModeDistinctly() {
        let visibility = ProviderVisibility()
        let codex = UsageSnapshot(
            provider: .codex,
            windows: [
                UsageWindow(kind: .fiveHour, label: "5 hours", usedPercent: 28),
                UsageWindow(kind: .weekly, label: "7 days", usedPercent: 69)
            ]
        )
        let claude = UsageSnapshot(
            provider: .claude,
            windows: [
                UsageWindow(kind: .fiveHour, label: "5 hours", usedPercent: 41),
                UsageWindow(kind: .weekly, label: "Weekly", usedPercent: 22)
            ]
        )

        #expect(
            MenuBarSummaryMode.visibleProviders.summaryItems(
                visibility: visibility,
                codex: codex,
                claude: claude
            ) == [
                MenuBarSummaryItem(provider: .codex, value: .percent(69)),
                MenuBarSummaryItem(provider: .claude, value: .percent(22))
            ]
        )
        #expect(
            MenuBarSummaryMode.codexOnly.summaryItems(
                visibility: visibility,
                codex: codex,
                claude: claude
            ) == [MenuBarSummaryItem(provider: .codex, value: .percent(69))]
        )
        #expect(
            MenuBarSummaryMode.claudeOnly.summaryItems(
                visibility: visibility,
                codex: codex,
                claude: claude
            ) == [MenuBarSummaryItem(provider: .claude, value: .percent(22))]
        )
        #expect(
            MenuBarSummaryMode.iconOnly.summaryItems(
                visibility: visibility,
                codex: codex,
                claude: claude
            ).isEmpty
        )
    }

    @Test("Does not substitute session usage when weekly usage is unavailable")
    func doesNotSubstituteSessionUsage() {
        let codex = UsageSnapshot(
            provider: .codex,
            windows: [UsageWindow(label: "5 hours", usedPercent: 28)]
        )
        let claude = UsageSnapshot(
            provider: .claude,
            windows: [UsageWindow(label: "5 hours", usedPercent: 41)]
        )

        #expect(
            MenuBarSummaryMode.visibleProviders.summaryItems(
                visibility: ProviderVisibility(),
                codex: codex,
                claude: claude
            ) == [
                MenuBarSummaryItem(provider: .codex, value: .unavailable),
                MenuBarSummaryItem(provider: .claude, value: .unavailable)
            ]
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
