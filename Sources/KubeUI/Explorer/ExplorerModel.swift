import KubeClient
import KubeCore
import Observation
import SwiftUI

/// Drives the explorer's content: builds a `ClusterClient` for the selected
/// connection (via the injected factory) and loads its resources. Rebuilding on
/// selection is what makes switching clusters show live data.
@MainActor
@Observable
public final class ExplorerModel {
    public var selection: ResourceKind = .pods
    public private(set) var pods: [Pod] = []
    public private(set) var deploymentCount: Int?
    public private(set) var isLoading = false
    public private(set) var loadError: String?
    /// The source kind currently loaded — lets the UI tell live from demo.
    public private(set) var activeSourceKind: ClusterSource.Kind?

    private let provider: any ClusterClientProviding
    private var client: (any ClusterClient)?

    public init(clientProvider: any ClusterClientProviding) {
        self.provider = clientProvider
    }

    /// Point the explorer at a connection (or nothing). Builds its client and
    /// loads resources. Safe to call repeatedly as the selection changes.
    public func activate(_ connection: ClusterConnection?) async {
        guard let connection else {
            client = nil
            pods = []
            deploymentCount = nil
            activeSourceKind = nil
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let client = try await provider.makeClient(for: connection)
            self.client = client
            activeSourceKind = connection.source.kind
            try await load(using: client)
        } catch {
            self.client = nil
            pods = []
            deploymentCount = nil
            activeSourceKind = connection.source.kind
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func load(using client: any ClusterClient) async throws {
        async let pods = client.listPods(namespace: nil)
        async let deployments = client.listDeployments(namespace: nil)
        self.pods = try await pods
        self.deploymentCount = try await deployments.count
    }
}
