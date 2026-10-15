import Foundation

public struct UsageStatusText: Equatable, Sendable {
    public let label: String
    public let help: String
    public let accessibilityLabel: String
}

public extension UsageSnapshot {
    func statusText(at now: Date = Date()) -> UsageStatusText {
        guard let freshness = claudeQuotaFreshness(at: now), let updatedAt else {
            let label: String = switch health {
            case .loading: "Loading"
            case .ready: "Working"
            case .inactive: "Inactive"
            case .limited: "Limited"
            case .needsAttention: "Needs attention"
            }
            let status = "\(provider.displayName) status: \(label)"
            return UsageStatusText(
                label: label,
                help: status,
                accessibilityLabel: status
            )
        }

        let age = UsageFormatting.age(since: updatedAt, now: now)
        let sourceLabel: String
        switch freshness {
        case .current:
            sourceLabel = source == .live ? "Live now" : "Captured now"
        case .unknown:
            sourceLabel = "Unknown age"
        case .aging, .stale:
            sourceLabel = source == .live ? "Live · \(age)" : age
        }
        let label = health == .limited ? "Limited · \(sourceLabel)" : sourceLabel
        let limitedText = health == .limited
            ? "Some Claude quota data may be unavailable or out of date. "
            : ""
        let help = source == .live
            ? "\(limitedText)Claude live limits checked \(age). Refresh QuotaPeek for current limits."
            : "\(limitedText)Claude quota captured \(age). Send a Claude Code message, then refresh QuotaPeek."
        let accessibilityLabel = source == .live
            ? "Claude Code live quota: \(label)"
            : "Claude Code quota capture: \(label)"
        return UsageStatusText(
            label: label,
            help: help,
            accessibilityLabel: accessibilityLabel
        )
    }
}
