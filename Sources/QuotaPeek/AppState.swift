import AppKit
import Combine
import Foundation
import QuotaPeekCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var codex = UsageSnapshot.loading(.codex)
    @Published private(set) var claude = UsageSnapshot.loading(.claude)
    @Published private(set) var codexResetForecast: CodexResetForecast?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastRefreshWasManual = false

    private var timer: AnyCancellable?
    private var forecastRefreshAfter = Date.distantPast

    init() {
        refresh(announcesCompletion: false)
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh(announcesCompletion: false)
            }
    }

    var menuBarText: String {
        var parts: [String] = []
        if let used = codex.windows.first?.usedPercent {
            parts.append("C \(Int(used.rounded()))%")
        } else if let tokens = codex.windows.first?.tokens {
            parts.append("C \(UsageFormatting.tokens(tokens))")
        }
        if let tokens = claude.windows.first?.tokens {
            parts.append("A \(UsageFormatting.tokens(tokens))")
        }
        return parts.isEmpty ? "Tokens" : parts.joined(separator: " · ")
    }

    var refreshSummary: String {
        if isRefreshing {
            return "Refreshing local usage…"
        }
        guard lastRefresh != nil else {
            return "Checking local usage…"
        }

        let attentionCount = [codex, claude].filter(\.needsAttention).count
        switch attentionCount {
        case 0:
            return lastRefreshWasManual ? "Usage refreshed" : "All usage sources are working"
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
        let shouldRefreshForecast = Date() >= forecastRefreshAfter

        Task {
            let forecastTask = shouldRefreshForecast
                ? Task.detached(priority: .utility) {
                    await CodexResetForecastReader().load()
                }
                : nil
            let result = await Task.detached(priority: .utility) {
                (
                    CodexUsageReader().load(),
                    ClaudeUsageReader().load()
                )
            }.value

            codex = result.0
            claude = result.1

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
