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
