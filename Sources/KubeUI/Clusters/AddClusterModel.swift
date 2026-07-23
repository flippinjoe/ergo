import Foundation
import KubeClient
import KubeCore
import Observation

/// Drives the multi-step "Add Cluster" flow. Provider-agnostic shell today with
/// the Azure path fully wired; new providers add steps here.
@MainActor
@Observable
final class AddClusterModel {
    enum Step: Equatable {
        case chooseSource
        case azureSignIn
        case azureSubscriptions
        case azureClusters
        case kubeconfigContexts
    }

    var step: Step = .chooseSource
    var isBusy = false
    var error: String?

    // Azure flow state.
    var account: AzureAccount?
    var subscriptions: [AzureSubscription] = []
    var selectedSubscription: AzureSubscription?
    var clusters: [AzureManagedCluster] = []
    var selectedClusterIDs: Set<AzureManagedCluster.ID> = []

    // Local-kubeconfig flow state.
    var kubeContexts: [Kubeconfig.Context] = []
    var selectedContextNames: Set<String> = []
    private var kubeconfigPath = ""
    private var kubeconfigBookmark: Data?

    private let azure: any AzureClusterService

    init(azure: any AzureClusterService) {
        self.azure = azure
    }

    var canGoBack: Bool { step != .chooseSource }

    func goBack() {
        switch step {
        case .chooseSource: break
        case .azureSignIn: step = .chooseSource
        case .azureSubscriptions: step = .azureSignIn
        case .azureClusters: step = .azureSubscriptions
        case .kubeconfigContexts: step = .chooseSource
        }
    }

    // MARK: Local kubeconfig

    /// Reads a user-picked kubeconfig, records a security-scoped bookmark for
    /// later access, and lists its contexts for selection.
    func loadKubeconfig(url: URL) {
        error = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            kubeconfigBookmark = try? url.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            kubeconfigPath = url.path
            kubeContexts = try Kubeconfig.contexts(from: data)
            selectedContextNames = Set(kubeContexts.map(\.name))  // default: all
            step = .kubeconfigContexts
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    func toggleContext(_ name: String) {
        if selectedContextNames.contains(name) {
            selectedContextNames.remove(name)
        } else {
            selectedContextNames.insert(name)
        }
    }

    func selectedKubeconfigConnections(now: Date) -> [ClusterConnection] {
        kubeContexts
            .filter { selectedContextNames.contains($0.name) }
            .map { context in
                ClusterConnection(
                    displayName: context.name,
                    source: .kubeconfig(
                        KubeconfigRef(
                            path: kubeconfigPath, contextName: context.name, bookmark: kubeconfigBookmark)),
                    addedAt: now,
                    server: context.server.isEmpty ? nil : context.server,
                    contextName: context.name)
            }
    }

    func chooseAzure() {
        error = nil
        step = account == nil ? .azureSignIn : .azureSubscriptions
    }

    func signIn() async {
        await run {
            account = try await azure.signIn()
            subscriptions = try await azure.listSubscriptions()
            step = .azureSubscriptions
        }
    }

    func pick(_ subscription: AzureSubscription) async {
        selectedSubscription = subscription
        selectedClusterIDs = []
        await run {
            clusters = try await azure.listClusters(inSubscription: subscription.subscriptionID)
            step = .azureClusters
        }
    }

    func toggle(_ cluster: AzureManagedCluster) {
        if selectedClusterIDs.contains(cluster.id) {
            selectedClusterIDs.remove(cluster.id)
        } else {
            selectedClusterIDs.insert(cluster.id)
        }
    }

    /// The connections for the chosen clusters, stamped with `now`.
    func selectedConnections(now: Date) -> [ClusterConnection] {
        clusters
            .filter { selectedClusterIDs.contains($0.id) }
            .map { $0.connection(addedAt: now) }
    }

    private func run(_ work: () async throws -> Void) async {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            self.error = String(describing: error)
        }
    }
}
