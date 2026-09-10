import AppKit
import Combine
import Foundation
import QuotaPeekCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var codex = UsageSnapshot.loading(.codex)
    @Published private(set) var claude = UsageSnapshot.loading(.claude)
    @Published private(set) var codexResetForecast: CodexResetForecast?
    @Published private(set) var availableUpdate: AppRelease?
    @Published private(set) var providerVisibility: ProviderVisibility
    @Published private(set) var menuBarSummaryMode: MenuBarSummaryMode
    @Published private(set) var isClaudeQuotaIntegrationEnabled: Bool
    @Published private(set) var claudeQuotaIntegrationError: String?
    @Published private(set) var claudeQuotaRetryTarget: Bool?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastRefreshWasManual = false

    private var timer: AnyCancellable?
    private var forecastRefreshAfter = Date.distantPast
    private var releaseRefreshAfter = Date.distantPast
    private let defaults: UserDefaults
    private let claudeIntegration: ClaudeStatusLineIntegration

    private enum PreferenceKey {
        static let showsCodex = "providerVisibility.codex"
        static let showsClaude = "providerVisibility.claude"
        static let menuBarSummaryMode = "menuBarSummaryMode"
    }

    init(
        defaults: UserDefaults = .standard,
        claudeIntegration: ClaudeStatusLineIntegration = .currentUser
    ) {
        self.defaults = defaults
        self.claudeIntegration = claudeIntegration
        isClaudeQuotaIntegrationEnabled = claudeIntegration.isInstalled
        providerVisibility = ProviderVisibility(
            showsCodex: defaults.object(forKey: PreferenceKey.showsCodex) as? Bool ?? true,
            showsClaude: defaults.object(forKey: PreferenceKey.showsClaude) as? Bool ?? true
        )
        menuBarSummaryMode = defaults.string(forKey: PreferenceKey.menuBarSummaryMode)
            .flatMap(MenuBarSummaryMode.init(rawValue:))
            ?? .visibleProviders
        if menuBarSummaryMode != .iconOnly,
           menuBarSummaryMode.providers(in: providerVisibility).isEmpty {
            menuBarSummaryMode = .visibleProviders
            defaults.set(
                MenuBarSummaryMode.visibleProviders.rawValue,
                forKey: PreferenceKey.menuBarSummaryMode
            )
        }
        refresh(announcesCompletion: false)
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh(announcesCompletion: false)
            }
        refreshBundledClaudeBridgeIfNeeded()
    }

    var menuBarItems: [MenuBarSummaryItem] {
        menuBarSummaryMode.summaryItems(
            visibility: providerVisibility,
            codex: codex,
            claude: claude
        )
    }

    var visibleSnapshots: [UsageSnapshot] {
        providerVisibility.visibleProviders.map { provider in
            provider == .codex ? codex : claude
        }
    }

    var hasStaleClaudeQuota: Bool {
        providerVisibility.showsClaude
            && claude.claudeQuotaFreshness() == .stale
    }

    var refreshSummary: String {
        if isRefreshing {
            return "Refreshing local usage…"
        }
        guard lastRefresh != nil else {
            return "Checking local usage…"
        }

        let attentionCount = visibleSnapshots.filter(\.needsAttention).count
        switch attentionCount {
        case 0:
            if hasStaleClaudeQuota {
                return "Claude quota may be out of date"
            }
            let hasInactiveSource = visibleSnapshots.contains { $0.health == .inactive }
            if lastRefreshWasManual || hasInactiveSource {
                return "Usage sources checked"
            }
            return "All usage sources are working"
        case 1:
            return lastRefreshWasManual
                ? "Checked · 1 usage source needs attention"
                : "1 usage source needs attention"
        default:
            return lastRefreshWasManual
                ? "Checked · \(attentionCount) usage sources need attention"
                : "\(attentionCount) usage sources need attention"
        }
    }

    func refresh(announcesCompletion: Bool = true) {
        guard !isRefreshing else { return }
        isRefreshing = true
        let visibility = providerVisibility
        let claudeIntegrationEnabled = isClaudeQuotaIntegrationEnabled
        let claudeCacheURL = claudeIntegration.paths.cacheURL
        let shouldRefreshForecast = Date() >= forecastRefreshAfter
        let currentVersion = AppVersion.current
        let shouldRefreshRelease = currentVersion != nil && Date() >= releaseRefreshAfter

        if shouldRefreshRelease, let currentVersion {
            refreshRelease(currentVersion: currentVersion)
        }

        Task {
            let forecastTask = visibility.showsCodex && shouldRefreshForecast
                ? Task.detached(priority: .utility) {
                    await CodexResetForecastReader().load()
                }
                : nil
            let result = await Task.detached(priority: .utility) {
                (
                    visibility.showsCodex ? CodexUsageReader().load() : nil,
                    visibility.showsClaude
                        ? ClaudeQuotaReader(
                            cacheURL: claudeCacheURL,
                            integrationEnabled: claudeIntegrationEnabled
                        ).load()
                        : nil
                )
            }.value

            if let codexSnapshot = result.0 {
                codex = codexSnapshot
            }
            if let claudeSnapshot = result.1,
               claudeIntegrationEnabled == isClaudeQuotaIntegrationEnabled,
               claudeQuotaRetryTarget == nil {
                claude = claudeSnapshot
            }

            if let forecastTask {
                if let forecast = await forecastTask.value {
                    codexResetForecast = forecast
                    let now = Date()
                    forecastRefreshAfter = min(
                        max(
                            forecast.nextRefreshAt ?? now.addingTimeInterval(30 * 60),
                            now.addingTimeInterval(60)
                        ),
                        now.addingTimeInterval(60 * 60)
                    )
                } else {
                    forecastRefreshAfter = Date().addingTimeInterval(5 * 60)
                    if let current = codexResetForecast,
                       Date().timeIntervalSince(current.fetchedAt) > 2 * 60 * 60 {
                        codexResetForecast = nil
                    }
                }
            }

            lastRefresh = Date()
            isRefreshing = false
            lastRefreshWasManual = announcesCompletion
            if announcesCompletion {
                announceRefreshCompletion()
            }
        }
    }

    private func refreshRelease(currentVersion: String) {
        releaseRefreshAfter = Date().addingTimeInterval(30 * 60)

        Task {
            let release = await Task.detached(priority: .utility) {
                await AppReleaseReader().load()
            }.value
            guard let release else { return }

            availableUpdate = release.isNewer(than: currentVersion) ? release : nil
            releaseRefreshAfter = Date().addingTimeInterval(6 * 60 * 60)
        }
    }

    func setProvider(_ provider: Provider, isVisible: Bool) {
        let previous = providerVisibility
        let updated = providerVisibility.setting(provider, isVisible: isVisible)
        guard updated != previous else { return }

        providerVisibility = updated
        defaults.set(updated.showsCodex, forKey: PreferenceKey.showsCodex)
        defaults.set(updated.showsClaude, forKey: PreferenceKey.showsClaude)

        if !isMenuBarSummaryModeAvailable(menuBarSummaryMode) {
            setMenuBarSummaryMode(.visibleProviders)
        }

        if !previous.showsCodex, updated.showsCodex {
            codex = .loading(.codex)
        }
        if !previous.showsClaude, updated.showsClaude {
            claude = .loading(.claude)
        }
        if !updated.showsCodex {
            codexResetForecast = nil
            forecastRefreshAfter = .distantPast
        }
        refresh(announcesCompletion: false)
    }

    func isMenuBarSummaryModeAvailable(_ mode: MenuBarSummaryMode) -> Bool {
        mode == .iconOnly || !mode.providers(in: providerVisibility).isEmpty
    }

    func setMenuBarSummaryMode(_ mode: MenuBarSummaryMode) {
        guard isMenuBarSummaryModeAvailable(mode), mode != menuBarSummaryMode else { return }

        menuBarSummaryMode = mode
        defaults.set(mode.rawValue, forKey: PreferenceKey.menuBarSummaryMode)
    }

    func setClaudeQuotaIntegrationEnabled(_ isEnabled: Bool) {
        guard isEnabled != isClaudeQuotaIntegrationEnabled
            || claudeQuotaRetryTarget == isEnabled
        else {
            return
        }
        claudeQuotaIntegrationError = nil
        claudeQuotaRetryTarget = nil

        do {
            if isEnabled {
                guard let helperURL = bundledClaudeBridgeURL else {
                    throw ClaudeQuotaIntegrationError.helperMissing
                }
                try claudeIntegration.install(helperSourceURL: helperURL)
            } else {
                try claudeIntegration.uninstall()
            }
            isClaudeQuotaIntegrationEnabled = claudeIntegration.isInstalled
            claudeQuotaRetryTarget = nil
            claude = ClaudeQuotaReader(
                cacheURL: claudeIntegration.paths.cacheURL,
                integrationEnabled: isClaudeQuotaIntegrationEnabled
            ).load()
            refresh(announcesCompletion: false)
        } catch {
            isClaudeQuotaIntegrationEnabled = claudeIntegration.isInstalled
            claudeQuotaIntegrationError = error.localizedDescription
            claudeQuotaRetryTarget = isEnabled
            let action = isEnabled ? "enabled" : "disabled"
            claude = UsageSnapshot(
                provider: .claude,
                health: .needsAttention,
                issue: UsageIssue(
                    kind: .readError,
                    title: "Claude quota bars could not be \(action)",
                    message: error.localizedDescription,
                    recoverySuggestion: "Check Claude Code settings, then try again."
                )
            )
        }
    }

    private func refreshBundledClaudeBridgeIfNeeded() {
        guard
            isClaudeQuotaIntegrationEnabled,
            let helperURL = bundledClaudeBridgeURL
        else {
            return
        }
        do {
            try claudeIntegration.install(helperSourceURL: helperURL)
        } catch {
            claudeQuotaIntegrationError = error.localizedDescription
        }
    }

    private var bundledClaudeBridgeURL: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/QuotaPeekClaudeBridge")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private func announceRefreshCompletion() {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: refreshSummary,
                .priority: NSNumber(value: NSAccessibilityPriorityLevel.medium.rawValue)
            ]
        )
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private enum ClaudeQuotaIntegrationError: LocalizedError {
    case helperMissing

    var errorDescription: String? {
        "QuotaPeek could not find its Claude quota helper. Reinstall the app and try again."
    }
}
