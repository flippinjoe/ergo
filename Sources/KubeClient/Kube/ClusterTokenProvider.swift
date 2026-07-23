import Foundation

/// Supplies a bearer token for the cluster's API server. The live Kubernetes
/// client asks for one on each request set; implementations cache as needed.
public protocol ClusterTokenProvider: Sendable {
    func token() async throws -> String
}

/// A fixed token (embedded-token kubeconfigs).
public struct StaticTokenProvider: ClusterTokenProvider {
    private let value: String
    public init(_ value: String) { self.value = value }
    public func token() async throws -> String { value }
}

/// Mints an Entra token scoped to the AKS AAD server app by redeeming the
/// signed-in refresh token — the equivalent of what `kubelogin` does, without
/// shelling out. Tokens are cached until near expiry.
public actor AzureExecTokenProvider: ClusterTokenProvider {
    private let tokenClient: AzureTokenClient
    private let tokenStore: any TokenStore
    private let scopes: [String]
    private let now: @Sendable () -> Date

    private var cached: (token: String, expiresAt: Date)?

    init(
        config: AzureOAuthConfig,
        http: any HTTPClient,
        tokenStore: any TokenStore,
        serverAppID: String?,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.tokenClient = AzureTokenClient(config: config, http: http)
        self.tokenStore = tokenStore
        let appID = serverAppID ?? AzureOAuthConfig.aksServerAppID
        self.scopes = ["\(appID)/.default", "offline_access"]
        self.now = now
    }

    public func token() async throws -> String {
        if let cached, now().addingTimeInterval(60) < cached.expiresAt {
            return cached.token
        }
        guard let stored = try await tokenStore.load(), let refreshToken = stored.refreshToken else {
            throw AzureError.notSignedIn
        }
        let response = try await tokenClient.refresh(refreshToken: refreshToken, scopes: scopes)
        let expires = now().addingTimeInterval(TimeInterval(response.expiresIn))
        cached = (response.accessToken, expires)
        return response.accessToken
    }
}
