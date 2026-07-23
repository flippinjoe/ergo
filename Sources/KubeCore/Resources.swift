import Foundation

/// A workload Pod. Modeled shallowly — enough to drive the explorer table and
/// seed the relationship graph via `metadata.ownerReferences`.
public struct Pod: Hashable, Sendable, Codable, Identifiable {
    public var metadata: ObjectMeta
    public var spec: Spec?
    public var status: Status?

    public struct Spec: Hashable, Sendable, Codable {
        public var nodeName: String?
        public init(nodeName: String? = nil) { self.nodeName = nodeName }
    }

    public struct Status: Hashable, Sendable, Codable {
        public var phase: String?
        public var containerStatuses: [ContainerStatus]?
        public init(phase: String? = nil, containerStatuses: [ContainerStatus]? = nil) {
            self.phase = phase
            self.containerStatuses = containerStatuses
        }
    }

    public var id: String { metadata.uid ?? "\(metadata.namespace ?? "")/\(metadata.name)" }

    /// Total container restarts — the "Restarts" column.
    public var restartCount: Int {
        status?.containerStatuses?.reduce(0) { $0 + $1.restartCount } ?? 0
    }

    /// What the UI shows in the "Status" column. A container waiting reason
    /// (e.g. `CrashLoopBackOff`) is more useful than the coarse phase, so it
    /// wins when present.
    public var displayStatus: String {
        if let reason = status?.containerStatuses?.compactMap(\.state?.waiting?.reason).first {
            return reason
        }
        return status?.phase ?? "Unknown"
    }

    /// Health bucket derived from `displayStatus` — drives the status dot color.
    public var health: HealthStatus { HealthStatus(kubernetesStatus: displayStatus) }

    public init(metadata: ObjectMeta, spec: Spec? = nil, status: Status? = nil) {
        self.metadata = metadata
        self.spec = spec
        self.status = status
    }
}

/// A single container's runtime status. Only the fields the explorer needs.
public struct ContainerStatus: Hashable, Sendable, Codable {
    public var name: String?
    public var restartCount: Int
    public var state: ContainerState?

    public init(name: String? = nil, restartCount: Int = 0, state: ContainerState? = nil) {
        self.name = name
        self.restartCount = restartCount
        self.state = state
    }
}

/// A container's current state. Modeled just far enough to surface a waiting
/// reason like `CrashLoopBackOff`.
public struct ContainerState: Hashable, Sendable, Codable {
    public var waiting: Waiting?

    public struct Waiting: Hashable, Sendable, Codable {
        public var reason: String?
        public init(reason: String? = nil) { self.reason = reason }
    }

    public init(waiting: Waiting? = nil) { self.waiting = waiting }
}

/// A Deployment. Owns ReplicaSets which in turn own Pods — the canonical
/// three-hop chain the relationships pillar visualizes.
public struct Deployment: Hashable, Sendable, Codable, Identifiable {
    public var metadata: ObjectMeta
    public var spec: Spec?
    public var status: Status?

    public struct Spec: Hashable, Sendable, Codable {
        public var replicas: Int?
        public init(replicas: Int? = nil) { self.replicas = replicas }
    }

    public struct Status: Hashable, Sendable, Codable {
        public var readyReplicas: Int?
        public init(readyReplicas: Int? = nil) { self.readyReplicas = readyReplicas }
    }

    public var id: String { metadata.uid ?? "\(metadata.namespace ?? "")/\(metadata.name)" }

    /// "ready/desired", e.g. "3/3".
    public var readyText: String { "\(status?.readyReplicas ?? 0)/\(spec?.replicas ?? 0)" }
    /// Healthy when all desired replicas are ready.
    public var health: HealthStatus {
        (status?.readyReplicas ?? 0) >= (spec?.replicas ?? 0) && (spec?.replicas ?? 0) > 0 ? .ok : .warning
    }

    public init(metadata: ObjectMeta, spec: Spec? = nil, status: Status? = nil) {
        self.metadata = metadata
        self.spec = spec
        self.status = status
    }
}

/// A StatefulSet — modeled like Deployment (workload with a desired/ready
/// replica count).
public struct StatefulSet: Hashable, Sendable, Codable, Identifiable {
    public var metadata: ObjectMeta
    public var spec: Spec?
    public var status: Status?

    public struct Spec: Hashable, Sendable, Codable {
        public var replicas: Int?
        public init(replicas: Int? = nil) { self.replicas = replicas }
    }

    public struct Status: Hashable, Sendable, Codable {
        public var readyReplicas: Int?
        public init(readyReplicas: Int? = nil) { self.readyReplicas = readyReplicas }
    }

    public var id: String { metadata.uid ?? "\(metadata.namespace ?? "")/\(metadata.name)" }
    public var readyText: String { "\(status?.readyReplicas ?? 0)/\(spec?.replicas ?? 0)" }
    public var health: HealthStatus {
        (status?.readyReplicas ?? 0) >= (spec?.replicas ?? 0) && (spec?.replicas ?? 0) > 0 ? .ok : .warning
    }

    public init(metadata: ObjectMeta, spec: Spec? = nil, status: Status? = nil) {
        self.metadata = metadata
        self.spec = spec
        self.status = status
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
