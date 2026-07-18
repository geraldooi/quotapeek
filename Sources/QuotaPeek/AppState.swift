import AppKit
import Combine
import Foundation
import QuotaPeekCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var codex = UsageSnapshot.unavailable(.codex, message: "Loading…")
    @Published private(set) var claude = UsageSnapshot.unavailable(.claude, message: "Loading…")
    @Published private(set) var codexResetForecast: CodexResetForecast?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private var timer: AnyCancellable?
    private var forecastRefreshAfter = Date.distantPast

    init() {
        refresh()
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    var menuBarText: String {
        var parts: [String] = []
        if let used = codex.windows.first?.usedPercent {
            parts.append("C \(Int(used.rounded()))%")
        }
        if let tokens = claude.windows.first?.tokens {
            parts.append("A \(UsageFormatting.tokens(tokens))")
        }
        return parts.isEmpty ? "Tokens" : parts.joined(separator: " · ")
    }

    func refresh() {
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
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
