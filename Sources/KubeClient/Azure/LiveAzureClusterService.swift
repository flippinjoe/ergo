import Foundation
import KubeCore

/// The real Azure discovery service: interactive Microsoft sign-in (auth-code +
/// PKCE against the well-known public client), token caching in the Keychain,
/// and read-only ARM discovery of subscriptions and AKS clusters.
///
/// Every side effect is injected — the browser (`WebAuthenticator`), the network
/// (`HTTPClient`), and secure storage (`TokenStore`) — so the whole flow is
/// unit-tested with fakes and never touches the real world in tests.
///
/// Swap it in at the app's composition root:
/// ```
/// LiveAzureClusterService(webAuthenticator: SystemWebAuthenticator(), tokenStore: KeychainTokenStore())
/// ```
public struct LiveAzureClusterService: AzureClusterService {
    private let config: AzureOAuthConfig
    private let webAuth: any WebAuthenticator
    private let tokens: any TokenStore
    private let tokenClient: AzureTokenClient
    private let arm: AzureARMClient
    private let now: @Sendable () -> Date

    public init(
        webAuthenticator: any WebAuthenticator,
        http: any HTTPClient = URLSessionHTTPClient(),
        tokenStore: any TokenStore,
        config: AzureOAuthConfig = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.config = config
        self.webAuth = webAuthenticator
        self.tokens = tokenStore
        self.tokenClient = AzureTokenClient(config: config, http: http)
        self.arm = AzureARMClient(http: http)
        self.now = now
    }

    // MARK: AzureClusterService

    public func signIn() async throws -> AzureAccount {
        let pkce = PKCE.generate()
        let state = randomBase64URL(byteCount: 16)

        let callback = try await webAuth.authenticate { redirectURI in
            authorizationURL(config: config, pkce: pkce, redirectURI: redirectURI, state: state)
        }

        let items = URLComponents(url: callback.callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw AzureError.authenticationFailed(value("error_description") ?? error)
        }
        guard value("state") == state else {
            throw AzureError.invalidCallback("state mismatch")
        }
        guard let code = value("code") else {
            throw AzureError.invalidCallback("no authorization code in callback")
        }

        let response = try await tokenClient.exchange(
            code: code, redirectURI: callback.redirectURI, pkce: pkce)
        let account = Self.account(fromIDToken: response.idToken)
        try await tokens.save(stored(from: response, account: account, previousRefresh: nil))
        return account
    }

    public func listSubscriptions() async throws -> [AzureSubscription] {
        try await arm.subscriptions(accessToken: validAccessToken())
    }

    public func listClusters(inSubscription subscriptionID: String) async throws -> [AzureManagedCluster] {
        let token = try await loadToken()
        return try await arm.managedClusters(
            accessToken: try await validAccessToken(),
            subscriptionID: subscriptionID,
            tenantID: token.account.tenantID
        )
    }

    public func fetchKubeconfig(for cluster: AzureClusterRef) async throws -> Data {
        try await arm.userKubeconfig(accessToken: validAccessToken(), cluster: cluster)
    }

    // MARK: Token lifecycle

    private func loadToken() async throws -> StoredToken {
        guard let token = try await tokens.load() else { throw AzureError.notSignedIn }
        return token
    }

    /// Returns a non-expired access token, refreshing (and re-persisting) if
    /// needed. Throws `.notSignedIn` if there's nothing to refresh with.
    private func validAccessToken() async throws -> String {
        var token = try await loadToken()
        guard token.isExpired(now: now()) else { return token.accessToken }
        guard let refreshToken = token.refreshToken else { throw AzureError.notSignedIn }
        let response = try await tokenClient.refresh(refreshToken: refreshToken)
        token = stored(from: response, account: token.account, previousRefresh: refreshToken)
        try await tokens.save(token)
        return token.accessToken
    }

    private func stored(
        from response: TokenResponse, account: AzureAccount, previousRefresh: String?
    )
        -> StoredToken
    {
        StoredToken(
            accessToken: response.accessToken,
            // Refresh responses may omit a new refresh token; keep the old one.
            refreshToken: response.refreshToken ?? previousRefresh,
            expiresAt: now().addingTimeInterval(TimeInterval(response.expiresIn)),
            account: account
        )
    }

    // MARK: id_token → account

    /// Reads `preferred_username`/`upn` and `tid` from the id_token payload. The
    /// token came straight from the token endpoint over TLS, so it's parsed for
    /// display only — no signature verification needed here.
    static func account(fromIDToken idToken: String?) -> AzureAccount {
        guard let idToken,
            case let segments = idToken.split(separator: "."), segments.count >= 2,
            let data = Data(base64URLEncoded: String(segments[1])),
            let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return AzureAccount(username: "Azure account", tenantID: "")
        }
        let username =
            (claims["preferred_username"] as? String)
            ?? (claims["upn"] as? String)
            ?? (claims["email"] as? String)
            ?? "Azure account"
        let tenant = (claims["tid"] as? String) ?? ""
        return AzureAccount(username: username, tenantID: tenant)
    }
}
