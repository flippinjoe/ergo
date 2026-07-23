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

    public func listStatefulSets(namespace: String?) async throws -> [StatefulSet] {
        try await list(
            path(group: "apis/apps/v1", resource: "statefulsets", namespace: namespace),
            as: ItemList<StatefulSet>.self
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

    public func listNamespaces() async throws -> [String] {
        try await list("/api/v1/namespaces", as: ItemList<NameOnly>.self)
            .items.map(\.metadata.name).sorted()
    }

    public func listDynamic(
        _ gvr: GroupVersionResource, namespace: String?
    ) async throws
        -> [DynamicResource]
    {
        let data = try await get(gvr.listPath(namespace: namespace))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = root?["items"] as? [[String: Any]] ?? []
        return items.map(Self.dynamicResource(from:))
    }

    public func streamLogs(
        namespace: String, pod: String, container: String?
    )
        -> AsyncThrowingStream<String, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let streaming = http as? StreamingHTTPClient else {
                        throw KubernetesError.api(status: 0, body: "streaming not supported")
                    }
                    var query = "follow=true&tailLines=200&timestamps=true"
                    if let container { query += "&container=\(container)" }
                    let token = try await tokenProvider.token()
                    guard
                        let url = URL(
                            string: baseURL.absoluteString
                                + "/api/v1/namespaces/\(namespace)/pods/\(pod)/log?\(query)")
                    else {
                        throw KubernetesError.api(status: 0, body: "bad log URL")
                    }
                    let request = HTTPRequest(
                        method: .get, url: url, headers: ["Authorization": "Bearer \(token)"])
                    for try await line in streaming.streamLines(request) {
                        if Task.isCancelled { break }
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request

    private func get(_ path: String) async throws -> Data {
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
        return response.body
    }

    private func list<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        try decoder.decode(T.self, from: try await get(path))
    }

    /// Builds a `DynamicResource` from a raw resource object, deriving a
    /// best-effort status from common shapes (conditions, `status.health`,
    /// `status.phase`).
    static func dynamicResource(from item: [String: Any]) -> DynamicResource {
        let metadata = item["metadata"] as? [String: Any] ?? [:]
        let name = metadata["name"] as? String ?? "?"
        let namespace = metadata["namespace"] as? String
        var created: Date?
        if let ts = metadata["creationTimestamp"] as? String {
            created = try? Date(ts, strategy: .iso8601)
        }
        let (statusText, health) = deriveStatus(item["status"] as? [String: Any])
        return DynamicResource(
            name: name, namespace: namespace, creationTimestamp: created,
            statusText: statusText, health: health)
    }

    private static func deriveStatus(_ status: [String: Any]?) -> (String?, HealthStatus) {
        guard let status else { return (nil, .unknown) }
        if let conditions = status["conditions"] as? [[String: Any]] {
            let ready =
                conditions.first { ($0["type"] as? String) == "Ready" }
                ?? conditions.first { ($0["type"] as? String) == "Available" }
                ?? conditions.last
            if let ready {
                let type = ready["type"] as? String ?? "?"
                let value = ready["status"] as? String ?? "?"
                if value == "True" { return (type, .ok) }
                return (ready["reason"] as? String ?? "Not \(type)", .error)
            }
        }
        // Argo CD Application: status.health.status.
        if let healthText = (status["health"] as? [String: Any])?["status"] as? String {
            return (healthText, HealthStatus(kubernetesStatus: healthText))
        }
        if let phase = status["phase"] as? String {
            return (phase, HealthStatus(kubernetesStatus: phase))
        }
        return (nil, .unknown)
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

/// Decodes just `metadata.name` (for namespace listing).
private struct NameOnly: Decodable, Sendable {
    let metadata: Meta
    struct Meta: Decodable, Sendable { let name: String }
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
