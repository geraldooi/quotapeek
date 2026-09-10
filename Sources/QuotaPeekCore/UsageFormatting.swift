import Foundation

public enum UsageFormatting {
    private static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    public static func tokens(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...:
            String(format: "%.1fK", Double(count) / 1_000)
        default:
            integer.string(from: NSNumber(value: count)) ?? "\(count)"
        }
    }

    public static func percent(_ value: Double) -> String {
        value.rounded() == value
            ? "\(Int(value))%"
            : String(format: "%.1f%%", value)
    }

    public static func age(since date: Date, now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed.isFinite else { return "unknown age" }
        if elapsed <= 0 { return "now" }
        guard elapsed <= Double(Int.max) else { return "very old" }

        let seconds = Int(elapsed)
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m old" }
        if seconds < 86_400 { return "\(seconds / 3_600)h old" }
        return "\(seconds / 86_400)d old"
    }

    public static func reset(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds < 60 {
            return "resets in <1m"
        }
        if seconds < 3_600 {
            return "resets in \(seconds / 60)m"
        }
        if seconds < 86_400 {
            return "resets in \(seconds / 3_600)h \((seconds % 3_600) / 60)m"
        }
        return "resets in \(seconds / 86_400)d \((seconds % 86_400) / 3_600)h"
    }
}
