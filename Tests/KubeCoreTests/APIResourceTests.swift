import Testing

@testable import KubeCore

@Suite("APIResource display name")
struct APIResourceTests {
    private func name(kind: String, resource: String) -> String {
        APIResource(group: "g", version: "v1", resource: resource, kind: kind, namespaced: true).displayName
    }

    @Test("Pluralizes and humanizes the kind")
    func displayNames() {
        #expect(name(kind: "Pod", resource: "pods") == "Pods")
        #expect(name(kind: "Service", resource: "services") == "Services")
        #expect(name(kind: "Ingress", resource: "ingresses") == "Ingresses")
        #expect(name(kind: "ConfigMap", resource: "configmaps") == "Config Maps")
        #expect(name(kind: "NetworkPolicy", resource: "networkpolicies") == "Network Policies")
        #expect(
            name(kind: "PersistentVolumeClaim", resource: "persistentvolumeclaims")
                == "Persistent Volume Claims")
        #expect(name(kind: "HTTPRoute", resource: "httproutes") == "HTTP Routes")
        // Already-plural kinds aren't double-pluralized.
        #expect(name(kind: "Endpoints", resource: "endpoints") == "Endpoints")
    }

    @Test("id and gvr reflect group/version/resource")
    func identity() {
        let core = APIResource(group: "", version: "v1", resource: "pods", kind: "Pod", namespaced: true)
        #expect(core.id == "v1/pods")
        #expect(core.groupTitle == "Core")

        let apps = APIResource(
            group: "apps", version: "v1", resource: "deployments", kind: "Deployment", namespaced: true)
        #expect(apps.id == "apps/v1/deployments")
        #expect(apps.gvr.listPath(namespace: "x") == "/apis/apps/v1/namespaces/x/deployments")
    }
}
