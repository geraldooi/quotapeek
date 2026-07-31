import Testing
@testable import QuotaPeekCore

@Suite("Provider visibility")
struct ProviderVisibilityTests {
    @Test("Shows both providers by default")
    func showsBothProvidersByDefault() {
        let visibility = ProviderVisibility()

        #expect(visibility.visibleProviders == [.codex, .claude])
        #expect(visibility.subtitle == "Codex and Claude Code")
    }

    @Test("Supports showing only one provider")
    func supportsShowingOnlyOneProvider() {
        let codexOnly = ProviderVisibility(showsCodex: true, showsClaude: false)
        let claudeOnly = ProviderVisibility(showsCodex: false, showsClaude: true)

        #expect(codexOnly.visibleProviders == [.codex])
        #expect(codexOnly.subtitle == "Codex")
        #expect(claudeOnly.visibleProviders == [.claude])
        #expect(claudeOnly.subtitle == "Claude Code")
    }

    @Test("Keeps one provider visible")
    func keepsOneProviderVisible() {
        let codexOnly = ProviderVisibility(showsCodex: true, showsClaude: false)
        let unchanged = codexOnly.setting(.codex, isVisible: false)

        #expect(unchanged == codexOnly)
    }

    @Test("Repairs persisted settings that hide both providers")
    func repairsInvalidPersistedSettings() {
        let visibility = ProviderVisibility(showsCodex: false, showsClaude: false)

        #expect(visibility.visibleProviders == [.codex])
    }
}
