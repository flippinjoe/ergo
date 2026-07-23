import Foundation
import KubeCore

/// The single boundary between Ergo and any Kubernetes API server.
///
/// Everything above this protocol (view models, UI) depends only on the
/// abstraction, so tests and previews inject `FakeClusterClient` and never
/// touch a real cluster. A live implementation (URLSession against the API
/// server) will conform to the same protocol later.
///
/// All methods are read-only in the skeleton — the scaffold deliberately
/// ships no mutating calls, so nothing here can ever alter a real cluster.
public protocol ClusterClient: Sendable {
    func listPods(namespace: String?) async throws -> [Pod]
    func listDeployments(namespace: String?) async throws -> [Deployment]
    func listStatefulSets(namespace: String?) async throws -> [StatefulSet]
    func listEvents(namespace: String?) async throws -> [EventRecord]
    func listCRDs() async throws -> [CRDSummary]
    /// The namespaces on the cluster, for the namespace filter.
    func listNamespaces() async throws -> [String]
    /// Generic list of any resource type (the pillar-2 seam) — used for CRDs
    /// with no compiled-in type.
    func listDynamic(_ gvr: GroupVersionResource, namespace: String?) async throws -> [DynamicResource]
    /// Streams a pod's logs (`follow=true`) as they're produced. Read-only.
    /// Terminating the stream closes the connection.
    func streamLogs(
        namespace: String, pod: String, container: String?
    )
        -> AsyncThrowingStream<String, Error>
    /// Watches a resource type: yields the full current set of objects (raw
    /// JSON) on every change, via the Kubernetes list+watch protocol. Read-only.
    func watch(
        _ gvr: GroupVersionResource, namespace: String?
    )
        -> AsyncThrowingStream<[ResourceObject], Error>
    /// Discovers every listable resource type the cluster serves (preferred
    /// version per group) — the source of truth for the sidebar.
    func discoverAPIResources() async throws -> [APIResource]
    /// Kind → human description from the cluster's OpenAPI schema, for a single
    /// group/version. Used to explain resource types in the UI.
    func resourceDescriptions(group: String, version: String) async throws -> [String: String]
}

/// Pillar 2 (schema & AI): fetches the OpenAPI schema for a resource type so
/// the UI can render a dynamic form. A seam only — no implementation yet.
public protocol SchemaProviding: Sendable {
    func openAPISchema(for gvk: GroupVersionKind) async throws -> Data
}

/// Pillar 3 (auth & agents): exposes selected read-only cluster operations to
/// a local MCP server so agents can drive Ergo. A seam only — no
/// implementation yet.
public protocol MCPExposing: Sendable {
    var exposedToolNames: [String] { get }
}

/// Errors surfaced across the client boundary.
public enum ClusterClientError: Error, Sendable, Equatable {
    case fixtureNotFound(String)
    case notImplemented
}
