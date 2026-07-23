import Foundation
import KubeCore

/// Builds the right `ClusterClient` for a saved connection. The explorer asks
/// for one whenever the selected cluster changes.
public protocol ClusterClientProviding: Sendable {
    func makeClient(for connection: ClusterConnection) async throws -> any ClusterClient
}

/// Always returns the same client — for previews/tests and as the explorer's
/// default before a real factory is wired.
public struct StaticClusterClientProvider: ClusterClientProviding {
    private let client: any ClusterClient
    public init(_ client: any ClusterClient) { self.client = client }
    public func makeClient(for connection: ClusterConnection) async throws -> any ClusterClient { client }
}

/// The real factory: mock connections get demo data; Azure/kubeconfig
/// connections get a live `LiveKubernetesClient` built from the cluster's
/// kubeconfig (CA-pinned TLS + an appropriate token provider).
public struct DefaultClusterClientFactory: ClusterClientProviding {
    private let azure: any AzureClusterService
    private let tokenStore: any TokenStore
    private let config: AzureOAuthConfig
    private let demoClient: any ClusterClient
    private let authHTTP: any HTTPClient

    public init(
        azure: any AzureClusterService,
        tokenStore: any TokenStore,
        demoClient: any ClusterClient,
        config: AzureOAuthConfig = .default,
        authHTTP: any HTTPClient = URLSessionHTTPClient()
    ) {
        self.azure = azure
        self.tokenStore = tokenStore
        self.demoClient = demoClient
        self.config = config
        self.authHTTP = authHTTP
    }

    public func makeClient(for connection: ClusterConnection) async throws -> any ClusterClient {
        switch connection.source {
        case .mock:
            return demoClient
        case .azure(let ref):
            let kubeconfig = try Kubeconfig.parse(try await azure.fetchKubeconfig(for: ref))
            return try liveClient(from: kubeconfig)
        case .kubeconfig(let ref):
            let data = try readKubeconfig(ref)
            return try liveClient(from: try Kubeconfig.parse(data, context: ref.contextName))
        }
    }

    /// Reads the kubeconfig bytes, resolving a security-scoped bookmark when
    /// present (required for a sandboxed app to re-open a user-picked file after
    /// relaunch), falling back to the plain path.
    private func readKubeconfig(_ ref: KubeconfigRef) throws -> Data {
        guard let bookmark = ref.bookmark else {
            return try Data(contentsOf: URL(fileURLWithPath: ref.path))
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark, options: [.withSecurityScope],
            relativeTo: nil, bookmarkDataIsStale: &isStale)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private func liveClient(from kubeconfig: Kubeconfig) throws -> any ClusterClient {
        let http = KubernetesHTTPClient(caPEM: kubeconfig.caPEM)
        let provider: any ClusterTokenProvider
        switch kubeconfig.auth {
        case .token(let token):
            provider = StaticTokenProvider(token)
        case .azureExec(let serverAppID):
            provider = AzureExecTokenProvider(
                config: config, http: authHTTP, tokenStore: tokenStore, serverAppID: serverAppID)
        case .clientCertificate:
            throw KubeconfigError.unsupportedAuth("client-certificate auth isn't supported yet")
        case .unknown:
            throw KubeconfigError.unsupportedAuth("unrecognized kubeconfig auth")
        }
        return LiveKubernetesClient(baseURL: kubeconfig.server, http: http, tokenProvider: provider)
    }
}
