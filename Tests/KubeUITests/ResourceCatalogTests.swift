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
        let sections = ResourceCatalog.sections(from: resources)
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
        let apps = ResourceCatalog.sections(from: resources).first { $0.title == "apps" }
        #expect(apps?.resources.map(\.displayName) == ["Daemon Sets", "Deployments", "Stateful Sets"])
    }

    @Test("Pods and workload-detail detection")
    func classification() {
        #expect(ResourceCatalog.isPods(r("", "pods", "Pod")))
        #expect(!ResourceCatalog.isPods(r("apps", "deployments", "Deployment")))
        #expect(ResourceCatalog.hasReadyColumn(r("apps", "deployments", "Deployment")))
        #expect(!ResourceCatalog.hasReadyColumn(r("", "services", "Service")))
    }
}
