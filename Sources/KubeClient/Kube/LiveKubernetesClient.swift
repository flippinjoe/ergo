import Foundation
import KubeCore

/// A `ClusterClient` that talks to a real Kubernetes API server. TLS trust (the
/// cluster CA) is handled by the injected `HTTPClient`; this type adds the
/// bearer token and decodes list responses into the domain types.
///
/// Read-only: only GETs. Nothing here can mutate a cluster.
public struct LiveKubernetesClient: ClusterClient {
    private let baseURL: URL
    private let http: any HTTPClient
    private let tokenProvider: any ClusterTokenProvider
    private let decoder: JSONDecoder

    public init(baseURL: URL, http: any HTTPClient, tokenProvider: any ClusterTokenProvider) {
        self.baseURL = baseURL
        self.http = http
        self.tokenProvider = tokenProvider
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func listPods(namespace: String?) async throws -> [Pod] {
        try await list(path(core: "pods", namespace: namespace), as: ItemList<Pod>.self).items
    }

    public func listDeployments(namespace: String?) async throws -> [Deployment] {
        try await list(
            path(group: "apis/apps/v1", resource: "deployments", namespace: namespace),
            as: ItemList<Deployment>.self
        ).items
    }

    public func listEvents(namespace: String?) async throws -> [EventRecord] {
        try await list(path(core: "events", namespace: namespace), as: ItemList<EventRecord>.self).items
    }

    public func listCRDs() async throws -> [CRDSummary] {
        let list = try await list(
            "/apis/apiextensions.k8s.io/v1/customresourcedefinitions", as: ItemList<CRD>.self)
        return list.items.map(\.summary)
    }

    // MARK: - Request

    private func list<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        let token = try await tokenProvider.token()
        let request = HTTPRequest(
            method: .get,
            url: baseURL.appendingPathComponent(path),
            headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"]
        )
        let response = try await http.send(request)
        guard response.isSuccess else {
            throw KubernetesError.api(
                status: response.status, body: "GET \(request.url.absoluteString) — \(response.bodyText)")
        }
        return try decoder.decode(T.self, from: response.body)
    }

    private func path(core resource: String, namespace: String?) -> String {
        if let namespace { return "/api/v1/namespaces/\(namespace)/\(resource)" }
        return "/api/v1/\(resource)"
    }

    private func path(group: String, resource: String, namespace: String?) -> String {
        if let namespace { return "/\(group)/namespaces/\(namespace)/\(resource)" }
        return "/\(group)/\(resource)"
    }

    private struct ItemList<Element: Decodable & Sendable>: Decodable, Sendable {
        let items: [Element]
    }
}

public enum KubernetesError: Error, Sendable, Equatable {
    case api(status: Int, body: String)
}

/// Minimal decode of an apiextensions.k8s.io/v1 CRD → our `CRDSummary`.
private struct CRD: Decodable, Sendable {
    let metadata: Meta
    let spec: Spec

    struct Meta: Decodable, Sendable { let name: String }
    struct Spec: Decodable, Sendable {
        let group: String
        let names: Names
        let scope: String
        let versions: [Version]
        struct Names: Decodable, Sendable { let kind: String }
        struct Version: Decodable, Sendable { let name: String }
    }

    var summary: CRDSummary {
        CRDSummary(
            name: metadata.name,
            group: spec.group,
            kind: spec.names.kind,
            versions: spec.versions.map(\.name),
            scope: CRDSummary.Scope(rawValue: spec.scope) ?? .namespaced
        )
    }
}
