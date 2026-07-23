import Foundation
import KubeCore

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
}

/// Errors across the Azure boundary.
public enum AzureError: Error, Sendable, Equatable {
    case notSignedIn
    case notImplemented
    case fixtureNotFound(String)
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

/// The live Azure service — **not implemented yet** (agreed next step). Kept as
/// a concrete seam so swapping the mock for real calls is a one-line change at
/// the app's composition root.
///
/// The planned flow, all on-device, kubeconfig never leaving this Mac:
///  1. Sign in with `ASWebAuthenticationSession` (authorization-code + PKCE)
///     against Microsoft's well-known public client
///     `04b07795-8ddb-461a-bbee-02f9e1bf7b46` (the same client `az`/`kubelogin`
///     use — no app registration required); cache tokens in the Keychain.
///  2. `GET https://management.azure.com/subscriptions?api-version=2022-12-01`
///     for subscriptions.
///  3. `GET …/subscriptions/{id}/providers/Microsoft.ContainerService/managedClusters?api-version=2024-05-01`
///     for AKS clusters.
///  4. On add, `POST …/managedClusters/{name}/listClusterUserCredentials` to
///     fetch the kubeconfig (never admin credentials).
public struct LiveAzureClusterService: AzureClusterService {
    public init() {}

    public func signIn() async throws -> AzureAccount { throw AzureError.notImplemented }
    public func listSubscriptions() async throws -> [AzureSubscription] { throw AzureError.notImplemented }
    public func listClusters(inSubscription subscriptionID: String) async throws -> [AzureManagedCluster] {
        throw AzureError.notImplemented
    }
}
