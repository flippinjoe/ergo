import Testing

@testable import KubeUI

@Suite("Log line parsing")
struct LogLineTests {
    @Test("Splits an RFC-3339 timestamp into a short time")
    func timestamp() {
        let line = LogLine(raw: "2026-07-23T09:41:13.201Z INFO starting up")
        #expect(line.time == "09:41:13")
        #expect(line.message == "INFO starting up")
    }

    @Test("Classifies severity from the message")
    func levels() {
        #expect(LogLine(raw: "2026-07-23T09:41:13Z ERROR boom").level == .error)
        #expect(LogLine(raw: "2026-07-23T09:41:13Z WARN careful").level == .warn)
        #expect(LogLine(raw: "2026-07-23T09:41:13Z hello").level == .info)
        #expect(LogLine(raw: "plain line, no timestamp").level == .info)
    }

    @Test("A line without a timestamp keeps the whole message")
    func noTimestamp() {
        let line = LogLine(raw: "just a message")
        #expect(line.time == nil)
        #expect(line.message == "just a message")
    }
}
