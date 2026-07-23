import Foundation
import KubeClient
import KubeCore
import Observation

/// Drives the explorer: discovers the cluster's API resources (the sidebar),
/// **watches** the selected resource type (list+watch push updates) filtered by
/// namespace, and owns the pod-log stream and the selection inspector.
@MainActor
@Observable
final class ExplorerModel {
    /// The resource type shown in the content pane.
    var selection: APIResource? {
        didSet {
            if selection != oldValue {
                selectedID = nil
                pods = []
                rows = []
                if let selection { expandedGroups.insert(Self.sectionID(for: selection)) }
                restartWatch()
                fetchDescription()
            }
        }
    }
    /// Expanded sidebar sections (by group id). Collapsed by default; the
    /// selected resource's section is auto-expanded so it stays visible.
    private(set) var expandedGroups: Set<String> = []
    /// Namespaces to show; empty = all. Client-side filter over a cluster-wide
    /// watch, so toggling is instant.
    var selectedNamespaces: Set<String> = [] {
        didSet { if selectedNamespaces != oldValue { applyFilter() } }
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

    private(set) var sections: [SidebarSection] = []
    private(set) var namespaces: [String] = []
    private(set) var pods: [Pod] = []
    private(set) var rows: [ResourceRow] = []
    private var fullPods: [Pod] = []
    private var fullRows: [ResourceRow] = []
    private(set) var counts: [String: Int] = [:]
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var activeSourceKind: ClusterSource.Kind?
    private(set) var lastUpdated: Date?

    private(set) var logLines: [LogLine] = []
    private(set) var followedPod: String?
    private(set) var inspector: InspectorData?
    /// The selected resource type's description from the OpenAPI schema.
    private(set) var selectionDescription: String?
    private var descriptionCache: [String: [String: String]] = [:]

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

    /// Point the explorer at a connection: build its client, discover resources,
    /// load namespaces, and start watching a default resource (Pods).
    func activate(_ connection: ClusterConnection?) async {
        stop()
        selection = nil
        selectedID = nil
        inspector = nil
        sections = []
        counts = [:]
        selectedNamespaces = []
        guard let connection else {
            client = nil
            pods = []
            rows = []
            namespaces = []
            activeSourceKind = nil
            return
        }
        isLoading = true
        do {
            let client = try await provider.makeClient(for: connection)
            self.client = client
            activeSourceKind = connection.source.kind
            let resources = try await client.discoverAPIResources()
            sections = ResourceCatalog.sections(from: resources)
            namespaces = (try? await client.listNamespaces()) ?? []
            // Default to Pods if present, else the first resource.
            selection =
                resources.first(where: ResourceCatalog.isPods)
                ?? sections.first?.resources.first
            // restartWatch runs from selection's didSet (which also handled the
            // no-op case where selection stayed nil).
            if selection == nil { isLoading = false }
        } catch {
            self.client = nil
            sections = []
            isLoading = false
            activeSourceKind = connection.source.kind
            loadError = message(for: error)
        }
    }

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
        guard let client, let selection else { return }
        isLoading = true
        loadError = nil
        let resource = selection
        watchTask = Task { [weak self] in
            do {
                // Watch cluster-wide; namespace selection is a client-side filter.
                for try await snapshot in client.watch(resource.gvr, namespace: nil) {
                    if Task.isCancelled { break }
                    guard let self else { break }
                    self.apply(snapshot, for: resource)
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

    private func apply(_ snapshot: [ResourceObject], for resource: APIResource) {
        rawObjects = Dictionary(snapshot.map { ($0.id, $0.data) }, uniquingKeysWith: { _, new in new })
        let now = Date()
        if ResourceCatalog.isPods(resource) {
            fullPods = snapshot.compactMap { try? decoder.decode(Pod.self, from: $0.data) }
                .sorted {
                    ($0.metadata.namespace ?? "", $0.metadata.name) < (
                        $1.metadata.namespace ?? "", $1.metadata.name
                    )
                }
            fullRows = []
            if followedPod == nil, selectedID != nil { updateLogStream() }
        } else {
            fullPods = []
            fullRows = snapshot.compactMap { LiveKubernetesClient.dynamicResource(fromJSON: $0.data) }
                .sorted { ($0.namespace ?? "", $0.name) < ($1.namespace ?? "", $1.name) }
                .map { ResourceRow(dynamic: $0, now: now) }
        }
        applyFilter()
    }

    /// Recomputes displayed `pods`/`rows` from the full sets using the namespace
    /// filter. Cluster-scoped resources ignore the filter.
    private func applyFilter() {
        let clusterScoped = selection.map { !$0.namespaced } ?? false
        let selectedNamespaces = clusterScoped ? [] : selectedNamespaces
        pods = fullPods.filter {
            Self.matches(namespace: $0.metadata.namespace, selection: selectedNamespaces)
        }
        rows = fullRows.filter { Self.matches(namespace: $0.namespace, selection: selectedNamespaces) }
        if let id = selection?.id { counts[id] = fullPods.isEmpty ? rows.count : pods.count }
    }

    nonisolated static func matches(namespace: String?, selection: Set<String>) -> Bool {
        selection.isEmpty || (namespace.map(selection.contains) ?? false)
    }

    // MARK: - Sidebar sections

    static func sectionID(for resource: APIResource) -> String {
        resource.group.isEmpty ? "core" : resource.group
    }

    func isExpanded(_ sectionID: String) -> Bool { expandedGroups.contains(sectionID) }

    func toggleSection(_ sectionID: String) {
        if expandedGroups.contains(sectionID) {
            expandedGroups.remove(sectionID)
        } else {
            expandedGroups.insert(sectionID)
        }
    }

    // MARK: - Schema descriptions

    private func fetchDescription() {
        selectionDescription = nil
        guard let selection, let client else { return }
        let key = "\(selection.group)/\(selection.version)"
        if let cached = descriptionCache[key] {
            selectionDescription = cached[selection.kind]
            return
        }
        Task { [weak self] in
            let map =
                (try? await client.resourceDescriptions(
                    group: selection.group, version: selection.version)) ?? [:]
            guard let self, self.selection == selection else { return }
            self.descriptionCache[key] = map
            self.selectionDescription = map[selection.kind]
        }
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
        guard let selection, ResourceCatalog.isPods(selection), let id = selectedID,
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
        guard let id = selectedID, let selection, let client, let data = rawObjects[id],
            let wrap = try? decoder.decode(MetaWrap.self, from: data)
        else {
            inspector = nil
            return
        }
        let (statusText, health) = statusForSelected(id)
        inspector = InspectorData(
            id: id, kindTitle: selection.kind, iconName: ResourceCatalog.icon(for: selection),
            meta: wrap.metadata, statusText: statusText, health: health,
            manifest: Self.prettyJSON(data), events: [])

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
        if let pod = pods.first(where: { $0.id == id }) {
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

    /// Pretty-printed JSON manifest for the detail view.
    private static func prettyJSON(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return String(decoding: data, as: UTF8.self) }
        return String(decoding: pretty, as: UTF8.self)
    }
}

/// Decodes just the metadata of any object (for the inspector).
private struct MetaWrap: Decodable {
    let metadata: ObjectMeta
}
