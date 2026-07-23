import Foundation
import KubeCore
import Security

/// Pillar 3 (auth & agents): the boundary for discovering clusters from Azure.
/// The UI drives this three-step flow — sign in, list subscriptions, list the
/// AKS clusters in one — and never knows whether it's talking to a mock or the
/// real Azure Resource Manager.
public protocol AzureClusterService: Sendable {
    /// Interactive Microsoft sign-in. Returns the signed-in identity; tokens are
    /// stored securely by the implementation, not handed back here.
    func signIn() async throws -> AzureAccount
    func listSubscriptions() async throws -> [AzureSubscription]
    func listClusters(inSubscription subscriptionID: String) async throws -> [AzureManagedCluster]
    /// Fetches the cluster's kubeconfig (user credentials). Returns the raw
    /// kubeconfig YAML bytes.
    func fetchKubeconfig(for cluster: AzureClusterRef) async throws -> Data
}

/// Errors across the Azure boundary.
public enum AzureError: Error, Sendable, Equatable {
    case notSignedIn
    case fixtureNotFound(String)
    case authenticationFailed(String)
    case httpError(status: Int, body: String)
    case invalidCallback(String)
    case cancelled
    case keychain(OSStatus)
}

/// Fixture-backed Azure service for previews and tests. Fully hermetic: no
/// network, no real sign-in. Lets the entire add-cluster UX be built and tested
/// before the live ARM calls land.
public struct FakeAzureClusterService: AzureClusterService {
    private let account: AzureAccount
    private let decoder = JSONDecoder.iso8601

    public init(
        account: AzureAccount = AzureAccount(username: "dev@contoso.com", tenantID: "contoso.onmicrosoft.com")
    ) {
        self.account = account
    }

    public func signIn() async throws -> AzureAccount { account }

    public func listSubscriptions() async throws -> [AzureSubscription] {
        try load("azure-subscriptions", as: ItemList<AzureSubscription>.self).items
    }

    public func listClusters(inSubscription subscriptionID: String) async throws -> [AzureManagedCluster] {
        try load("azure-clusters", as: ItemList<AzureManagedCluster>.self).items
            .filter { $0.subscriptionID == subscriptionID }
    }

    public func fetchKubeconfig(for cluster: AzureClusterRef) async throws -> Data {
        // A minimal embedded-token kubeconfig so the mock path can build a
        // (non-functional) client without a real cluster.
        Data(
            """
            apiVersion: v1
            kind: Config
            current-context: \(cluster.clusterName)
            clusters:
            - name: \(cluster.clusterName)
              cluster:
                server: https://\(cluster.clusterName).example.invalid:443
            contexts:
            - name: \(cluster.clusterName)
              context:
                cluster: \(cluster.clusterName)
                user: \(cluster.clusterName)
            users:
            - name: \(cluster.clusterName)
              user:
                token: fake-token
            """.utf8)
    }

    private struct ItemList<Element: Decodable & Sendable>: Decodable, Sendable {
        let items: [Element]
    }

    private func load<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: name, withExtension: "json")
        else {
            throw AzureError.fixtureNotFound("\(name).json")
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }
}
