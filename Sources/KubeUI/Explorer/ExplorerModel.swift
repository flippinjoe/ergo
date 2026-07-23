import KubeClient
import KubeCore
import Observation
import SwiftUI

/// Drives the explorer: loads resources through the `ClusterClient` boundary
/// and exposes view state. `@MainActor` because it feeds SwiftUI directly; it
/// only ever talks to the injected client, so it stays hermetic in previews and
/// tests.
@MainActor
@Observable
public final class ExplorerModel {
    public var selection: ResourceKind = .pods
    public private(set) var pods: [Pod] = []
    public private(set) var loadError: String?

    private let client: any ClusterClient

    public init(client: any ClusterClient) {
        self.client = client
    }

    public func loadPods() async {
        do {
            pods = try await client.listPods(namespace: nil)
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }
}
