import AppKit
import Combine
import Foundation
import QuotaPeekCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var codex = UsageSnapshot.loading(.codex)
    @Published private(set) var claude = UsageSnapshot.loading(.claude)
    @Published private(set) var codexResetForecast: CodexResetForecast?
    @Published private(set) var providerVisibility: ProviderVisibility
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastRefreshWasManual = false

    private var timer: AnyCancellable?
    private var forecastRefreshAfter = Date.distantPast
    private let defaults: UserDefaults

    private enum PreferenceKey {
        static let showsCodex = "providerVisibility.codex"
        static let showsClaude = "providerVisibility.claude"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        providerVisibility = ProviderVisibility(
            showsCodex: defaults.object(forKey: PreferenceKey.showsCodex) as? Bool ?? true,
            showsClaude: defaults.object(forKey: PreferenceKey.showsClaude) as? Bool ?? true
        )
        refresh(announcesCompletion: false)
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh(announcesCompletion: false)
            }
    }

    var menuBarText: String {
        var parts: [String] = []
        if providerVisibility.showsCodex {
            if let used = codex.windows.first?.usedPercent {
                parts.append("C \(Int(used.rounded()))%")
            } else if let tokens = codex.windows.first?.tokens {
                parts.append("C \(UsageFormatting.tokens(tokens))")
            }
        }
        if providerVisibility.showsClaude, let tokens = claude.windows.first?.tokens {
            parts.append("A \(UsageFormatting.tokens(tokens))")
        }
        return parts.isEmpty ? "Tokens" : parts.joined(separator: " · ")
    }

    var visibleSnapshots: [UsageSnapshot] {
        providerVisibility.visibleProviders.map { provider in
            provider == .codex ? codex : claude
        }
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
            if lastRefreshWasManual {
                return "Usage refreshed"
            }
            let hasInactiveSource = visibleSnapshots.contains { $0.health == .inactive }
            return hasInactiveSource ? "Usage sources checked" : "All usage sources are working"
        case 1:
            return lastRefreshWasManual
                ? "Refreshed · 1 usage source needs attention"
                : "1 usage source needs attention"
        default:
            return lastRefreshWasManual
                ? "Refreshed · \(attentionCount) usage sources need attention"
                : "\(attentionCount) usage sources need attention"
        }
    }

    func refresh(announcesCompletion: Bool = true) {
        guard !isRefreshing else { return }
        isRefreshing = true
        let visibility = providerVisibility
        let shouldRefreshForecast = Date() >= forecastRefreshAfter

        Task {
            let forecastTask = visibility.showsCodex && shouldRefreshForecast
                ? Task.detached(priority: .utility) {
                    await CodexResetForecastReader().load()
                }
                : nil
            let result = await Task.detached(priority: .utility) {
                (
                    visibility.showsCodex ? CodexUsageReader().load() : nil,
                    visibility.showsClaude ? ClaudeUsageReader().load() : nil
                )
            }.value

            if let codexSnapshot = result.0 {
                codex = codexSnapshot
            }
            if let claudeSnapshot = result.1 {
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

    func setProvider(_ provider: Provider, isVisible: Bool) {
        let previous = providerVisibility
        let updated = providerVisibility.setting(provider, isVisible: isVisible)
        guard updated != previous else { return }

        providerVisibility = updated
        defaults.set(updated.showsCodex, forKey: PreferenceKey.showsCodex)
        defaults.set(updated.showsClaude, forKey: PreferenceKey.showsClaude)

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
