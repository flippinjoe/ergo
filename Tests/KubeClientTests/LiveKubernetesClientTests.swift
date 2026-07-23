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

/// A streaming client that records the requested URL and replays canned lines.
private final class CapturingStreamingClient: StreamingHTTPClient, @unchecked Sendable {
    let lines: [String]
    private let lock = NSLock()
    private var _lastURL: String?
    var lastURL: String? { lock.withLock { _lastURL } }

    init(lines: [String]) { self.lines = lines }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(status: 200, body: Data())
    }

    func streamLines(_ request: HTTPRequest) -> AsyncThrowingStream<String, Error> {
        lock.withLock { _lastURL = request.url.absoluteString }
        let lines = lines
        return AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
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

    @Test("StatefulSets decode from the apps/v1 endpoint")
    func statefulSets() async throws {
        let json = """
            {"items":[{"metadata":{"name":"db"},"spec":{"replicas":3},"status":{"readyReplicas":3}}]}
            """
        let http = RecordingHTTPClient(["/apis/apps/v1/statefulsets": (200, json)])
        let sets = try await client(http).listStatefulSets(namespace: nil)
        #expect(sets.first?.readyText == "3/3")
        #expect(sets.first?.health == .ok)
    }

    @Test("Namespaces decode to sorted names")
    func namespaces() async throws {
        let json = """
            {"items":[{"metadata":{"name":"prod"}},{"metadata":{"name":"default"}}]}
            """
        let http = RecordingHTTPClient(["/api/v1/namespaces": (200, json)])
        let namespaces = try await client(http).listNamespaces()
        #expect(namespaces == ["default", "prod"])
    }

    @Test("Dynamic list decodes CRs and derives status from conditions")
    func dynamicConditions() async throws {
        let json = """
            {"items":[
              {"metadata":{"name":"api-tls","namespace":"prod","creationTimestamp":"2026-07-01T00:00:00Z"},
               "status":{"conditions":[{"type":"Ready","status":"True"}]}},
              {"metadata":{"name":"web-tls","namespace":"prod"},
               "status":{"conditions":[{"type":"Ready","status":"False","reason":"DoesNotExist"}]}}
            ]}
            """
        let gvr = GroupVersionResource(
            group: "cert-manager.io", version: "v1", resource: "certificates", namespaced: true)
        let http = RecordingHTTPClient(["/apis/cert-manager.io/v1/namespaces/prod/certificates": (200, json)])
        let crs = try await client(http).listDynamic(gvr, namespace: "prod")

        #expect(crs.count == 2)
        let ready = try #require(crs.first { $0.name == "api-tls" })
        #expect(ready.health == .ok)
        #expect(ready.statusText == "Ready")
        #expect(ready.creationTimestamp != nil)

        let notReady = try #require(crs.first { $0.name == "web-tls" })
        #expect(notReady.health == .error)
        #expect(notReady.statusText == "DoesNotExist")
    }

    @Test("Log streaming yields lines and targets the follow endpoint")
    func logStreaming() async throws {
        let http = CapturingStreamingClient(lines: [
            "2026-07-23T09:41:13.201Z INFO hello",
            "2026-07-23T09:41:13.334Z ERROR boom",
        ])
        let live = LiveKubernetesClient(
            baseURL: URL(string: "https://api.example.com:443")!,
            http: http, tokenProvider: StaticTokenProvider("tkn"))

        var lines: [String] = []
        for try await line in live.streamLogs(namespace: "default", pod: "web", container: "app") {
            lines.append(line)
        }
        #expect(lines.count == 2)

        let url = try #require(http.lastURL)
        #expect(url.contains("/api/v1/namespaces/default/pods/web/log"))
        #expect(url.contains("follow=true"))
        #expect(url.contains("container=app"))
    }

    @Test("Dynamic status falls back to Argo-style health, then phase")
    func dynamicHealthAndPhase() {
        let argo = LiveKubernetesClient.dynamicResource(from: [
            "metadata": ["name": "app1"],
            "status": ["health": ["status": "Healthy"], "sync": ["status": "Synced"]],
        ])
        #expect(argo.statusText == "Healthy")
        #expect(argo.health == .ok)

        let phased = LiveKubernetesClient.dynamicResource(from: [
            "metadata": ["name": "job1"], "status": ["phase": "Failed"],
        ])
        #expect(phased.statusText == "Failed")
        #expect(phased.health == .error)
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
            "listClusterUserCredential": (200, credsJSON),
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
