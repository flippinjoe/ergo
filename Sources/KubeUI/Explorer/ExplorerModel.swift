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
                if let selection {
                    expandedGroups.insert(ResourceCatalog.sectionID(for: selection, grouping: grouping))
                }
                selectResource()
                fetchDescription()
            }
        }
    }
    /// How the sidebar is organized (persisted). Changing it re-sections without
    /// re-discovering.
    var grouping: SidebarGrouping {
        didSet {
            if grouping != oldValue {
                UserDefaults.standard.set(grouping.rawValue, forKey: Self.groupingKey)
                rebuildSections()
            }
        }
    }
    /// Expanded sidebar sections. Collapsed by default; the selected resource's
    /// section is auto-expanded so it stays visible.
    private(set) var expandedGroups: Set<String> = []
    /// Namespaces to show; empty = all. Client-side filter over a cluster-wide
    /// watch, so toggling is instant.
    var selectedNamespaces: Set<String> = [] {
        didSet {
            if selectedNamespaces != oldValue {
                applyFilter()
                recomputeCounts()
            }
        }
    }
    /// The selected row's id (uid). Drives the inspector and, on Pods, logs.
    var selectedID: String? {
        didSet {
            if selectedID != oldValue {
                if showLogDock { updateLogStream() }
                updateInspectorTask()
            }
        }
    }
    /// Whether the pod log dock is shown. Off by default: logs are opt-in, not
    /// summoned automatically by selecting a pod. Streaming only runs while the
    /// dock is visible.
    private(set) var showLogDock = false

    private(set) var sections: [SidebarSection] = []
    /// Resource types pinned to the top of the sidebar, in the user's order.
    /// Per-cluster and independent of the grouping mode.
    private(set) var pinnedResources: [APIResource] = []
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
    private let layoutStore: any SidebarLayoutStore
    /// Stable key of the active cluster, used to scope its saved layout.
    private var clusterKey: String?
    /// Ordered pinned ids for the active cluster (superset of `pinnedResources`;
    /// may hold ids not currently discovered). The display list is derived.
    private var pinnedIDs: [String] = []
    private var client: (any ClusterClient)?
    private var logTask: Task<Void, Never>?
    private var inspectorTask: Task<Void, Never>?
    private var rawObjects: [String: Data] = [:]
    private var discovered: [APIResource] = []

    // MARK: Cache
    //
    // One watch per visited/pinned resource type keeps feeding a per-type cache,
    // so switching resources shows cached rows instantly (no flash) while the
    // stream keeps them live. Warm watches are capped by `watchLimit` (LRU),
    // never evicting the current selection or a pinned type.
    private struct Cached {
        var pods: [Pod] = []
        var rows: [ResourceRow] = []
        var lastUpdated: Date?
        var loaded = false
    }
    private var cache: [String: Cached] = [:]
    private var rawByKey: [String: [String: Data]] = [:]
    private var watchTasks: [String: Task<Void, Never>] = [:]
    private var watchOrder: [String] = []
    private let watchLimit = 24

    private let maxLogLines = 1000
    private static let groupingKey = "ergo.sidebarGrouping"
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(
        clientProvider: any ClusterClientProviding,
        layoutStore: any SidebarLayoutStore = UserDefaultsSidebarLayoutStore()
    ) {
        self.provider = clientProvider
        self.layoutStore = layoutStore
        let stored = UserDefaults.standard.string(forKey: Self.groupingKey)
        self.grouping = stored.flatMap(SidebarGrouping.init(rawValue:)) ?? .curated
    }

    /// Point the explorer at a connection: build its client, discover resources,
    /// load namespaces, and start watching a default resource (Pods).
    func activate(_ connection: ClusterConnection?) async {
        stop()
        showLogDock = false
        selection = nil
        selectedID = nil
        inspector = nil
        sections = []
        counts = [:]
        selectedNamespaces = []
        pinnedResources = []
        pinnedIDs = []
        cache = [:]
        rawByKey = [:]
        clusterKey = connection?.source.identityKey
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
            discovered = try await client.discoverAPIResources()
            rebuildSections()
            loadPinned()
            namespaces = (try? await client.listNamespaces()) ?? []
            // Default to Pods if present, else the first resource.
            selection =
                discovered.first(where: ResourceCatalog.isPods)
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
        for task in watchTasks.values { task.cancel() }
        watchTasks = [:]
        watchOrder = []
        stopLogStream()
        inspectorTask?.cancel()
        inspectorTask = nil
    }

    // MARK: - Watch + cache

    /// Point the visible content at the selected resource: show its cached rows
    /// immediately (no flash), then make sure a watch is feeding that cache.
    private func selectResource() {
        loadError = nil
        guard let selection else {
            fullPods = []
            fullRows = []
            rawObjects = [:]
            isLoading = false
            applyFilter()
            return
        }
        let key = selection.id
        if let cached = cache[key], cached.loaded {
            fullPods = cached.pods
            fullRows = cached.rows
            rawObjects = rawByKey[key] ?? [:]
            isLoading = false
        } else {
            fullPods = []
            fullRows = []
            rawObjects = [:]
            isLoading = true
        }
        applyFilter()
        ensureWatch(for: selection)
    }

    /// Start (or reuse) a persistent watch for a resource type, feeding its
    /// cache. Watches are cluster-wide; namespace selection is a client-side
    /// filter over the cache.
    private func ensureWatch(for resource: APIResource) {
        guard let client else { return }
        let key = resource.id
        touch(key)
        guard watchTasks[key] == nil else { return }
        watchTasks[key] = Task { [weak self] in
            do {
                for try await snapshot in client.watch(resource.gvr, namespace: nil) {
                    if Task.isCancelled { break }
                    guard let self else { break }
                    self.ingest(snapshot, for: resource)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.watchFailed(key: key, error: error)
            }
        }
    }

    /// Fold a fresh snapshot into the cache and, if this is the visible
    /// resource, into the displayed rows.
    private func ingest(_ snapshot: [ResourceObject], for resource: APIResource) {
        let key = resource.id
        let now = Date()
        rawByKey[key] = Dictionary(
            snapshot.map { ($0.id, $0.data) }, uniquingKeysWith: { _, new in new })
        var cached = Cached(lastUpdated: now, loaded: true)
        if ResourceCatalog.isPods(resource) {
            cached.pods = snapshot.compactMap { try? decoder.decode(Pod.self, from: $0.data) }
                .sorted {
                    ($0.metadata.namespace ?? "", $0.metadata.name) < (
                        $1.metadata.namespace ?? "", $1.metadata.name
                    )
                }
        } else {
            cached.rows = snapshot.compactMap { LiveKubernetesClient.dynamicResource(fromJSON: $0.data) }
                .sorted { ($0.namespace ?? "", $0.name) < ($1.namespace ?? "", $1.name) }
                .map { ResourceRow(dynamic: $0, now: now) }
        }
        cache[key] = cached
        counts[key] = count(for: cached, resource: resource)

        guard selection?.id == key else { return }
        fullPods = cached.pods
        fullRows = cached.rows
        rawObjects = rawByKey[key] ?? [:]
        isLoading = false
        loadError = nil
        lastUpdated = now
        applyFilter()
        if showLogDock, followedPod == nil, selectedID != nil, ResourceCatalog.isPods(resource) {
            updateLogStream()
        }
    }

    private func watchFailed(key: String, error: any Error) {
        watchTasks[key]?.cancel()
        watchTasks[key] = nil
        watchOrder.removeAll { $0 == key }
        guard selection?.id == key else { return }
        isLoading = false
        // Keep showing cached (stale) rows if we have them; only surface the
        // error when there's nothing to show.
        if cache[key]?.loaded != true {
            fullPods = []
            fullRows = []
            applyFilter()
            loadError = message(for: error)
        }
    }

    /// Mark a resource as most-recently-used and evict cold watches past the cap.
    private func touch(_ key: String) {
        watchOrder.removeAll { $0 == key }
        watchOrder.append(key)
        let keep = Set([selection?.id].compactMap { $0 }).union(pinnedIDs)
        var index = 0
        while watchTasks.count > watchLimit, index < watchOrder.count {
            let candidate = watchOrder[index]
            if keep.contains(candidate) || watchTasks[candidate] == nil {
                index += 1
                continue
            }
            // Drop the live watch but keep the last snapshot so a return visit is
            // still instant (stale until the watch restarts).
            watchTasks[candidate]?.cancel()
            watchTasks[candidate] = nil
            watchOrder.remove(at: index)
        }
    }

    /// Recomputes displayed `pods`/`rows` from the full sets using the namespace
    /// filter. Cluster-scoped resources ignore the filter.
    private func applyFilter() {
        let clusterScoped = selection.map { !$0.namespaced } ?? false
        let namespaces = clusterScoped ? [] : selectedNamespaces
        pods = fullPods.filter { Self.matches(namespace: $0.metadata.namespace, selection: namespaces) }
        rows = fullRows.filter { Self.matches(namespace: $0.namespace, selection: namespaces) }
    }

    /// The count shown next to a resource in the sidebar, honoring the namespace
    /// filter (cluster-scoped types ignore it).
    private func count(for cached: Cached, resource: APIResource) -> Int {
        let isPods = ResourceCatalog.isPods(resource)
        guard resource.namespaced, !selectedNamespaces.isEmpty else {
            return isPods ? cached.pods.count : cached.rows.count
        }
        if isPods {
            return cached.pods.filter {
                Self.matches(namespace: $0.metadata.namespace, selection: selectedNamespaces)
            }.count
        }
        return cached.rows.filter {
            Self.matches(namespace: $0.namespace, selection: selectedNamespaces)
        }.count
    }

    /// Refresh every cached resource's sidebar count for the current filter.
    private func recomputeCounts() {
        let byID = Dictionary(discovered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, cached) in cache {
            if let resource = byID[key] { counts[key] = count(for: cached, resource: resource) }
        }
    }

    nonisolated static func matches(namespace: String?, selection: Set<String>) -> Bool {
        selection.isEmpty || (namespace.map(selection.contains) ?? false)
    }

    // MARK: - Sidebar sections

    private func rebuildSections() {
        sections = ResourceCatalog.sections(from: discovered, grouping: grouping)
        // Reset expansion to just the selected resource's section.
        if let selection {
            expandedGroups = [ResourceCatalog.sectionID(for: selection, grouping: grouping)]
        } else {
            expandedGroups = []
        }
    }

    func isExpanded(_ sectionID: String) -> Bool { expandedGroups.contains(sectionID) }

    func toggleSection(_ sectionID: String) {
        if expandedGroups.contains(sectionID) {
            expandedGroups.remove(sectionID)
        } else {
            expandedGroups.insert(sectionID)
        }
    }

    // MARK: - Pinned resources (per cluster)

    /// The ids currently pinned, for marking rows in the grouped sections.
    var pinnedIDSet: Set<String> { Set(pinnedIDs) }

    func isPinned(_ resource: APIResource) -> Bool { pinnedIDs.contains(resource.id) }

    /// Load the active cluster's saved pins, dropping any that this cluster no
    /// longer serves, then persist the pruned set.
    private func loadPinned() {
        guard let clusterKey else { return }
        let discoveredIDs = Set(discovered.map(\.id))
        let stored = layoutStore.layout(for: clusterKey).pinned
        let pruned = stored.filter(discoveredIDs.contains)
        pinnedIDs = pruned
        if pruned != stored { persistPinned() }
        rebuildPinned()
        warmPinned()
    }

    func togglePin(_ resource: APIResource) {
        if let index = pinnedIDs.firstIndex(of: resource.id) {
            pinnedIDs.remove(at: index)
        } else {
            pinnedIDs.append(resource.id)
            ensureWatch(for: resource)  // start feeding the cache so it's instant later
        }
        persistPinned()
        rebuildPinned()
    }

    /// Keep a live watch running for each pinned resource so the cache stays warm.
    private func warmPinned() {
        let byID = Dictionary(discovered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in pinnedIDs {
            if let resource = byID[id] { ensureWatch(for: resource) }
        }
    }

    /// Reorder a pinned resource to sit before `targetID` (nil = move to end).
    func movePinned(_ draggedID: String, before targetID: String?) {
        let reordered = SidebarLayout.reorder(pinnedIDs, moving: draggedID, before: targetID)
        guard reordered != pinnedIDs else { return }
        pinnedIDs = reordered
        persistPinned()
        rebuildPinned()
    }

    private func rebuildPinned() {
        let byID = Dictionary(discovered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        pinnedResources = pinnedIDs.compactMap { byID[$0] }
    }

    private func persistPinned() {
        guard let clusterKey else { return }
        layoutStore.save(SidebarLayout(pinned: pinnedIDs), for: clusterKey)
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

    /// Show or hide the pod log dock. Showing it starts streaming the selected
    /// pod; hiding it tears the stream down and clears any buffered lines.
    func setLogDockVisible(_ visible: Bool) {
        guard showLogDock != visible else { return }
        showLogDock = visible
        if visible {
            updateLogStream()
        } else {
            stopLogStream()
            logLines = []
            followedPod = nil
        }
    }

    func toggleLogDock() { setLogDockVisible(!showLogDock) }

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
        let detailSections = ResourceDetail.sections(
            kind: selection.kind, group: selection.group, manifest: data)
        inspector = InspectorData(
            id: id, kindTitle: selection.kind, iconName: ResourceCatalog.icon(for: selection),
            meta: wrap.metadata, statusText: statusText, health: health,
            manifest: Self.prettyJSON(data), events: [], detailSections: detailSections)

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
