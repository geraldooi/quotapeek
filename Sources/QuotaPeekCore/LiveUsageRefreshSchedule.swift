import Foundation

public enum LiveUsageRefreshSchedule {
    /// Allows the one-minute UI timer a full tick to start a new read before
    /// a five-minute Claude snapshot is labeled stale.
    public static func nextRead(after startedAt: Date) -> Date {
        startedAt.addingTimeInterval(3 * 60 + 30)
    }

    public static func shouldRead(
        at now: Date,
        deadline: Date,
        manuallyRequested: Bool = false,
        retryAfter: Date? = nil
    ) -> Bool {
        guard retryAfter.map({ now >= $0 }) ?? true else { return false }
        return manuallyRequested || now >= deadline
    }
}
