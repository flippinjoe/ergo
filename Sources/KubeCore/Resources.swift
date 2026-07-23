import Foundation

/// A workload Pod. Modeled shallowly — enough to prove decoding and to seed
/// the relationship graph via `metadata.ownerReferences`.
public struct Pod: Hashable, Sendable, Codable, Identifiable {
    public var metadata: ObjectMeta
    public var status: Status?

    public struct Status: Hashable, Sendable, Codable {
        public var phase: String?
        public init(phase: String? = nil) { self.phase = phase }
    }

    public var id: String { metadata.uid ?? "\(metadata.namespace ?? "")/\(metadata.name)" }

    public init(metadata: ObjectMeta, status: Status? = nil) {
        self.metadata = metadata
        self.status = status
    }
}

/// A Deployment. Owns ReplicaSets which in turn own Pods — the canonical
/// three-hop chain the relationships pillar visualizes.
public struct Deployment: Hashable, Sendable, Codable, Identifiable {
    public var metadata: ObjectMeta
    public var spec: Spec?

    public struct Spec: Hashable, Sendable, Codable {
        public var replicas: Int?
        public init(replicas: Int? = nil) { self.replicas = replicas }
    }

    public var id: String { metadata.uid ?? "\(metadata.namespace ?? "")/\(metadata.name)" }

    public init(metadata: ObjectMeta, spec: Spec? = nil) {
        self.metadata = metadata
        self.spec = spec
    }
}

/// Pillar 1 (relationships & time): a cluster Event. Streaming these against
/// the ownership graph is how Ergo shows *what happened, when* to a workload.
public struct EventRecord: Hashable, Sendable, Codable, Identifiable {
    public var metadata: ObjectMeta
    public var involvedObject: ObjectReference
    public var reason: String?
    public var message: String?
    /// `Normal` or `Warning`.
    public var type: String?
    public var count: Int?
    public var lastTimestamp: Date?

    public var id: String { metadata.uid ?? metadata.name }

    public init(
        metadata: ObjectMeta,
        involvedObject: ObjectReference,
        reason: String? = nil,
        message: String? = nil,
        type: String? = nil,
        count: Int? = nil,
        lastTimestamp: Date? = nil
    ) {
        self.metadata = metadata
        self.involvedObject = involvedObject
        self.reason = reason
        self.message = message
        self.type = type
        self.count = count
        self.lastTimestamp = lastTimestamp
    }
}

/// Pillar 2 (schema & AI): a thin descriptor of a CustomResourceDefinition.
/// The full OpenAPI schema (the raw material for dynamic, AI-assisted forms)
/// is fetched on demand through `SchemaProviding` rather than modeled here.
public struct CRDSummary: Hashable, Sendable, Codable, Identifiable {
    public var name: String
    public var group: String
    public var kind: String
    public var versions: [String]
    public var scope: Scope

    public enum Scope: String, Sendable, Codable {
        case namespaced = "Namespaced"
        case cluster = "Cluster"
    }

    public var id: String { name }

    public init(name: String, group: String, kind: String, versions: [String], scope: Scope) {
        self.name = name
        self.group = group
        self.kind = kind
        self.versions = versions
        self.scope = scope
    }
}
