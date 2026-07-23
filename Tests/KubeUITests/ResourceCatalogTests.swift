import KubeCore
import Testing

@testable import KubeUI

@Suite("Resource catalog")
struct ResourceCatalogTests {
    private func r(_ group: String, _ resource: String, _ kind: String) -> APIResource {
        APIResource(group: group, version: "v1", resource: resource, kind: kind, namespaced: true)
    }

    @Test("Groups by API group with core first, then known, then alphabetical")
    func ordering() {
        let resources = [
            r("cert-manager.io", "certificates", "Certificate"),
            r("apps", "deployments", "Deployment"),
            r("", "pods", "Pod"),
            r("networking.k8s.io", "ingresses", "Ingress"),
        ]
        let sections = ResourceCatalog.sections(from: resources, grouping: .byGroup)
        #expect(sections.map(\.title) == ["Core", "apps", "networking.k8s.io", "cert-manager.io"])
        #expect(sections.first?.resources.first?.kind == "Pod")
    }

    @Test("Resources within a group are sorted by display name")
    func sortedWithinGroup() {
        let resources = [
            r("apps", "statefulsets", "StatefulSet"),
            r("apps", "daemonsets", "DaemonSet"),
            r("apps", "deployments", "Deployment"),
        ]
        let apps = ResourceCatalog.sections(from: resources, grouping: .byGroup).first { $0.title == "apps" }
        #expect(apps?.resources.map(\.displayName) == ["Daemon Sets", "Deployments", "Stateful Sets"])
    }

    @Test("Pods and workload-detail detection")
    func classification() {
        #expect(ResourceCatalog.isPods(r("", "pods", "Pod")))
        #expect(!ResourceCatalog.isPods(r("apps", "deployments", "Deployment")))
        #expect(ResourceCatalog.hasReadyColumn(r("apps", "deployments", "Deployment")))
        #expect(!ResourceCatalog.hasReadyColumn(r("", "services", "Service")))
    }

    @Test("Curated grouping sorts standard kinds into task categories")
    func curatedCategories() {
        #expect(ResourceCatalog.curatedCategory(for: r("", "pods", "Pod")) == "Workloads")
        #expect(ResourceCatalog.curatedCategory(for: r("apps", "deployments", "Deployment")) == "Workloads")
        #expect(ResourceCatalog.curatedCategory(for: r("", "configmaps", "ConfigMap")) == "Config")
        #expect(ResourceCatalog.curatedCategory(for: r("", "secrets", "Secret")) == "Config")
        #expect(ResourceCatalog.curatedCategory(for: r("", "services", "Service")) == "Network")
        #expect(
            ResourceCatalog.curatedCategory(for: r("networking.k8s.io", "ingresses", "Ingress")) == "Network")
        #expect(
            ResourceCatalog.curatedCategory(for: r("", "persistentvolumeclaims", "PersistentVolumeClaim"))
                == "Storage")
        #expect(
            ResourceCatalog.curatedCategory(for: r("rbac.authorization.k8s.io", "roles", "Role"))
                == "Access Control")
        #expect(ResourceCatalog.curatedCategory(for: r("", "nodes", "Node")) == "Cluster")
        // A niche built-in group falls to Cluster; a CRD falls to Custom Resources.
        #expect(
            ResourceCatalog.curatedCategory(
                for: r("flowcontrol.apiserver.k8s.io", "flowschemas", "FlowSchema")) == "Cluster")
        #expect(
            ResourceCatalog.curatedCategory(for: r("cert-manager.io", "certificates", "Certificate"))
                == "Custom Resources")
    }

    @Test("Curated collapses core + events.k8s.io Events into one row")
    func curatedDedupesEvents() {
        let resources = [
            r("", "events", "Event"),
            r("events.k8s.io", "events", "Event"),
            r("", "nodes", "Node"),
        ]
        let cluster = ResourceCatalog.sections(from: resources, grouping: .curated)
            .first { $0.title == "Cluster" }
        let events = cluster?.resources.filter { $0.kind == "Event" } ?? []
        #expect(events.count == 1)
        // Prefers the newer, non-core API group.
        #expect(events.first?.group == "events.k8s.io")
    }

    @Test("API Groups keeps both Events (faithful to the cluster)")
    func byGroupKeepsBothEvents() {
        let resources = [r("", "events", "Event"), r("events.k8s.io", "events", "Event")]
        let all = ResourceCatalog.sections(from: resources, grouping: .byGroup).flatMap(\.resources)
        #expect(all.filter { $0.kind == "Event" }.count == 2)
    }

    @Test("Curated sections appear in the fixed category order")
    func curatedOrder() {
        let resources = [
            r("cert-manager.io", "certificates", "Certificate"),
            r("", "nodes", "Node"),
            r("", "pods", "Pod"),
            r("", "services", "Service"),
        ]
        let titles = ResourceCatalog.sections(from: resources, grouping: .curated).map(\.title)
        #expect(titles == ["Workloads", "Network", "Cluster", "Custom Resources"])
    }
}
