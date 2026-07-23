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
                podCount: model.pods.count,
                deploymentCount: model.deploymentCount,
                clusters: clusters,
                onAddCluster: { showingAdd = true },
                onManage: { showingManage = true }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detail
                .background(WallBackground())
                .toolbar { toolbar }
        }
        .navigationTitle(model.selection.title)
        .task { await clusters.load() }
        // Rebuild + reload whenever the selected cluster changes.
        .task(id: clusters.selectedID) { await model.activate(clusters.selected) }
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
                isLive: model.activeSourceKind != nil && model.activeSourceKind != .mock
            )
        default:
            ComingSoonPane(kind: model.selection)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Label(clusters.selected?.displayName ?? "No cluster", systemImage: "cube")
                .labelStyle(.titleAndIcon)
                .tint(Nocturne.accent200)
        }
        ToolbarItemGroup(placement: .principal) {
            Button {
            } label: {
                Label("Status", systemImage: "line.3.horizontal.decrease")
            }
            Button {
            } label: {
                Label("Age", systemImage: "arrow.up.arrow.down")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
            } label: {
                Image(systemName: "magnifyingglass")
            }
            Button {
            } label: {
                Label("Ask", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(Nocturne.accent)
        }
    }
}

/// The Pods pane: the table edge-to-edge with the log dock pinned to the bottom.
private struct PodsContentPane: View {
    let pods: [Pod]
    let loadError: String?
    let isLoading: Bool
    let isLive: Bool

    var body: some View {
        VStack(spacing: 0) {
            PodsTableView(pods: pods, loadError: loadError, isLoading: isLoading)
                .frame(maxHeight: .infinity)
            // Sample logs only for the demo cluster; live clusters show an
            // honest "coming soon" rather than fabricated log lines.
            if isLive {
                LogDockView(followed: nil, lines: [])
                    .padding([.horizontal, .bottom], Nocturne.Space.s3)
            } else {
                LogDockView(followed: "argocd-repo-server-5f7b-jc9wd", lines: Self.sampleLog)
                    .padding([.horizontal, .bottom], Nocturne.Space.s3)
            }
        }
    }

    static let sampleLog: [LogDockView.Line] = [
        .init(
            time: "09:41:13.201", level: .warn,
            message: "git credential template store not found, falling back"),
        .init(
            time: "09:41:13.334", level: .error,
            message: "failed to init repo cache: dial tcp 10.0.44.9:6379: connect: connection refused"),
        .init(
            time: "09:41:13.335", level: .error, message: "redis unreachable — see redis-master-0 (Pending)"),
    ]
}

/// Placeholder for kinds whose panes aren't built yet — keeps the navigation
/// whole while features land behind the seams.
private struct ComingSoonPane: View {
    let kind: ResourceKind

    var body: some View {
        ContentUnavailableView {
            Label(kind.title, systemImage: kind.systemImage)
        } description: {
            Text("This pane isn't built yet — the seam is here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    ClusterExplorerView(clientProvider: StaticClusterClientProvider(FakeClusterClient()))
        .frame(width: 1040, height: 680)
        .preferredColorScheme(.dark)
}
#endif
