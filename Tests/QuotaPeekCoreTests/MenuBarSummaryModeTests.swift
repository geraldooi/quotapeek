import Testing
@testable import QuotaPeekCore

@Suite("Menu-bar summary mode")
struct MenuBarSummaryModeTests {
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
        #expect(MenuBarSummaryMode.iconOnly.fallbackText == nil)
    }

    @Test("Modes provide useful fallback text")
    func modesProvideFallbackText() {
        #expect(MenuBarSummaryMode.visibleProviders.fallbackText == "Tokens")
        #expect(MenuBarSummaryMode.codexOnly.fallbackText == "Codex")
        #expect(MenuBarSummaryMode.claudeOnly.fallbackText == "Claude")
    }
}
