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

    @Test("Pods decode with node, restarts, and owner references")
    func decodePods() async throws {
        let pods = try await client.listPods(namespace: nil)
        #expect(pods.count == 8)

        let cert = try #require(pods.first { $0.metadata.name.hasPrefix("cert-manager") })
        #expect(cert.spec?.nodeName == "ip-10-0-3-91")
        #expect(cert.restartCount == 0)
        // Pillar 1: the relationship link decodes.
        #expect(cert.metadata.ownerReferences?.first?.kind == "ReplicaSet")
        #expect(cert.metadata.ownerReferences?.first?.controller == true)
    }

    @Test("A crash-looping container surfaces its waiting reason and restarts")
    func crashLoopStatus() async throws {
        let pods = try await client.listPods(namespace: "argocd")
        let argo = try #require(pods.first)
        #expect(argo.restartCount == 7)
        #expect(argo.displayStatus == "CrashLoopBackOff")
        #expect(argo.health == .error)
    }

    @Test("A pending, unscheduled pod has no node and reads as a warning")
    func pendingPod() async throws {
        let pods = try await client.listPods(namespace: "redis")
        let redis = try #require(pods.first)
        #expect(redis.spec?.nodeName == nil)
        #expect(redis.displayStatus == "Pending")
        #expect(redis.health == .warning)
    }

    @Test("Namespace filtering is applied to fixtures")
    func namespaceFilter() async throws {
        let monitoring = try await client.listPods(namespace: "monitoring")
        #expect(monitoring.count == 2)
        #expect(monitoring.allSatisfy { $0.metadata.namespace == "monitoring" })
    }

    @Test("Deployments decode with spec")
    func decodeDeployments() async throws {
        let deployments = try await client.listDeployments(namespace: "argocd")
        let repo = try #require(deployments.first)
        #expect(repo.metadata.name == "argocd-repo-server")
        #expect(repo.spec?.replicas == 2)
    }

    @Test("StatefulSets decode with ready/desired and health")
    func decodeStatefulSets() async throws {
        let sets = try await client.listStatefulSets(namespace: nil)
        #expect(sets.count == 2)

        let redis = try #require(sets.first { $0.metadata.name == "redis-master" })
        #expect(redis.readyText == "0/1")
        #expect(redis.health == .warning)  // not all replicas ready

        let prom = try #require(sets.first { $0.metadata.name == "prometheus-k8s" })
        #expect(prom.readyText == "2/2")
        #expect(prom.health == .ok)
    }

    @Test("Namespaces are derived from the fixtures")
    func namespaces() async throws {
        let namespaces = try await client.listNamespaces()
        #expect(namespaces.contains("monitoring"))
        #expect(namespaces.contains("cert-manager"))
        // Sorted, deduped.
        #expect(namespaces == namespaces.sorted())
        #expect(Set(namespaces).count == namespaces.count)
    }

    @Test("Watch yields a snapshot of raw objects from the fixtures")
    func watchSnapshot() async throws {
        let gvr = GroupVersionResource(group: "", version: "v1", resource: "pods", namespaced: true)
        var snapshot: [ResourceObject] = []
        for try await objects in client.watch(gvr, namespace: nil) {
            snapshot = objects
            break
        }
        #expect(snapshot.count == 8)
        // Each object is decodable back into a Pod.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let pod = try #require(snapshot.first.map { try decoder.decode(Pod.self, from: $0.data) })
        #expect(!pod.metadata.name.isEmpty)
    }

    @Test("Events decode with involvedObject and ISO-8601 timestamps")
    func decodeEvents() async throws {
        let events = try await client.listEvents(namespace: nil)
        #expect(events.count == 3)

        let backoff = try #require(events.first { $0.reason == "BackOff" })
        #expect(backoff.type == "Warning")
        #expect(backoff.involvedObject.name == "argocd-repo-server-5f7b-jc9wd")
        // Pillar 1 (time): the timestamp parsed as a real Date.
        #expect(backoff.lastTimestamp != nil)
    }

    @Test("CRD summaries decode with scope enum")
    func decodeCRDs() async throws {
        let crds = try await client.listCRDs()
        #expect(crds.count == 2)
        #expect(crds.contains { $0.kind == "ClusterIssuer" && $0.scope == .cluster })
    }

    @Test("The client boundary error type is a typed, comparable value")
    func typedError() {
        #expect(ClusterClientError.fixtureNotFound("x.json") == .fixtureNotFound("x.json"))
        #expect(ClusterClientError.fixtureNotFound("x.json") != .notImplemented)
    }
}
