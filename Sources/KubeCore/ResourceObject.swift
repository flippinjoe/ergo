import Foundation

/// A single resource as raw JSON from the API server, plus its stable identity.
/// The watch stream yields snapshots of these; callers decode the `data` into
/// whatever typed or dynamic form they need.
public struct ResourceObject: Sendable, Identifiable, Hashable {
    public let id: String
    public let data: Data

    public init(id: String, data: Data) {
        self.id = id
        self.data = data
    }
}

/// A watch event type from the Kubernetes watch stream.
public enum WatchEventType: String, Sendable {
    case added = "ADDED"
    case modified = "MODIFIED"
    case deleted = "DELETED"
    case bookmark = "BOOKMARK"
    case error = "ERROR"
}
