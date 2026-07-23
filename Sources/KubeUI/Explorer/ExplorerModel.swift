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
        didSet {
            if selection != oldValue {
                reloadTask()
                updateLogStream()
            }
        }
    }
    /// nil = all namespaces.
    var selectedNamespace: String? {
        didSet { if selectedNamespace != oldValue { reloadTask() } }
    }
    /// The pod whose logs the dock follows (bound from the pods table).
    var selectedPodID: Pod.ID? {
        didSet { if selectedPodID != oldValue { updateLogStream() } }
    }

    private(set) var logLines: [LogLine] = []
    private(set) var followedPod: String?

    private(set) var namespaces: [String] = []
    private(set) var pods: [Pod] = []
    private(set) var rows: [ResourceRow] = []
    private(set) var counts: [ResourceKind: Int] = [:]
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var activeSourceKind: ClusterSource.Kind?
    /// When the visible data was last refreshed (for the auto-update indicator).
    private(set) var lastUpdated: Date?

    /// How often the current view silently refreshes. A stand-in for a future
    /// watch stream — the refresh seam is here.
    let pollInterval: Duration = .seconds(5)

    private let provider: any ClusterClientProviding
    private var client: (any ClusterClient)?
    private var pollingTask: Task<Void, Never>?
    private var logTask: Task<Void, Never>?
    private let maxLogLines = 1000

    init(clientProvider: any ClusterClientProviding) {
        self.provider = clientProvider
    }

    /// Point the explorer at a connection (or nothing). Builds its client, loads
    /// namespaces, and starts refreshing the current selection.
    func activate(_ connection: ClusterConnection?) async {
        stopPolling()
        stopLogStream()
        selectedPodID = nil
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
            await load(showSpinner: true)
            startPolling()
        } catch {
            self.client = nil
            pods = []
            rows = []
            namespaces = []
            activeSourceKind = connection.source.kind
            loadError = message(for: error)
        }
    }

    /// Stops all background work — call from the view's `onDisappear`.
    func stop() {
        stopPolling()
        stopLogStream()
    }

    /// Stops background refresh.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Log streaming

    private func stopLogStream() {
        logTask?.cancel()
        logTask = nil
    }

    /// (Re)starts the pod-log stream for the current selection. Only streams on
    /// the Pods view with a selected pod that exists in the loaded list.
    private func updateLogStream() {
        stopLogStream()
        logLines = []
        followedPod = nil
        guard selection == .pods, let id = selectedPodID,
            let pod = pods.first(where: { $0.id == id }), let client
        else { return }

        followedPod = pod.metadata.name
        let namespace = pod.metadata.namespace ?? "default"
        let name = pod.metadata.name
        let container = pod.status?.containerStatuses?.first?.name
        logTask = Task { [weak self] in
            do {
                for try await raw in client.streamLogs(
                    namespace: namespace, pod: name, container: container)
                {
                    if Task.isCancelled { break }
                    self?.appendLog(LogLine(raw: raw))
                }
            } catch {
                self?.appendLog(LogLine(raw: "— log stream ended: \(self?.message(for: error) ?? "")"))
            }
        }
    }

    private func appendLog(_ line: LogLine) {
        logLines.append(line)
        if logLines.count > maxLogLines { logLines.removeFirst(logLines.count - maxLogLines) }
    }

    private func reloadTask() {
        // Selection/namespace changed: show the spinner and restart the poll.
        Task {
            await load(showSpinner: true)
            startPolling()
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self, interval = pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await self?.load(showSpinner: false)
            }
        }
    }

    /// Loads the current selection for the current namespace. `showSpinner` is
    /// false for background polls so the view doesn't flicker, and a transient
    /// poll error keeps the last-known data instead of blanking the table.
    func load(showSpinner: Bool) async {
        guard let client else { return }
        if showSpinner { isLoading = true }
        defer { if showSpinner { isLoading = false } }
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
            loadError = nil
            lastUpdated = now
        } catch {
            if showSpinner {
                pods = []
                rows = []
                loadError = message(for: error)
            }
            // Background poll failures are ignored — keep showing last-known data.
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
