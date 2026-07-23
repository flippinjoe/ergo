import KubeCore
import SwiftUI

/// A sidebar section (an API group, or a curated category).
struct SidebarSection: Identifiable {
    let id: String
    let title: String
    let resources: [APIResource]
}

/// How the sidebar organizes discovered resources.
enum SidebarGrouping: String, CaseIterable, Sendable {
    /// Strictly by API group, faithful to the cluster (Core, apps, …).
    case byGroup
    /// Task-oriented categories (Workloads, Config, Network, …) + a Custom
    /// Resources catch-all.
    case curated

    var title: String { self == .byGroup ? "API Groups" : "Curated" }
}

/// Turns discovered API resources into an ordered, grouped sidebar and maps
/// kinds to icons.
enum ResourceCatalog {
    static func sections(from resources: [APIResource], grouping: SidebarGrouping) -> [SidebarSection] {
        switch grouping {
        case .byGroup: byGroupSections(resources)
        case .curated: curatedSections(resources)
        }
    }

    /// The section id a resource belongs to, under the given grouping (used to
    /// auto-expand the selected resource's section).
    static func sectionID(for resource: APIResource, grouping: SidebarGrouping) -> String {
        switch grouping {
        case .byGroup: resource.group.isEmpty ? "core" : resource.group
        case .curated: curatedCategory(for: resource)
        }
    }

    // MARK: By API group

    private static let groupOrder = [
        "", "apps", "batch", "networking.k8s.io", "storage.k8s.io",
        "rbac.authorization.k8s.io", "autoscaling", "policy", "scheduling.k8s.io",
        "coordination.k8s.io", "node.k8s.io", "discovery.k8s.io",
        "admissionregistration.k8s.io", "apiextensions.k8s.io", "apiregistration.k8s.io",
        "events.k8s.io", "certificates.k8s.io", "flowcontrol.apiserver.k8s.io",
    ]

    private static func byGroupSections(_ resources: [APIResource]) -> [SidebarSection] {
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

    // MARK: Curated categories

    static let curatedOrder = [
        "Workloads", "Config", "Network", "Storage", "Access Control", "Cluster", "Custom Resources",
    ]

    /// Built-in Kubernetes groups whose uncategorized resources land under
    /// "Cluster" rather than "Custom Resources".
    private static let builtinGroups: Set<String> = [
        "", "apps", "batch", "autoscaling", "policy", "networking.k8s.io", "storage.k8s.io",
        "rbac.authorization.k8s.io", "scheduling.k8s.io", "node.k8s.io", "coordination.k8s.io",
        "discovery.k8s.io", "admissionregistration.k8s.io", "apiextensions.k8s.io",
        "apiregistration.k8s.io", "events.k8s.io", "certificates.k8s.io",
        "flowcontrol.apiserver.k8s.io", "authentication.k8s.io", "authorization.k8s.io",
        "metrics.k8s.io",
    ]

    /// group/resource → curated category (group empty for core).
    private static let curatedMap: [String: String] = {
        var map: [String: String] = [:]
        func add(_ category: String, _ keys: [String]) { for key in keys { map[key] = category } }
        add(
            "Workloads",
            [
                "/pods", "/replicationcontrollers", "apps/deployments", "apps/statefulsets",
                "apps/daemonsets", "apps/replicasets", "apps/controllerrevisions", "batch/jobs",
                "batch/cronjobs", "autoscaling/horizontalpodautoscalers",
            ])
        add(
            "Config",
            [
                "/configmaps", "/secrets", "/resourcequotas", "/limitranges", "/podtemplates",
                "scheduling.k8s.io/priorityclasses", "node.k8s.io/runtimeclasses",
                "policy/poddisruptionbudgets", "coordination.k8s.io/leases",
            ])
        add(
            "Network",
            [
                "/services", "/endpoints", "networking.k8s.io/ingresses",
                "networking.k8s.io/ingressclasses", "networking.k8s.io/networkpolicies",
                "discovery.k8s.io/endpointslices",
            ])
        add(
            "Storage",
            [
                "/persistentvolumeclaims", "/persistentvolumes", "storage.k8s.io/storageclasses",
                "storage.k8s.io/volumeattachments", "storage.k8s.io/csidrivers",
                "storage.k8s.io/csinodes", "storage.k8s.io/csistoragecapacities",
            ])
        add(
            "Access Control",
            [
                "/serviceaccounts", "rbac.authorization.k8s.io/roles",
                "rbac.authorization.k8s.io/rolebindings", "rbac.authorization.k8s.io/clusterroles",
                "rbac.authorization.k8s.io/clusterrolebindings",
                "certificates.k8s.io/certificatesigningrequests",
            ])
        add(
            "Cluster",
            [
                "/nodes", "/namespaces", "/events", "/componentstatuses",
                "events.k8s.io/events", "apiextensions.k8s.io/customresourcedefinitions",
                "apiregistration.k8s.io/apiservices",
            ])
        return map
    }()

    static func curatedCategory(for resource: APIResource) -> String {
        let key = "\(resource.group)/\(resource.resource)"
        if let category = curatedMap[key] { return category }
        // Uncategorized built-ins → Cluster; everything else (CRDs) → Custom Resources.
        return builtinGroups.contains(resource.group) ? "Cluster" : "Custom Resources"
    }

    private static func curatedSections(_ resources: [APIResource]) -> [SidebarSection] {
        let byCategory = Dictionary(grouping: resources, by: curatedCategory(for:))
        return curatedOrder.compactMap { category in
            guard let items = byCategory[category], !items.isEmpty else { return nil }
            return SidebarSection(
                id: category, title: category,
                resources: items.sorted { $0.displayName < $1.displayName })
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
