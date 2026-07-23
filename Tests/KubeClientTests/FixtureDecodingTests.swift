import Foundation
import KubeCore
import Testing

@testable import KubeClient

/// Proves the hermetic-fixture pattern is real: decode the bundled JSON
/// through `FakeClusterClient` and assert on the shapes. No cluster, no
/// network, no kubeconfig — the whole point.
@Suite("Fixture decoding")
struct FixtureDecodingTests {
    let client = FakeClusterClient()

    @Test("Pods decode with owner references and phases")
    func decodePods() async throws {
        let pods = try await client.listPods(namespace: nil)
        #expect(pods.count == 3)

        let web = try #require(pods.first { $0.metadata.name == "web-7d9f8c6b5-abcde" })
        #expect(web.status?.phase == "Running")
        // Pillar 1: the relationship link decodes.
        #expect(web.metadata.ownerReferences?.first?.kind == "ReplicaSet")
        #expect(web.metadata.ownerReferences?.first?.controller == true)
    }

    @Test("Namespace filtering is applied to fixtures")
    func namespaceFilter() async throws {
        let jobsPods = try await client.listPods(namespace: "jobs")
        #expect(jobsPods.count == 1)
        #expect(jobsPods.first?.metadata.name == "batch-runner")
    }

    @Test("Deployments decode with spec")
    func decodeDeployments() async throws {
        let deployments = try await client.listDeployments(namespace: "default")
        let web = try #require(deployments.first)
        #expect(web.metadata.name == "web")
        #expect(web.spec?.replicas == 2)
    }

    @Test("Events decode with involvedObject and ISO-8601 timestamps")
    func decodeEvents() async throws {
        let events = try await client.listEvents(namespace: nil)
        #expect(events.count == 2)

        let warning = try #require(events.first { $0.type == "Warning" })
        #expect(warning.reason == "FailedScheduling")
        #expect(warning.involvedObject.name == "batch-runner")
        // Pillar 1 (time): the timestamp parsed as a real Date.
        #expect(warning.lastTimestamp != nil)
    }

    @Test("CRD summaries decode with scope enum")
    func decodeCRDs() async throws {
        let crds = try await client.listCRDs()
        #expect(crds.count == 2)
        #expect(crds.contains { $0.kind == "ClusterIssuer" && $0.scope == .cluster })
    }

    @Test("The client boundary error type is a typed, comparable value")
    func typedError() {
        // The boundary defines a typed error so callers can branch on it
        // rather than inspecting strings.
        #expect(ClusterClientError.fixtureNotFound("x.json") == .fixtureNotFound("x.json"))
        #expect(ClusterClientError.fixtureNotFound("x.json") != .notImplemented)
    }
}
