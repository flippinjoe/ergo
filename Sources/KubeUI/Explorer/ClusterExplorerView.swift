import KubeClient
import KubeCore
import SwiftUI

/// Concept **1a — the everyday cluster explorer** and the app's main window:
/// a glass navigation sidebar over an edge-to-edge solid content pane, a
/// unified toolbar, and a log dock. This is the shared, platform-agnostic
/// surface; the macOS app target only supplies the window + a `ClusterClient`.
public struct ClusterExplorerView: View {
    @State private var model: ExplorerModel
    @State private var clusters: ClustersModel
    @State private var showingAdd = false
    @State private var showingManage = false
    @State private var showingNamespaces = false

    public init(
        clientProvider: any ClusterClientProviding = StaticClusterClientProvider(FakeClusterClient()),
        clusterStore: any ClusterStore = InMemoryClusterStore(),
        azureService: any AzureClusterService = FakeAzureClusterService()
    ) {
        _model = State(initialValue: ExplorerModel(clientProvider: clientProvider))
        _clusters = State(initialValue: ClustersModel(store: clusterStore, azure: azureService))
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $model.selection,
                grouping: $model.grouping,
                sections: model.sections,
                counts: model.counts,
                expanded: model.expandedGroups,
                onToggleSection: { model.toggleSection($0) },
                pinned: model.pinnedResources,
                pinnedIDs: model.pinnedIDSet,
                onTogglePin: { model.togglePin($0) },
                onMovePinned: { model.movePinned($0, before: $1) },
                clusters: clusters,
                onAddCluster: { showingAdd = true },
                onManage: { showingManage = true }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            HStack(spacing: 0) {
                detail
                if let inspector = model.inspector {
                    InspectorView(data: inspector) { model.clearSelection() }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: model.inspector?.id)
            .background(WallBackground())
            .toolbar { toolbar }
        }
        // The refractive wall also sits behind the sidebar and under the unified
        // toolbar, so the sidebar glass and the Liquid Glass title bar refract
        // one continuous surface instead of a plain window backing.
        .background(WallBackground())
        .navigationTitle(model.selection?.displayName ?? "Ergo")
        .task { await clusters.load() }
        // Rebuild + reload whenever the selected cluster changes.
        .task(id: clusters.selectedID) { await model.activate(clusters.selected) }
        .onDisappear { model.stop() }
        .tint(Nocturne.accent)
        .sheet(isPresented: $showingAdd) {
            AddClusterSheet(azure: clusters.azure) { connections in
                await clusters.add(connections)
            }
        }
        .sheet(isPresented: $showingManage) {
            ClustersManagerView(clusters: clusters) {
                showingManage = false
                showingAdd = true
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let selection = model.selection {
            if ResourceCatalog.isPods(selection) {
                PodsContentPane(
                    pods: model.pods,
                    description: model.selectionDescription,
                    loadError: model.loadError,
                    isLoading: model.isLoading,
                    selection: $model.selectedID,
                    followedPod: model.followedPod,
                    logLines: model.logLines,
                    showLogs: model.showLogDock,
                    onCloseLogs: { model.setLogDockVisible(false) }
                )
            } else {
                ResourceTableView(
                    title: selection.displayName,
                    description: model.selectionDescription,
                    rows: model.rows,
                    detailTitle: ResourceCatalog.hasReadyColumn(selection) ? "Ready" : nil,
                    loadError: model.loadError,
                    isLoading: model.isLoading,
                    selection: $model.selectedID
                )
            }
        } else {
            ContentUnavailableView("Select a resource", systemImage: "square.grid.2x2")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // Leading: the scope filter (namespace). Grouped here, near the content
        // it filters, instead of floating in the toolbar's center.
        ToolbarItemGroup(placement: .navigation) {
            Button {
                showingNamespaces.toggle()
            } label: {
                Label(namespaceSummary, systemImage: "line.3.horizontal.decrease")
            }
            .help("Filter by namespace")
            .popover(isPresented: $showingNamespaces, arrowEdge: .bottom) {
                NamespaceFilterView(namespaces: model.namespaces, selection: $model.selectedNamespaces)
            }
        }
        // Trailing: logs toggle (Pods only), search, and the AI action.
        ToolbarItemGroup(placement: .primaryAction) {
            if let selection = model.selection, ResourceCatalog.isPods(selection) {
                Button {
                    model.toggleLogDock()
                } label: {
                    Label("Logs", systemImage: "text.alignleft")
                }
                .help(model.showLogDock ? "Hide logs" : "Show logs")
                .tint(model.showLogDock ? Nocturne.accent : nil)
            }
            Button {
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Search")
            Button {
            } label: {
                Label("Ask", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(Nocturne.accent)
        }
    }

    private var namespaceSummary: String {
        switch model.selectedNamespaces.count {
        case 0: "All namespaces"
        case 1: model.selectedNamespaces.first ?? "All namespaces"
        default: "\(model.selectedNamespaces.count) namespaces"
        }
    }
}

/// The Pods pane: the table edge-to-edge, with the log dock revealed at the
/// bottom only while `showLogs` is on (opt-in, closable).
private struct PodsContentPane: View {
    let pods: [Pod]
    let description: String?
    let loadError: String?
    let isLoading: Bool
    @Binding var selection: Pod.ID?
    let followedPod: String?
    let logLines: [LogLine]
    let showLogs: Bool
    let onCloseLogs: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PodsTableView(
                pods: pods, description: description, loadError: loadError, isLoading: isLoading,
                selection: $selection
            )
            .frame(maxHeight: .infinity)
            if showLogs {
                LogDockView(followed: followedPod, lines: logLines, onClose: onCloseLogs)
                    .padding([.horizontal, .bottom], Nocturne.Space.s3)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLogs)
    }
}

#if DEBUG
#Preview {
    ClusterExplorerView(clientProvider: StaticClusterClientProvider(FakeClusterClient()))
        .frame(width: 1040, height: 680)
        .preferredColorScheme(.dark)
}
#endif
