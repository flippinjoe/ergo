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
                counts: model.counts,
                clusters: clusters,
                onAddCluster: { showingAdd = true },
                onManage: { showingManage = true }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
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
        .navigationTitle(model.selection.title)
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
        switch model.selection {
        case .pods:
            PodsContentPane(
                pods: model.pods,
                loadError: model.loadError,
                isLoading: model.isLoading,
                selection: $model.selectedID,
                followedPod: model.followedPod,
                logLines: model.logLines
            )
        default:
            ResourceTableView(
                title: model.selection.title,
                rows: model.rows,
                detailTitle: model.selection.detailColumnTitle,
                loadError: model.loadError,
                isLoading: model.isLoading,
                selection: $model.selectedID
            )
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // Leading: the scope filter (namespace). Grouped here, near the content
        // it filters, instead of floating in the toolbar's center.
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                Button {
                    model.selectedNamespace = nil
                } label: {
                    namespaceLabel("All namespaces", selected: model.selectedNamespace == nil)
                }
                if !model.namespaces.isEmpty {
                    Divider()
                    ForEach(model.namespaces, id: \.self) { namespace in
                        Button {
                            model.selectedNamespace = namespace
                        } label: {
                            namespaceLabel(namespace, selected: model.selectedNamespace == namespace)
                        }
                    }
                }
            } label: {
                Label(model.selectedNamespace ?? "All namespaces", systemImage: "line.3.horizontal.decrease")
            }
            .help("Filter by namespace")
        }
        // Trailing: live-status, search, and the AI action.
        ToolbarItemGroup(placement: .primaryAction) {
            LiveIndicator(isLoading: model.isLoading)
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

    @ViewBuilder private func namespaceLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

/// A small "Live" pill signaling the view auto-updates.
private struct LiveIndicator: View {
    let isLoading: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: Nocturne.Space.s2) {
            Circle()
                .fill(Nocturne.statusOK)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.35 : 1)
            Text("Live").font(Nocturne.Font.small).foregroundStyle(Nocturne.muted(0.7))
        }
        .help("Auto-updating")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// The Pods pane: the table edge-to-edge with the log dock pinned to the bottom.
private struct PodsContentPane: View {
    let pods: [Pod]
    let loadError: String?
    let isLoading: Bool
    @Binding var selection: Pod.ID?
    let followedPod: String?
    let logLines: [LogLine]

    var body: some View {
        VStack(spacing: 0) {
            PodsTableView(pods: pods, loadError: loadError, isLoading: isLoading, selection: $selection)
                .frame(maxHeight: .infinity)
            LogDockView(followed: followedPod, lines: logLines)
                .padding([.horizontal, .bottom], Nocturne.Space.s3)
        }
    }
}

#if DEBUG
#Preview {
    ClusterExplorerView(clientProvider: StaticClusterClientProvider(FakeClusterClient()))
        .frame(width: 1040, height: 680)
        .preferredColorScheme(.dark)
}
#endif
