import Foundation
import KubeCore

/// A `ClusterClient` backed by static JSON fixtures bundled with this target.
///
/// This is the hermetic testing/preview backend: it never opens a socket,
/// reads no kubeconfig, and cannot mutate anything. Fixtures live in
/// `Sources/KubeClient/Fixtures` and are loaded from `Bundle.module`.
public struct FakeClusterClient: ClusterClient {
    private let decoder: JSONDecoder

    public init() {
        let decoder = JSONDecoder()
        // Kubernetes timestamps are RFC 3339 / ISO 8601 (e.g. 2026-07-22T18:04:11Z).
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func listPods(namespace: String?) async throws -> [Pod] {
        try filtered(load("pods", as: ItemList<Pod>.self).items, namespace: namespace, \.metadata.namespace)
    }

    public func listDeployments(namespace: String?) async throws -> [Deployment] {
        try filtered(
            load("deployments", as: ItemList<Deployment>.self).items, namespace: namespace,
            \.metadata.namespace)
    }

    public func listEvents(namespace: String?) async throws -> [EventRecord] {
        try filtered(
            load("events", as: ItemList<EventRecord>.self).items, namespace: namespace, \.metadata.namespace)
    }

    public func listStatefulSets(namespace: String?) async throws -> [StatefulSet] {
        try filtered(
            load("statefulsets", as: ItemList<StatefulSet>.self).items, namespace: namespace,
            \.metadata.namespace)
    }

    public func listCRDs() async throws -> [CRDSummary] {
        try load("crds", as: ItemList<CRDSummary>.self).items
    }

    public func listNamespaces() async throws -> [String] {
        // Derive from the pod fixtures so the filter has real values.
        let pods = try load("pods", as: ItemList<Pod>.self).items
        return Set(pods.compactMap(\.metadata.namespace)).sorted()
    }

    public func listDynamic(
        _ gvr: GroupVersionResource, namespace: String?
    ) async throws
        -> [DynamicResource]
    {
        // The demo cluster ships no custom-resource instances.
        []
    }

    public func streamLogs(
        namespace: String, pod: String, container: String?
    )
        -> AsyncThrowingStream<String, Error>
    {
        // Emit a few canned lines so the demo dock is populated, then finish.
        AsyncThrowingStream { continuation in
            let sample = [
                "2026-07-23T09:41:13.201Z INFO  starting \(pod)",
                "2026-07-23T09:41:13.334Z WARN  git credential template store not found, falling back",
                "2026-07-23T09:41:13.335Z ERROR failed to init repo cache: connection refused",
            ]
            for line in sample { continuation.yield(line) }
            continuation.finish()
        }
    }

    public func watch(
        _ gvr: GroupVersionResource, namespace: String?
    )
        -> AsyncThrowingStream<[ResourceObject], Error>
    {
        // The demo cluster is static: yield one snapshot from the fixtures.
        let fixture: String?
        switch gvr.resource {
        case "pods": fixture = "pods"
        case "deployments": fixture = "deployments"
        case "statefulsets": fixture = "statefulsets"
        default: fixture = nil  // custom resources have no demo fixtures
        }
        let objects = (fixture.flatMap { try? rawObjects(fixture: $0, namespace: namespace) }) ?? []
        return AsyncThrowingStream { continuation in
            continuation.yield(objects)
            continuation.finish()
        }
    }

    /// Reads a fixture's `items` as raw `ResourceObject`s (no typed decode).
    private func rawObjects(fixture: String, namespace: String?) throws -> [ResourceObject] {
        guard
            let url = Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: fixture, withExtension: "json")
        else { throw ClusterClientError.fixtureNotFound("\(fixture).json") }
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let items = root?["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            let meta = item["metadata"] as? [String: Any] ?? [:]
            if let namespace, (meta["namespace"] as? String) != namespace { return nil }
            let id =
                (meta["uid"] as? String)
                ?? "\(meta["namespace"] as? String ?? "")/\(meta["name"] as? String ?? "")"
            guard let data = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return ResourceObject(id: id, data: data)
        }
    }

    public func discoverAPIResources() async throws -> [APIResource] {
        func r(
            _ group: String, _ version: String, _ resource: String, _ kind: String, _ namespaced: Bool
        )
            -> APIResource
        {
            APIResource(
                group: group, version: version, resource: resource, kind: kind, namespaced: namespaced)
        }
        return [
            r("", "v1", "pods", "Pod", true),
            r("", "v1", "services", "Service", true),
            r("", "v1", "configmaps", "ConfigMap", true),
            r("", "v1", "secrets", "Secret", true),
            r("", "v1", "persistentvolumeclaims", "PersistentVolumeClaim", true),
            r("", "v1", "persistentvolumes", "PersistentVolume", false),
            r("", "v1", "namespaces", "Namespace", false),
            r("", "v1", "nodes", "Node", false),
            r("", "v1", "serviceaccounts", "ServiceAccount", true),
            r("apps", "v1", "deployments", "Deployment", true),
            r("apps", "v1", "statefulsets", "StatefulSet", true),
            r("apps", "v1", "daemonsets", "DaemonSet", true),
            r("batch", "v1", "jobs", "Job", true),
            r("batch", "v1", "cronjobs", "CronJob", true),
            r("networking.k8s.io", "v1", "ingresses", "Ingress", true),
            r("networking.k8s.io", "v1", "networkpolicies", "NetworkPolicy", true),
            r("storage.k8s.io", "v1", "storageclasses", "StorageClass", false),
            r("rbac.authorization.k8s.io", "v1", "roles", "Role", true),
            r("rbac.authorization.k8s.io", "v1", "clusterroles", "ClusterRole", false),
            r("cert-manager.io", "v1", "certificates", "Certificate", true),
            r("argoproj.io", "v1alpha1", "applications", "Application", true),
            r("keda.sh", "v1alpha1", "scaledobjects", "ScaledObject", true),
        ]
    }

    // MARK: - Fixture loading

    /// A Kubernetes list response: `{ "items": [...] }`.
    private struct ItemList<Element: Decodable & Sendable>: Decodable, Sendable {
        let items: [Element]
    }

    private func load<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: name, withExtension: "json")
        else {
            throw ClusterClientError.fixtureNotFound("\(name).json")
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func filtered<T>(_ items: [T], namespace: String?, _ keyPath: KeyPath<T, String?>) -> [T] {
        guard let namespace else { return items }
        return items.filter { $0[keyPath: keyPath] == namespace }
    }
}
