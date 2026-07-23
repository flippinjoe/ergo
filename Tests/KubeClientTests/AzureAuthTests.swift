import Foundation
import KubeCore
import Testing

@testable import KubeClient

@Suite("PKCE")
struct PKCETests {
    @Test("S256 challenge matches the RFC 7636 test vector")
    func rfcVector() {
        // From RFC 7636 Appendix B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Generated verifiers are URL-safe and unique")
    func generated() {
        let a = PKCE.generate()
        let b = PKCE.generate()
        #expect(a.verifier != b.verifier)
        #expect(a.method == "S256")
        #expect(
            a.verifier.allSatisfy {
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".contains($0)
            })
    }
}

@Suite("Authorization URL")
struct AuthorizationURLTests {
    @Test("Carries PKCE, redirect, scopes, and state")
    func query() throws {
        let pkce = PKCE(verifier: "verifier-123")
        let url = authorizationURL(
            config: .default,
            pkce: pkce,
            redirectURI: URL(string: "http://localhost:51820/")!,
            state: "xyz"
        )
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }

        #expect(
            url.absoluteString.hasPrefix(
                "https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize"))
        #expect(value("client_id") == "04b07795-8ddb-461a-bbee-02f9e1bf7b46")
        #expect(value("response_type") == "code")
        #expect(value("code_challenge") == pkce.challenge)
        #expect(value("code_challenge_method") == "S256")
        #expect(value("redirect_uri") == "http://localhost:51820/")
        #expect(value("state") == "xyz")
        #expect(value("scope")?.contains("https://management.azure.com/.default") == true)
    }
}

@Suite("ResourceID parsing")
struct ResourceIDTests {
    @Test("Extracts the resource group case-insensitively")
    func resourceGroup() {
        let id =
            "/subscriptions/s/resourceGroups/my-rg/providers/Microsoft.ContainerService/managedClusters/c"
        #expect(AzureARMClient.resourceGroup(fromID: id) == "my-rg")
        #expect(AzureARMClient.resourceGroup(fromID: "/nope") == nil)
    }
}

@Suite("Live Azure service (fakes)")
struct LiveAzureServiceTests {
    /// Routes canned responses by URL path so the whole flow runs offline.
    private struct RouterHTTPClient: HTTPClient {
        let responses: [String: (Int, String)]
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            let path = request.url.path
            for (fragment, result) in responses
            where path.contains(fragment) || request.url.absoluteString.contains(fragment) {
                return HTTPResponse(status: result.0, body: Data(result.1.utf8))
            }
            return HTTPResponse(status: 404, body: Data("no route for \(request.url)".utf8))
        }
    }

    /// A minimal unsigned JWT (header.payload.sig) with the given claims.
    private func idToken(_ claims: [String: String]) -> String {
        func seg(_ obj: [String: String]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: obj)
            return data.base64URLEncodedString()
        }
        return "\(seg(["alg": "none"])).\(seg(claims)).sig"
    }

    private var tokenJSON: String {
        """
        {"access_token":"at-123","refresh_token":"rt-123","expires_in":3600,
         "id_token":"\(idToken(["preferred_username": "dev@contoso.com", "tid": "contoso-tid"]))"}
        """
    }

    private let subscriptionsJSON = """
        {"value":[
          {"subscriptionId":"11111111","displayName":"Contoso Production","tenantId":"contoso-tid"},
          {"subscriptionId":"22222222","displayName":"Contoso Sandbox","tenantId":"contoso-tid"}
        ]}
        """

    private let clustersJSON = """
        {"value":[
          {"id":"/subscriptions/11111111/resourceGroups/prod-eastus/providers/Microsoft.ContainerService/managedClusters/prod-eus",
           "name":"prod-eus","location":"eastus",
           "properties":{"kubernetesVersion":"1.31.1","powerState":{"code":"Running"}}}
        ]}
        """

    private func makeService(
        http: HTTPClient,
        store: TokenStore = InMemoryTokenStore(),
        now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000_000_000) }
    ) -> LiveAzureClusterService {
        LiveAzureClusterService(
            webAuthenticator: FakeWebAuthenticator(code: "code-abc"),
            http: http,
            tokenStore: store,
            now: now
        )
    }

    @Test("Sign-in exchanges the code and parses the account from the id_token")
    func signIn() async throws {
        let store = InMemoryTokenStore()
        let service = makeService(
            http: RouterHTTPClient(responses: ["/token": (200, tokenJSON)]), store: store)

        let account = try await service.signIn()
        #expect(account.username == "dev@contoso.com")
        #expect(account.tenantID == "contoso-tid")

        // Tokens were persisted for later ARM calls.
        let stored = try await store.load()
        #expect(stored?.accessToken == "at-123")
        #expect(stored?.refreshToken == "rt-123")
    }

    @Test("Discovery uses the stored token to list subscriptions and clusters")
    func discovery() async throws {
        let http = RouterHTTPClient(responses: [
            "/token": (200, tokenJSON),
            "/subscriptions?": (200, subscriptionsJSON),
            "managedClusters": (200, clustersJSON),
        ])
        let service = makeService(http: http)
        _ = try await service.signIn()

        let subs = try await service.listSubscriptions()
        #expect(subs.map(\.displayName) == ["Contoso Production", "Contoso Sandbox"])

        let clusters = try await service.listClusters(inSubscription: "11111111")
        let cluster = try #require(clusters.first)
        #expect(cluster.name == "prod-eus")
        #expect(cluster.resourceGroup == "prod-eastus")
        #expect(cluster.health == .ok)
        #expect(cluster.tenantID == "contoso-tid")  // carried from the signed-in account
    }

    @Test("Discovery before sign-in throws notSignedIn")
    func notSignedIn() async {
        let service = makeService(http: RouterHTTPClient(responses: [:]))
        await #expect(throws: AzureError.notSignedIn) {
            _ = try await service.listSubscriptions()
        }
    }

    @Test("An expired access token is refreshed before ARM calls")
    func refresh() async throws {
        let store = InMemoryTokenStore(
            StoredToken(
                accessToken: "old",
                refreshToken: "rt-old",
                expiresAt: Date(timeIntervalSince1970: 900_000_000),  // long past "now"
                account: AzureAccount(username: "dev@contoso.com", tenantID: "contoso-tid")
            ))
        let http = RouterHTTPClient(responses: [
            "/token": (200, tokenJSON),  // refresh returns a fresh access token
            "/subscriptions?": (200, subscriptionsJSON),
        ])
        let service = makeService(http: http, store: store)

        _ = try await service.listSubscriptions()
        let refreshed = try await store.load()
        #expect(refreshed?.accessToken == "at-123")
    }

    @Test("A cancelled / errored callback surfaces authenticationFailed")
    func authError() async {
        let service = LiveAzureClusterService(
            webAuthenticator: FakeWebAuthenticator(error: "access_denied"),
            http: RouterHTTPClient(responses: [:]),
            tokenStore: InMemoryTokenStore()
        )
        await #expect(throws: AzureError.self) {
            _ = try await service.signIn()
        }
    }
}
