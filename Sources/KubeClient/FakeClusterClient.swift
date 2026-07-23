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

    public func listCRDs() async throws -> [CRDSummary] {
        try load("crds", as: ItemList<CRDSummary>.self).items
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
