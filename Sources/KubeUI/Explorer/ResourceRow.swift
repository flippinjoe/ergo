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

    init(
        id: String, name: String, namespace: String?, statusText: String?,
        health: HealthStatus, detail: String?, age: String?
    ) {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.statusText = statusText
        self.health = health
        self.detail = detail
        self.age = age
    }

    init(deployment: Deployment, now: Date) {
        self.init(
            id: deployment.id, name: deployment.metadata.name, namespace: deployment.metadata.namespace,
            statusText: nil, health: deployment.health, detail: deployment.readyText,
            age: deployment.metadata.age(now: now))
    }

    init(statefulSet: StatefulSet, now: Date) {
        self.init(
            id: statefulSet.id, name: statefulSet.metadata.name, namespace: statefulSet.metadata.namespace,
            statusText: nil, health: statefulSet.health, detail: statefulSet.readyText,
            age: statefulSet.metadata.age(now: now))
    }

    init(dynamic: DynamicResource, now: Date) {
        self.init(
            id: dynamic.id, name: dynamic.name, namespace: dynamic.namespace,
            statusText: dynamic.statusText, health: dynamic.health, detail: nil,
            age: dynamic.creationTimestamp.map { RelativeAge.string(from: $0, now: now) })
    }
}
