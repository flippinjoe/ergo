import Foundation

/// One parsed log line from a pod stream. Splits an optional leading RFC-3339
/// timestamp (from `timestamps=true`) and classifies severity from the text.
struct LogLine: Identifiable, Sendable {
    let id = UUID()
    let time: String?
    let level: Level
    let message: String

    enum Level: Sendable, Equatable { case info, warn, error }

    init(raw: String) {
        var message = raw
        var time: String?
        if let space = raw.firstIndex(of: " "), raw[raw.startIndex..<space].contains("T") {
            time = Self.shortTime(String(raw[raw.startIndex..<space]))
            message = String(raw[raw.index(after: space)...])
        }
        self.time = time
        self.message = message

        let upper = message.uppercased()
        if upper.contains("ERROR") || upper.contains("FATAL") || upper.contains("PANIC") {
            level = .error
        } else if upper.contains("WARN") {
            level = .warn
        } else {
            level = .info
        }
    }

    /// "2026-07-23T09:41:13.201Z" → "09:41:13".
    private static func shortTime(_ rfc3339: String) -> String? {
        guard let t = rfc3339.firstIndex(of: "T") else { return nil }
        return String(rfc3339[rfc3339.index(after: t)...].prefix(8))
    }
}
