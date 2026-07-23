import KubeClient
import KubeCore
import Observation
import SwiftUI

/// Drives the explorer's content: builds a `ClusterClient` for the selected
/// connection, then loads whichever resource kind is selected, scoped to the
/// selected namespace. Rebuilding on selection is what makes switching clusters
/// show live data.
@MainActor
@Observable
final class ExplorerModel {
    var selection: ResourceKind = .pods {
        didSet { if selection != oldValue { reloadTask() } }
    }
    /// nil = all namespaces.
    var selectedNamespace: String? {
        didSet { if selectedNamespace != oldValue { reloadTask() } }
    }

    private(set) var namespaces: [String] = []
    private(set) var pods: [Pod] = []
    private(set) var rows: [ResourceRow] = []
    private(set) var counts: [ResourceKind: Int] = [:]
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var activeSourceKind: ClusterSource.Kind?

    private let provider: any ClusterClientProviding
    private var client: (any ClusterClient)?

    init(clientProvider: any ClusterClientProviding) {
        self.provider = clientProvider
    }

    /// Point the explorer at a connection (or nothing). Builds its client, loads
    /// namespaces, and loads the current selection.
    func activate(_ connection: ClusterConnection?) async {
        guard let connection else {
            client = nil
            pods = []
            rows = []
            namespaces = []
            counts = [:]
            activeSourceKind = nil
            return
        }
        selectedNamespace = nil
        counts = [:]
        do {
            let client = try await provider.makeClient(for: connection)
            self.client = client
            activeSourceKind = connection.source.kind
            // Namespaces are best-effort — some clusters restrict listing them.
            namespaces = (try? await client.listNamespaces()) ?? []
            await reload()
        } catch {
            self.client = nil
            pods = []
            rows = []
            namespaces = []
            activeSourceKind = connection.source.kind
            loadError = message(for: error)
        }
    }

    private func reloadTask() {
        Task { await reload() }
    }

    /// Loads the current selection for the current namespace.
    func reload() async {
        guard let client else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let now = Date()
        do {
            switch selection {
            case .pods:
                let pods = try await client.listPods(namespace: selectedNamespace)
                self.pods = pods
                rows = []
                counts[.pods] = pods.count
            case .deployments:
                let items = try await client.listDeployments(namespace: selectedNamespace)
                setRows(items.map { ResourceRow(deployment: $0, now: now) })
            case .statefulSets:
                let items = try await client.listStatefulSets(namespace: selectedNamespace)
                setRows(items.map { ResourceRow(statefulSet: $0, now: now) })
            case .certificates, .applications, .scaledObjects:
                guard let gvr = selection.customResource else { return }
                let items = try await client.listDynamic(gvr, namespace: selectedNamespace)
                setRows(items.map { ResourceRow(dynamic: $0, now: now) })
            }
        } catch {
            pods = []
            rows = []
            loadError = message(for: error)
        }
    }

    private func setRows(_ rows: [ResourceRow]) {
        self.rows = rows
        pods = []
        counts[selection] = rows.count
    }

    private func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
