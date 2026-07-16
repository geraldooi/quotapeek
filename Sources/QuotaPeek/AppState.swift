import AppKit
import Combine
import Foundation
import QuotaPeekCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var codex = UsageSnapshot.unavailable(.codex, message: "Loading…")
    @Published private(set) var claude = UsageSnapshot.unavailable(.claude, message: "Loading…")
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private var timer: AnyCancellable?

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

        Task {
            let result = await Task.detached(priority: .utility) {
                (
                    CodexUsageReader().load(),
                    ClaudeUsageReader().load()
                )
            }.value

            codex = result.0
            claude = result.1
            lastRefresh = Date()
            isRefreshing = false
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
