import Foundation

public enum LiveUsageFallback {
    public static func select(
        live: UsageSnapshot,
        local: UsageSnapshot,
        now: Date = Date()
    ) -> UsageSnapshot {
        guard live.provider == local.provider else { return live }
        if live.isAvailable, !live.windows.isEmpty {
            return live
        }

        let validLocalWindows = local.windows.filter { window in
            guard let percent = window.usedPercent,
                  percent.isFinite,
                  (0...100).contains(percent) else {
                return false
            }
            return window.resetAt.map { $0 > now } ?? false
        }
        guard local.isAvailable, !validLocalWindows.isEmpty else { return live }

        let issue = UsageIssue(
            kind: .quotaLimitsUnavailable,
            title: "Live \(live.provider.displayName) limits unavailable",
            message: "Showing the last locally captured quota. It may not include usage from another device.",
            recoverySuggestion: "Check your provider sign-in and network connection, then refresh."
        )
        return UsageSnapshot(
            provider: local.provider,
            source: local.source,
            health: .limited,
            issue: issue,
            diagnostics: local.diagnostics,
            tokens: local.tokens,
            contextWindow: local.contextWindow,
            windows: validLocalWindows,
            updatedAt: local.updatedAt
        )
    }
}
