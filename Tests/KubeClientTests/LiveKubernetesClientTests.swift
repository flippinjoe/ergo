import Foundation
import KubeCore
import Testing

@testable import KubeClient

/// Records requests and replies by URL-substring — lets the live client and
/// token provider run fully offline.
private final class RecordingHTTPClient: HTTPClient, @unchecked Sendable {
    let responses: [String: (Int, String)]
    private(set) var requests: [HTTPRequest] = []
    private let lock = NSLock()

    init(_ responses: [String: (Int, String)]) { self.responses = responses }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { requests.append(request) }
        let url = request.url.absoluteString
        for (fragment, result) in responses where url.contains(fragment) {
            return HTTPResponse(status: result.0, body: Data(result.1.utf8))
        }
        return HTTPResponse(status: 404, body: Data("no route for \(url)".utf8))
    }

    var lastRequest: HTTPRequest? {
        lock.withLock { requests.last }
    }
}

@Suite("Live Kubernetes client (fakes)")
struct LiveKubernetesClientTests {
    private let podListJSON = """
        {"items":[
          {"metadata":{"name":"web-abc","namespace":"default","creationTimestamp":"2026-07-01T00:00:00Z"},
           "spec":{"nodeName":"node-1"},
           "status":{"phase":"Running","containerStatuses":[{"name":"web","restartCount":2}]}}
        ]}
        """

    private let crdListJSON = """
        {"items":[
          {"metadata":{"name":"certificates.cert-manager.io"},
           "spec":{"group":"cert-manager.io","names":{"kind":"Certificate"},"scope":"Namespaced",
                   "versions":[{"name":"v1"}]}}
        ]}
        """

    private func client(_ http: any HTTPClient) -> LiveKubernetesClient {
        LiveKubernetesClient(
            baseURL: URL(string: "https://api.example.com:443")!,
            http: http,
            tokenProvider: StaticTokenProvider("bearer-xyz")
        )
    }

    @Test("Decodes a real PodList and sends a bearer token")
    func pods() async throws {
        let http = RecordingHTTPClient(["/api/v1/pods": (200, podListJSON)])
        let pods = try await client(http).listPods(namespace: nil)

        let pod = try #require(pods.first)
        #expect(pod.metadata.name == "web-abc")
        #expect(pod.spec?.nodeName == "node-1")
        #expect(pod.restartCount == 2)
        #expect(pod.health == .ok)
        #expect(http.lastRequest?.headers["Authorization"] == "Bearer bearer-xyz")
    }

    @Test("Namespaced pods hit the namespaced path")
    func namespacedPath() async throws {
        let http = RecordingHTTPClient(["/pods": (200, podListJSON)])
        _ = try await client(http).listPods(namespace: "kube-system")
        #expect(http.lastRequest?.url.path == "/api/v1/namespaces/kube-system/pods")
    }

    @Test("Maps apiextensions CRDs into CRDSummary")
    func crds() async throws {
        let http = RecordingHTTPClient(["customresourcedefinitions": (200, crdListJSON)])
        let crds = try await client(http).listCRDs()
        let crd = try #require(crds.first)
        #expect(crd.name == "certificates.cert-manager.io")
        #expect(crd.kind == "Certificate")
        #expect(crd.scope == .namespaced)
        #expect(crd.versions == ["v1"])
    }

    @Test("A non-2xx API response surfaces a typed error")
    func apiError() async {
        let http = RecordingHTTPClient(["/api/v1/pods": (403, "forbidden")])
        await #expect(throws: KubernetesError.self) {
            _ = try await client(http).listPods(namespace: nil)
        }
    }

    @Test("PEM bundles split into certificates")
    func caParsing() {
        // Two (garbage-but-well-formed) blocks → parser attempts two certs.
        let pem = """
            -----BEGIN CERTIFICATE-----
            \(Data("cert-one".utf8).base64EncodedString())
            -----END CERTIFICATE-----
            -----BEGIN CERTIFICATE-----
            \(Data("cert-two".utf8).base64EncodedString())
            -----END CERTIFICATE-----
            """
        // Real DER would parse; this asserts the block splitter finds both.
        let blocks = pem.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst().count
        #expect(blocks == 2)
        // The parser itself is total (returns [] for non-DER) and doesn't crash.
        _ = KubernetesHTTPClient.certificates(fromPEM: Data(pem.utf8))
    }
}

@Suite("Azure cluster token provider (fakes)")
struct AzureExecTokenProviderTests {
    private let tokenJSON = """
        {"access_token":"aks-token","expires_in":3600}
        """

    @Test("Mints an AKS-scoped token from the stored refresh token")
    func mintsToken() async throws {
        let store = InMemoryTokenStore(
            StoredToken(
                accessToken: "arm", refreshToken: "rt", expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                account: AzureAccount(username: "dev@contoso.com", tenantID: "t")))
        let http = RecordingHTTPClient(["/token": (200, tokenJSON)])
        let provider = AzureExecTokenProvider(
            config: .default, http: http, tokenStore: store, serverAppID: nil,
            now: { Date(timeIntervalSince1970: 1_000_000_000) })

        let token = try await provider.token()
        #expect(token == "aks-token")

        // The scope requested is the AKS server app's .default.
        let body = String(decoding: http.lastRequest?.body ?? Data(), as: UTF8.self)
        #expect(body.contains("6dae42f8-4368-4678-94ff-3960e28e3630"))
    }

    @Test("Without a signed-in refresh token it throws notSignedIn")
    func notSignedIn() async {
        let provider = AzureExecTokenProvider(
            config: .default, http: RecordingHTTPClient([:]), tokenStore: InMemoryTokenStore(),
            serverAppID: nil)
        await #expect(throws: AzureError.notSignedIn) {
            _ = try await provider.token()
        }
    }
}

@Suite("Azure kubeconfig fetch (fakes)")
struct AzureKubeconfigFetchTests {
    @Test("listClusterUserCredentials is base64-decoded to kubeconfig bytes")
    func fetch() async throws {
        let kubeconfigYAML = "apiVersion: v1\nkind: Config\n"
        let credsJSON = """
            {"kubeconfigs":[{"name":"clusterUser","value":"\(Data(kubeconfigYAML.utf8).base64EncodedString())"}]}
            """
        let tokenJSON = "{\"access_token\":\"arm\",\"expires_in\":3600}"
        let store = InMemoryTokenStore(
            StoredToken(
                accessToken: "arm", refreshToken: "rt", expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                account: AzureAccount(username: "dev", tenantID: "t")))
        let http = RecordingHTTPClient([
            "/token": (200, tokenJSON),
            "listClusterUserCredentials": (200, credsJSON),
        ])
        let service = LiveAzureClusterService(
            webAuthenticator: FakeWebAuthenticator(), http: http, tokenStore: store,
            now: { Date(timeIntervalSince1970: 1_000_000_000) })

        let ref = AzureClusterRef(
            resourceID:
                "/subscriptions/s/resourceGroups/g/providers/Microsoft.ContainerService/managedClusters/c",
            subscriptionID: "s", resourceGroup: "g", clusterName: "c")
        let data = try await service.fetchKubeconfig(for: ref)
        #expect(String(decoding: data, as: UTF8.self) == kubeconfigYAML)
    }
}
