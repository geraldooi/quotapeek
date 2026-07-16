import Foundation

enum UsageFormatting {
    static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func tokens(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(count) / 1_000)
        default:
            return integer.string(from: NSNumber(value: count)) ?? "\(count)"
        }
    }

    static func percent(_ value: Double) -> String {
        value.rounded() == value
            ? "\(Int(value))%"
            : String(format: "%.1f%%", value)
    }

    static func reset(_ date: Date, now: Date = Date()) -> String {
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
