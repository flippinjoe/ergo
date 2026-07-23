import Foundation
import KubeCore
import Testing

@testable import KubeClient

@Suite("Cluster stores")
struct ClusterStoreTests {
    private func sample(_ name: String) -> ClusterConnection {
        ClusterConnection(
            displayName: name,
            source: .azure(
                AzureClusterRef(
                    resourceID:
                        "/subscriptions/s/resourceGroups/g/providers/Microsoft.ContainerService/managedClusters/\(name)",
                    subscriptionID: "s",
                    resourceGroup: "g",
                    clusterName: name
                )),
            addedAt: Date(timeIntervalSince1970: 1_000_000_000)
        )
    }

    @Test("In-memory store round-trips connections")
    func inMemoryRoundTrip() async throws {
        let store = InMemoryClusterStore()
        #expect(try await store.load().isEmpty)

        try await store.save([sample("a"), sample("b")])
        let loaded = try await store.load()
        #expect(loaded.map(\.displayName) == ["a", "b"])
    }

    @Test("File store writes and reads JSON on disk")
    func fileRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ergo-test-\(UUID().uuidString)")
        let store = FileClusterStore(url: dir.appendingPathComponent("clusters.json"))
        defer { try? FileManager.default.removeItem(at: dir) }

        // Missing file loads as empty, not an error.
        #expect(try await store.load().isEmpty)

        let connection = sample("prod")
        try await store.save([connection])

        let loaded = try await store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first == connection)
        // The source's associated value survives the round-trip.
        #expect(loaded.first?.source.kind == .azure)
    }

    @Test("ClusterSource encodes each case distinctly")
    func sourceCodable() throws {
        let cases: [ClusterSource] = [
            .azure(
                AzureClusterRef(resourceID: "r", subscriptionID: "s", resourceGroup: "g", clusterName: "c")),
            .kubeconfig(KubeconfigRef(path: "/tmp/kubeconfig", contextName: "ctx")),
            .mock,
        ]
        for source in cases {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(ClusterSource.self, from: data)
            #expect(decoded == source)
        }
    }
}
