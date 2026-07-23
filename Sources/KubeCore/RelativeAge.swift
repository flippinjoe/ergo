import Foundation

/// Compact, `kubectl`-style age strings ("3m", "2h", "14d", "1y"). Pure and
/// deterministic: pass the reference instant in, so it's unit-testable without
/// touching the wall clock.
public enum RelativeAge {
    /// Formats the interval between `date` and `now` the way `kubectl` shows
    /// the AGE column: the single largest unit, floored. Future dates and the
    /// present both render as `"0s"`.
    public static func string(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        guard seconds > 0 else { return "0s" }

        let minute = 60, hour = 3600, day = 86_400, year = 365 * 86_400
        switch seconds {
        case year...:
            return "\(seconds / year)y"
        case day...:
            return "\(seconds / day)d"
        case hour...:
            return "\(seconds / hour)h"
        case minute...:
            return "\(seconds / minute)m"
        default:
            return "\(seconds)s"
        }
    }
}

extension ObjectMeta {
    /// The object's age at `now`, or `nil` if it has no creation timestamp.
    public func age(now: Date) -> String? {
        creationTimestamp.map { RelativeAge.string(from: $0, now: now) }
    }
}
