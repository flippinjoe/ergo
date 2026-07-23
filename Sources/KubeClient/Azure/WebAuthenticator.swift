import Foundation

/// The result of the interactive sign-in: the full callback URL the redirect
/// landed on, plus the redirect URI that was actually used (the token exchange
/// must send the same value).
public struct AuthCallback: Sendable {
    public let callbackURL: URL
    public let redirectURI: URL

    public init(callbackURL: URL, redirectURI: URL) {
        self.callbackURL = callbackURL
        self.redirectURI = redirectURI
    }
}

/// Performs the interactive browser step. The concrete implementation (loopback
/// listener + system browser) lives in the app layer, where AppKit is
/// available; `LiveAzureClusterService` depends only on this protocol so it
/// stays testable.
///
/// The implementation owns the redirect URI (it picks the loopback port), so it
/// asks the caller to build the authorization URL from that redirect.
public protocol WebAuthenticator: Sendable {
    func authenticate(redirectURIBuilder: @escaping @Sendable (URL) -> URL) async throws -> AuthCallback
}

/// Test double: skips the browser, echoes the `state` from the built URL, and
/// returns a canned code — so the full sign-in path can be exercised offline.
public struct FakeWebAuthenticator: WebAuthenticator {
    let code: String
    let redirectURI: URL
    let errorParam: String?

    public init(
        code: String = "fake-auth-code",
        redirectURI: URL = URL(string: "http://localhost:0/")!,
        error: String? = nil
    ) {
        self.code = code
        self.redirectURI = redirectURI
        self.errorParam = error
    }

    public func authenticate(
        redirectURIBuilder: @escaping @Sendable (URL) -> URL
    ) async throws -> AuthCallback {
        let authorizeURL = redirectURIBuilder(redirectURI)
        let state = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value

        var callback = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false)!
        if let errorParam {
            callback.queryItems = [URLQueryItem(name: "error", value: errorParam)]
        } else {
            callback.queryItems = [
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "state", value: state),
            ]
        }
        return AuthCallback(callbackURL: callback.url!, redirectURI: redirectURI)
    }
}
