import Foundation

/// A pointer to another object in the cluster. Used by events and owner
/// references to name what they relate to without embedding it.
public struct ObjectReference: Hashable, Sendable, Codable {
    public var apiVersion: String?
    public var kind: String
    public var namespace: String?
    public var name: String
    public var uid: String?

    public init(
        apiVersion: String? = nil,
        kind: String,
        namespace: String? = nil,
        name: String,
        uid: String? = nil
    ) {
        self.apiVersion = apiVersion
        self.kind = kind
        self.namespace = namespace
        self.name = name
        self.uid = uid
    }
}

/// Pillar 1 (relationships & time): the link from a child object up to the
/// controller that owns it. Walking these builds the ownership graph the UI
/// renders — Deployment → ReplicaSet → Pod.
public struct OwnerReference: Hashable, Sendable, Codable {
    public var apiVersion: String
    public var kind: String
    public var name: String
    public var uid: String
    /// Whether this owner is the managing controller (only one per object).
    public var controller: Bool?

    public init(
        apiVersion: String,
        kind: String,
        name: String,
        uid: String,
        controller: Bool? = nil
    ) {
        self.apiVersion = apiVersion
        self.kind = kind
        self.name = name
        self.uid = uid
        self.controller = controller
    }
}

/// The metadata every Kubernetes object carries. Only the fields Ergo needs
/// today are modeled; the rest decode-and-ignore.
public struct ObjectMeta: Hashable, Sendable, Codable {
    public var name: String
    public var namespace: String?
    public var uid: String?
    public var creationTimestamp: Date?
    public var labels: [String: String]?
    public var annotations: [String: String]?
    public var ownerReferences: [OwnerReference]?

    public init(
        name: String,
        namespace: String? = nil,
        uid: String? = nil,
        creationTimestamp: Date? = nil,
        labels: [String: String]? = nil,
        annotations: [String: String]? = nil,
        ownerReferences: [OwnerReference]? = nil
    ) {
        self.name = name
        self.namespace = namespace
        self.uid = uid
        self.creationTimestamp = creationTimestamp
        self.labels = labels
        self.annotations = annotations
        self.ownerReferences = ownerReferences
    }
}
