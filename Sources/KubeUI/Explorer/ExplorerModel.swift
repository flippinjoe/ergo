import Foundation
import KubeClient
import KubeCore
import Observation

/// Drives the explorer's content: builds a `ClusterClient` for the selected
/// connection and **watches** the selected kind (list+watch push updates),
/// scoped to the selected namespace. Also owns the pod-log stream and the
/// selection-driven inspector.
@MainActor
@Observable
final class ExplorerModel {
    var selection: ResourceKind = .pods {
        didSet { if selection != oldValue { restartWatch() } }
    }
    /// nil = all namespaces.
    var selectedNamespace: String? {
        didSet { if selectedNamespace != oldValue { restartWatch() } }
    }
    /// The selected row's id (uid). Drives the inspector and, on Pods, logs.
    var selectedID: String? {
        didSet {
            if selectedID != oldValue {
                updateLogStream()
                updateInspectorTask()
            }
        }
    }

    private(set) var namespaces: [String] = []
    private(set) var pods: [Pod] = []
    private(set) var rows: [ResourceRow] = []
    private(set) var counts: [ResourceKind: Int] = [:]
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var activeSourceKind: ClusterSource.Kind?
    private(set) var lastUpdated: Date?

    // Logs
    private(set) var logLines: [LogLine] = []
    private(set) var followedPod: String?

    // Inspector
    private(set) var inspector: InspectorData?

    private let provider: any ClusterClientProviding
    private var client: (any ClusterClient)?
    private var watchTask: Task<Void, Never>?
    private var logTask: Task<Void, Never>?
    private var inspectorTask: Task<Void, Never>?
    private var rawObjects: [String: Data] = [:]
    private let maxLogLines = 1000
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(clientProvider: any ClusterClientProviding) {
        self.provider = clientProvider
    }

    /// Point the explorer at a connection (or nothing). Builds its client, loads
    /// namespaces, and starts watching the current selection.
    func activate(_ connection: ClusterConnection?) async {
        stop()
        selectedID = nil
        inspector = nil
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
            namespaces = (try? await client.listNamespaces()) ?? []
            restartWatch()
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
        watchTask?.cancel()
        watchTask = nil
        stopLogStream()
        inspectorTask?.cancel()
        inspectorTask = nil
    }

    // MARK: - Watch

    private func restartWatch() {
        watchTask?.cancel()
        guard let client else { return }
        isLoading = true
        loadError = nil
        let kind = selection
        let gvr = kind.gvr
        let namespace = selectedNamespace
        watchTask = Task { [weak self] in
            do {
                for try await snapshot in client.watch(gvr, namespace: namespace) {
                    if Task.isCancelled { break }
                    guard let self else { break }
                    self.apply(snapshot, for: kind)
                    self.isLoading = false
                    self.loadError = nil
                    self.lastUpdated = Date()
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isLoading = false
                self.pods = []
                self.rows = []
                self.loadError = self.message(for: error)
            }
        }
    }

    private func apply(_ snapshot: [ResourceObject], for kind: ResourceKind) {
        rawObjects = Dictionary(snapshot.map { ($0.id, $0.data) }, uniquingKeysWith: { _, new in new })
        let now = Date()
        switch kind {
        case .pods:
            let pods = snapshot.compactMap { try? decoder.decode(Pod.self, from: $0.data) }
                .sorted(by: Self.byNamespaceName)
            self.pods = pods
            rows = []
            counts[.pods] = pods.count
            // A newly-arrived selected pod can now start streaming logs.
            if followedPod == nil, selectedID != nil { updateLogStream() }
        case .deployments:
            let items = snapshot.compactMap { try? decoder.decode(Deployment.self, from: $0.data) }
                .sorted(by: Self.byNamespaceName)
            setRows(items.map { ResourceRow(deployment: $0, now: now) }, kind: kind)
        case .statefulSets:
            let items = snapshot.compactMap { try? decoder.decode(StatefulSet.self, from: $0.data) }
                .sorted(by: Self.byNamespaceName)
            setRows(items.map { ResourceRow(statefulSet: $0, now: now) }, kind: kind)
        case .certificates, .applications, .scaledObjects:
            let items = snapshot.compactMap { LiveKubernetesClient.dynamicResource(fromJSON: $0.data) }
                .sorted { ($0.namespace ?? "", $0.name) < ($1.namespace ?? "", $1.name) }
            setRows(items.map { ResourceRow(dynamic: $0, now: now) }, kind: kind)
        }
    }

    private func setRows(_ rows: [ResourceRow], kind: ResourceKind) {
        self.rows = rows
        pods = []
        counts[kind] = rows.count
    }

    private static func byNamespaceName<T: MetadataProviding>(_ a: T, _ b: T) -> Bool {
        (a.metadata.namespace ?? "", a.metadata.name) < (b.metadata.namespace ?? "", b.metadata.name)
    }

    // MARK: - Log streaming

    private func stopLogStream() {
        logTask?.cancel()
        logTask = nil
    }

    private func updateLogStream() {
        stopLogStream()
        logLines = []
        followedPod = nil
        guard selection == .pods, let id = selectedID,
            let pod = pods.first(where: { $0.id == id }), let client
        else { return }
        followedPod = pod.metadata.name
        let namespace = pod.metadata.namespace ?? "default"
        let name = pod.metadata.name
        let container = pod.status?.containerStatuses?.first?.name
        logTask = Task { [weak self] in
            do {
                for try await raw in client.streamLogs(namespace: namespace, pod: name, container: container)
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

    // MARK: - Inspector

    private func updateInspectorTask() {
        inspectorTask?.cancel()
        guard let id = selectedID, let client, let data = rawObjects[id],
            let wrap = try? decoder.decode(MetaWrap.self, from: data)
        else {
            inspector = nil
            return
        }
        let (statusText, health) = statusForSelected(id)
        inspector = InspectorData(
            id: id, kind: selection, meta: wrap.metadata, statusText: statusText, health: health, events: [])

        let meta = wrap.metadata
        inspectorTask = Task { [weak self] in
            let events = (try? await client.listEvents(namespace: meta.namespace)) ?? []
            let related =
                events
                .filter { $0.involvedObject.name == meta.name }
                .sorted { ($0.lastTimestamp ?? .distantPast) > ($1.lastTimestamp ?? .distantPast) }
            guard let self, !Task.isCancelled, self.selectedID == id else { return }
            self.inspector?.events = Array(related.prefix(25))
        }
    }

    private func statusForSelected(_ id: String) -> (String?, HealthStatus) {
        if selection == .pods, let pod = pods.first(where: { $0.id == id }) {
            return (pod.displayStatus, pod.health)
        }
        if let row = rows.first(where: { $0.id == id }) {
            return (row.statusText, row.health)
        }
        return (nil, .unknown)
    }

    func clearSelection() {
        selectedID = nil
    }

    private func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

/// Small helper so a generic sort can reach `.metadata`.
protocol MetadataProviding {
    var metadata: ObjectMeta { get }
}
extension Pod: MetadataProviding {}
extension Deployment: MetadataProviding {}
extension StatefulSet: MetadataProviding {}

/// Decodes just the metadata of any object (for the inspector).
private struct MetaWrap: Decodable {
    let metadata: ObjectMeta
}
