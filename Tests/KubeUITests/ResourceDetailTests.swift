import Foundation
import Testing

@testable import KubeUI

@Suite("Resource detail sections")
struct ResourceDetailTests {
    private func sections(_ kind: String, _ json: String) -> [DetailSection] {
        ResourceDetail.sections(kind: kind, group: "", manifest: Data(json.utf8))
    }

    private func section(_ sections: [DetailSection], _ id: String) -> DetailSection? {
        sections.first { $0.id == id }
    }

    @Test("Pod surfaces status fields and its containers")
    func pod() {
        let json = """
            {"kind":"Pod",
             "spec":{"nodeName":"node-1","serviceAccountName":"default",
                     "containers":[{"name":"app","image":"nginx:1.25"},
                                   {"name":"sidecar","image":"envoy:1.29"}]},
             "status":{"phase":"Running","podIP":"10.0.0.5",
                       "containerStatuses":[{"restartCount":2}]}}
            """
        let result = sections("Pod", json)
        let pod = section(result, "pod")
        #expect(pod?.rows.first { $0.label == "Phase" }?.value == "Running")
        #expect(pod?.rows.first { $0.label == "Pod IP" }?.value == "10.0.0.5")
        #expect(pod?.rows.first { $0.label == "Node" }?.value == "node-1")
        #expect(pod?.rows.first { $0.label == "Restarts" }?.value == "2")
        #expect(section(result, "containers")?.items.count == 2)
    }

    @Test("Deployment surfaces replica counts")
    func deployment() {
        let json = """
            {"kind":"Deployment","spec":{"replicas":3},
             "status":{"readyReplicas":3,"updatedReplicas":3,"availableReplicas":2}}
            """
        let replicas = section(sections("Deployment", json), "replicas")
        #expect(replicas?.rows.first { $0.label == "Desired" }?.value == "3")
        #expect(replicas?.rows.first { $0.label == "Available" }?.value == "2")
    }

    @Test("Service surfaces type and formatted ports")
    func service() {
        let json = """
            {"kind":"Service","spec":{"type":"ClusterIP","clusterIP":"10.1.2.3",
             "ports":[{"port":80,"targetPort":8080,"protocol":"TCP","name":"http"}]}}
            """
        let result = sections("Service", json)
        #expect(section(result, "service")?.rows.first { $0.label == "Type" }?.value == "ClusterIP")
        #expect(section(result, "ports")?.items.first == "http: 80 → 8080/TCP")
    }

    @Test("ConfigMap lists its data keys")
    func configMap() {
        let result = sections("ConfigMap", #"{"kind":"ConfigMap","data":{"b":"2","a":"1"}}"#)
        let data = section(result, "data")
        #expect(data?.title == "Data (2)")
        #expect(data?.items == ["a", "b"])  // sorted
    }

    @Test("Unknown kinds fall back to generic spec/status/conditions")
    func genericFallback() {
        let json = """
            {"kind":"Certificate",
             "spec":{"dnsNames":["a.com"],"secretName":"tls","renewBefore":"360h","isCA":false},
             "status":{"conditions":[{"type":"Ready","status":"True","reason":"Issued"}]}}
            """
        let result = sections("Certificate", json)
        let spec = section(result, "spec")
        #expect(spec?.rows.contains { $0.label == "Secret Name" && $0.value == "tls" } == true)
        #expect(spec?.rows.contains { $0.label == "Renew Before" } == true)
        #expect(spec?.rows.contains { $0.label == "Is CA" && $0.value == "false" } == true)
        // Array fields aren't scalars, so they're skipped.
        #expect(spec?.rows.contains { $0.label == "Dns Names" } == false)
        #expect(section(result, "conditions")?.items == ["Ready: True (Issued)"])
    }

    @Test("Kinds with no scalar spec/status contribute nothing")
    func empty() {
        #expect(sections("Widget", #"{"kind":"Widget","spec":{}}"#).isEmpty)
    }
}
