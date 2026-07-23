import Foundation

/// Addresses any resource type on the API server: `/apis/{group}/{version}/{resource}`
/// (or `/api/v1/{resource}` for the core group). This is the pillar-2 seam —
/// listing arbitrary CRDs without a compiled-in type.
public struct GroupVersionResource: Hashable, Sendable {
    public var group: String
    public var version: String
    /// The plural, lowercase resource name (e.g. `certificates`).
    public var resource: String
    public var namespaced: Bool

    public init(group: String, version: String, resource: String, namespaced: Bool) {
        self.group = group
        self.version = version
        self.resource = resource
        self.namespaced = namespaced
    }

    /// The list path, optionally scoped to a namespace.
    public func listPath(namespace: String?) -> String {
        let root = group.isEmpty ? "/api/\(version)" : "/apis/\(group)/\(version)"
        if namespaced, let namespace {
            return "\(root)/namespaces/\(namespace)/\(resource)"
        }
        return "\(root)/\(resource)"
    }
}

/// A type-erased resource instance, reduced to what a generic list view needs.
/// A best-effort `statusText`/`health` is derived from common status shapes
/// (conditions, `status.health`, `status.phase`) so unknown CRDs still show a
/// meaningful state.
public struct DynamicResource: Hashable, Sendable, Codable, Identifiable {
    public var name: String
    public var namespace: String?
    public var creationTimestamp: Date?
    public var statusText: String?
    public var health: HealthStatus

    public var id: String { "\(namespace ?? "")/\(name)" }

    public init(
        name: String,
        namespace: String? = nil,
        creationTimestamp: Date? = nil,
        statusText: String? = nil,
        health: HealthStatus = .unknown
    ) {
        self.name = name
        self.namespace = namespace
        self.creationTimestamp = creationTimestamp
        self.statusText = statusText
        self.health = health
    }
}
