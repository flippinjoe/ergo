import Foundation
import KubeCore

/// A generic display row for the resource table — one shape for deployments,
/// statefulsets, and any custom resource. (Pods keep their own richer table.)
struct ResourceRow: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let namespace: String?
    let statusText: String?
    let health: HealthStatus
    /// Kind-specific column value (e.g. "3/3" ready). `nil` when the kind has no
    /// detail column.
    let detail: String?
    let age: String?
    /// Underlying creation time — the column sorts on this, not the age string.
    let created: Date?

    // Non-optional keys for `Table` column sorting.
    var sortNamespace: String { namespace ?? "" }
    var sortStatus: String { statusText ?? Self.healthRank(health) }
    var sortDetail: String { detail ?? "" }
    var sortCreated: Date { created ?? .distantPast }

    init(
        id: String, name: String, namespace: String?, statusText: String?,
        health: HealthStatus, detail: String?, age: String?, created: Date?
    ) {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.statusText = statusText
        self.health = health
        self.detail = detail
        self.age = age
        self.created = created
    }

    init(deployment: Deployment, now: Date) {
        self.init(
            id: deployment.id, name: deployment.metadata.name, namespace: deployment.metadata.namespace,
            statusText: nil, health: deployment.health, detail: deployment.readyText,
            age: deployment.metadata.age(now: now), created: deployment.metadata.creationTimestamp)
    }

    init(statefulSet: StatefulSet, now: Date) {
        self.init(
            id: statefulSet.id, name: statefulSet.metadata.name, namespace: statefulSet.metadata.namespace,
            statusText: nil, health: statefulSet.health, detail: statefulSet.readyText,
            age: statefulSet.metadata.age(now: now), created: statefulSet.metadata.creationTimestamp)
    }

    init(dynamic: DynamicResource, now: Date) {
        self.init(
            id: dynamic.id, name: dynamic.name, namespace: dynamic.namespace,
            statusText: dynamic.statusText, health: dynamic.health, detail: nil,
            age: dynamic.creationTimestamp.map { RelativeAge.string(from: $0, now: now) },
            created: dynamic.creationTimestamp)
    }

    /// Orders health so a status sort groups by severity when there's no text.
    private static func healthRank(_ health: HealthStatus) -> String {
        switch health {
        case .error: "0"
        case .warning: "1"
        case .unknown: "2"
        case .info: "3"
        case .ok: "4"
        }
    }
}
