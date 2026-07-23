import KubeCore
import SwiftUI

/// A sidebar section = one Kubernetes API group.
struct SidebarSection: Identifiable {
    let id: String
    let title: String
    let resources: [APIResource]
}

/// Turns discovered API resources into an ordered, grouped sidebar and maps
/// kinds to icons. Grouping is strictly by API group (the user's choice), with
/// well-known groups ordered first and the rest alphabetical.
enum ResourceCatalog {
    private static let groupOrder = [
        "", "apps", "batch", "networking.k8s.io", "storage.k8s.io",
        "rbac.authorization.k8s.io", "autoscaling", "policy", "scheduling.k8s.io",
        "coordination.k8s.io", "node.k8s.io", "discovery.k8s.io",
        "admissionregistration.k8s.io", "apiextensions.k8s.io", "apiregistration.k8s.io",
        "events.k8s.io", "certificates.k8s.io", "flowcontrol.apiserver.k8s.io",
    ]

    static func sections(from resources: [APIResource]) -> [SidebarSection] {
        let byGroup = Dictionary(grouping: resources, by: \.group)
        let groups = byGroup.keys.sorted(by: order)
        return groups.map { group in
            SidebarSection(
                id: group.isEmpty ? "core" : group,
                title: group.isEmpty ? "Core" : group,
                resources: (byGroup[group] ?? []).sorted { $0.displayName < $1.displayName })
        }
    }

    private static func order(_ a: String, _ b: String) -> Bool {
        let ia = groupOrder.firstIndex(of: a)
        let ib = groupOrder.firstIndex(of: b)
        switch (ia, ib) {
        case (let x?, let y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a < b
        }
    }

    /// Whether a resource shows a "Ready" (ready/desired) detail column.
    static func hasReadyColumn(_ resource: APIResource) -> Bool {
        resource.group == "apps"
            && ["deployments", "statefulsets", "daemonsets", "replicasets"].contains(resource.resource)
    }

    static func isPods(_ resource: APIResource) -> Bool {
        resource.group.isEmpty && resource.resource == "pods"
    }

    /// SF Symbol for a resource kind (falls back by scope).
    static func icon(for resource: APIResource) -> String {
        icons[resource.kind.lowercased()] ?? (resource.namespaced ? "shippingbox" : "cube")
    }

    private static let icons: [String: String] = [
        "pod": "shippingbox",
        "deployment": "square.stack.3d.up",
        "statefulset": "cylinder.split.1x2",
        "daemonset": "square.grid.3x3",
        "replicaset": "square.stack",
        "job": "hammer",
        "cronjob": "calendar.badge.clock",
        "service": "network",
        "ingress": "arrow.left.arrow.right",
        "ingressclass": "arrow.left.arrow.right.square",
        "networkpolicy": "lock.shield",
        "endpoints": "point.3.connected.trianglepath.dotted",
        "endpointslice": "point.3.connected.trianglepath.dotted",
        "configmap": "doc.text",
        "secret": "key",
        "persistentvolumeclaim": "externaldrive",
        "persistentvolume": "externaldrive.fill",
        "storageclass": "cylinder",
        "namespace": "square.on.square",
        "node": "server.rack",
        "serviceaccount": "person.circle",
        "role": "lock",
        "clusterrole": "lock.circle",
        "rolebinding": "lock.rotation",
        "clusterrolebinding": "lock.rotation",
        "certificate": "checkmark.seal",
        "horizontalpodautoscaler": "gauge.with.dots.needle.67percent",
        "customresourcedefinition": "puzzlepiece.extension",
        "event": "clock.arrow.circlepath",
        "poddisruptionbudget": "shield",
    ]
}
