import Foundation
import KubeClient
import KubeCore
import Observation

/// Owns the set of saved clusters: load, add, remove, select — persisted
/// through the injected `ClusterStore`. `@MainActor` because it feeds SwiftUI.
///
/// On first run (empty store) it seeds one sample connection so the explorer
/// has something to show before the user adds a real cluster.
@MainActor
@Observable
public final class ClustersModel {
    public private(set) var connections: [ClusterConnection] = []
    public var selectedID: ClusterConnection.ID?

    private let store: any ClusterStore
    /// Exposed so the add-cluster flow can drive discovery with the same service.
    public let azure: any AzureClusterService

    public init(store: any ClusterStore, azure: any AzureClusterService) {
        self.store = store
        self.azure = azure
    }

    public var selected: ClusterConnection? {
        connections.first { $0.id == selectedID }
    }

    public func load() async {
        var loaded = (try? await store.load()) ?? []
        if loaded.isEmpty {
            loaded = [Self.sampleConnection()]
            try? await store.save(loaded)
        }
        connections = loaded
        if selectedID == nil || !connections.contains(where: { $0.id == selectedID }) {
            selectedID = connections.first?.id
        }
    }

    /// Adds connections, skipping any whose target is already saved. Selects the
    /// last newly-added one.
    public func add(_ incoming: [ClusterConnection]) async {
        let existing = Set(connections.map(\.source.identityKey))
        let fresh = incoming.filter { !existing.contains($0.source.identityKey) }
        guard !fresh.isEmpty else { return }
        connections.append(contentsOf: fresh)
        selectedID = fresh.last?.id
        await persist()
    }

    public func remove(_ connection: ClusterConnection) async {
        connections.removeAll { $0.id == connection.id }
        if selectedID == connection.id { selectedID = connections.first?.id }
        await persist()
    }

    public func select(_ connection: ClusterConnection) {
        selectedID = connection.id
    }

    private func persist() async {
        try? await store.save(connections)
    }

    private static func sampleConnection() -> ClusterConnection {
        ClusterConnection(
            displayName: "prod-eks",
            source: .mock,
            addedAt: Date(),
            contextName: "prod-eks"
        )
    }
}
