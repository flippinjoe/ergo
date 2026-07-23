import Foundation
import KubeCore
import Testing

@testable import KubeClient

/// Routes canned discovery responses by exact path.
private struct PathHTTPClient: HTTPClient {
    let bodies: [String: String]
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if let body = bodies[request.url.path] {
            return HTTPResponse(status: 200, body: Data(body.utf8))
        }
        return HTTPResponse(status: 404, body: Data("no route: \(request.url.path)".utf8))
    }
}

@Suite("API discovery")
struct DiscoveryTests {
    @Test("Discovers core + per-group resources; skips subresources and non-listables")
    func discover() async throws {
        let core = """
            {"resources":[
              {"name":"pods","namespaced":true,"kind":"Pod","verbs":["list","get"]},
              {"name":"pods/log","namespaced":true,"kind":"Pod","verbs":["get"]},
              {"name":"bindings","namespaced":true,"kind":"Binding","verbs":["create"]}
            ]}
            """
        let groups = """
            {"groups":[{"name":"apps","versions":[{"groupVersion":"apps/v1"}],
              "preferredVersion":{"groupVersion":"apps/v1"}}]}
            """
        let apps = """
            {"resources":[{"name":"deployments","namespaced":true,"kind":"Deployment","verbs":["list"]}]}
            """
        let http = PathHTTPClient(bodies: [
            "/api/v1": core, "/apis": groups, "/apis/apps/v1": apps,
        ])
        let live = LiveKubernetesClient(
            baseURL: URL(string: "https://api.example.com:443")!,
            http: http, tokenProvider: StaticTokenProvider("t"))

        let resources = try await live.discoverAPIResources()
        let ids = Set(resources.map(\.id))
        #expect(ids.contains("v1/pods"))
        #expect(ids.contains("apps/v1/deployments"))
        // Subresource and non-listable are excluded.
        #expect(!resources.contains { $0.resource.contains("/") })
        #expect(!ids.contains("v1/bindings"))

        let pods = try #require(resources.first { $0.resource == "pods" })
        #expect(pods.group.isEmpty)
        #expect(pods.namespaced)
    }
}
