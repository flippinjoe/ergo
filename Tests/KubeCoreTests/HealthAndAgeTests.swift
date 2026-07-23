import Foundation
import Testing

@testable import KubeCore

@Suite("HealthStatus mapping")
struct HealthStatusTests {
    @Test("Running-family statuses are ok")
    func okStatuses() {
        for s in ["Running", "Succeeded", "Synced", "Healthy"] {
            #expect(HealthStatus(kubernetesStatus: s) == .ok)
        }
    }

    @Test("Transient statuses are warnings")
    func warningStatuses() {
        for s in ["Pending", "ContainerCreating", "Terminating"] {
            #expect(HealthStatus(kubernetesStatus: s) == .warning)
        }
    }

    @Test("Failure statuses are errors")
    func errorStatuses() {
        for s in ["CrashLoopBackOff", "ImagePullBackOff", "Failed", "OOMKilled"] {
            #expect(HealthStatus(kubernetesStatus: s) == .error)
        }
    }

    @Test("Unrecognized statuses fall through to unknown, not a guess")
    func unknownStatus() {
        #expect(HealthStatus(kubernetesStatus: "SomethingNovel") == .unknown)
    }
}

@Suite("RelativeAge formatting")
struct RelativeAgeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func age(secondsAgo: Int) -> String {
        RelativeAge.string(from: now.addingTimeInterval(-Double(secondsAgo)), now: now)
    }

    @Test("Picks the single largest unit, kubectl-style")
    func units() {
        #expect(age(secondsAgo: 45) == "45s")
        #expect(age(secondsAgo: 3 * 60) == "3m")
        #expect(age(secondsAgo: 2 * 3600) == "2h")
        #expect(age(secondsAgo: 14 * 86_400) == "14d")
        #expect(age(secondsAgo: 400 * 86_400) == "1y")
    }

    @Test("Present and future both render as 0s")
    func nonPositive() {
        #expect(RelativeAge.string(from: now, now: now) == "0s")
        #expect(RelativeAge.string(from: now.addingTimeInterval(60), now: now) == "0s")
    }

    @Test("ObjectMeta.age uses its creation timestamp")
    func objectMetaAge() {
        let meta = ObjectMeta(name: "x", creationTimestamp: now.addingTimeInterval(-86_400))
        #expect(meta.age(now: now) == "1d")
        #expect(ObjectMeta(name: "y").age(now: now) == nil)
    }
}
