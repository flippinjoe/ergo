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
            let data = try Data(contentsOf: URL(fileURLWithPath: ref.path))
            return try liveClient(from: try Kubeconfig.parse(data))
        }
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
