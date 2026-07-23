import Foundation

/// Endpoints, client, and scopes for signing in to Azure. Defaults to
/// Microsoft's well-known public client (the one `az`/`kubelogin` use), so no
/// app registration is required.
public struct AzureOAuthConfig: Sendable {
    public var authority: String
    public var clientID: String
    public var scopes: [String]

    public init(authority: String, clientID: String, scopes: [String]) {
        self.authority = authority
        self.clientID = clientID
        self.scopes = scopes
    }

    public var authorizationEndpoint: URL { URL(string: authority + "/oauth2/v2.0/authorize")! }
    public var tokenEndpoint: URL { URL(string: authority + "/oauth2/v2.0/token")! }

    /// ARM resource base.
    public static let armBaseURL = URL(string: "https://management.azure.com")!

    public static let `default` = AzureOAuthConfig(
        // `organizations` = work/school (Azure) accounts; excludes personal MSAs
        // which can't hold Azure subscriptions.
        authority: "https://login.microsoftonline.com/organizations",
        clientID: "04b07795-8ddb-461a-bbee-02f9e1bf7b46",
        scopes: [
            "https://management.azure.com/.default",
            "offline_access", "openid", "profile",
        ]
    )
}

/// Builds the authorization URL the browser opens.
func authorizationURL(config: AzureOAuthConfig, pkce: PKCE, redirectURI: URL, state: String) -> URL {
    var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
    components.queryItems = [
        URLQueryItem(name: "client_id", value: config.clientID),
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
        URLQueryItem(name: "response_mode", value: "query"),
        URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
        URLQueryItem(name: "state", value: state),
        URLQueryItem(name: "code_challenge", value: pkce.challenge),
        URLQueryItem(name: "code_challenge_method", value: pkce.method),
        URLQueryItem(name: "prompt", value: "select_account"),
    ]
    return components.url!
}

/// The token endpoint's response (snake_case from Microsoft identity platform).
struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }
}

/// The token endpoint's error shape.
struct TokenErrorResponse: Decodable, Sendable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

/// Exchanges an authorization code for tokens and refreshes them. Talks only
/// through `HTTPClient`, so it's fully testable.
struct AzureTokenClient: Sendable {
    let config: AzureOAuthConfig
    let http: any HTTPClient

    func exchange(code: String, redirectURI: URL, pkce: PKCE) async throws -> TokenResponse {
        try await post([
            "client_id": config.clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI.absoluteString,
            "code_verifier": pkce.verifier,
            "scope": config.scopes.joined(separator: " "),
        ])
    }

    func refresh(refreshToken: String) async throws -> TokenResponse {
        try await post([
            "client_id": config.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": config.scopes.joined(separator: " "),
        ])
    }

    private func post(_ form: [String: String]) async throws -> TokenResponse {
        let body =
            form
            .map { "\(Self.escape($0.key))=\(Self.escape($0.value))" }
            .joined(separator: "&")
        let request = HTTPRequest(
            method: .post,
            url: config.tokenEndpoint,
            headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
            body: Data(body.utf8)
        )
        let response = try await http.send(request)
        guard response.isSuccess else {
            if let err = try? JSONDecoder().decode(TokenErrorResponse.self, from: response.body) {
                throw AzureError.authenticationFailed(err.errorDescription ?? err.error)
            }
            throw AzureError.httpError(status: response.status, body: response.bodyText)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: response.body)
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
