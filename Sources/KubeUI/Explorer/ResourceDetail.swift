import Foundation

/// A resource-specific block shown at the top of the inspector, above the
/// generic metadata/manifest sections.
///
/// This is the **pluggable-custom-area** approach (chosen over a full per-kind
/// view override): every resource gets the same consistent inspector chrome
/// — identity, metadata, owner chain, events, manifest — and a kind can *add*
/// focused sections here. Keeping them data-driven (rows + text items) rather
/// than arbitrary SwiftUI keeps rendering uniform and the logic unit-testable.
/// A kind that needs a bespoke visual can still grow a dedicated view later;
/// most just need "show these fields," which this covers.
struct DetailSection: Identifiable {
    let id: String
    let title: String
    let rows: [DetailRow]
    /// Free-form lines rendered under the rows (e.g. one per container).
    let items: [String]

    init(id: String, title: String, rows: [DetailRow] = [], items: [String] = []) {
        self.id = id
        self.title = title
        self.rows = rows
        self.items = items
    }
}

struct DetailRow: Identifiable {
    var id: String { label }
    let label: String
    let value: String
}

/// Builds a kind's custom inspector sections from its raw manifest JSON.
/// Unknown kinds simply return `[]` — the generic inspector still renders.
enum ResourceDetail {
    static func sections(kind: String, group: String, manifest data: Data) -> [DetailSection] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        switch kind {
        case "Pod": return pod(object)
        case "Deployment", "StatefulSet", "ReplicaSet", "DaemonSet": return workload(kind, object)
        case "Service": return service(object)
        case "ConfigMap": return configMap(object)
        case "Secret": return secret(object)
        case "Node": return node(object)
        case "PersistentVolumeClaim": return pvc(object)
        case "Ingress": return ingress(object)
        default: return []
        }
    }

    // MARK: - Per-kind builders

    private static func pod(_ object: [String: Any]) -> [DetailSection] {
        let spec = object["spec"] as? [String: Any]
        let status = object["status"] as? [String: Any]
        var rows: [DetailRow] = []
        if let phase = status?["phase"] as? String { rows.append(DetailRow(label: "Phase", value: phase)) }
        if let ip = status?["podIP"] as? String { rows.append(DetailRow(label: "Pod IP", value: ip)) }
        if let node = spec?["nodeName"] as? String { rows.append(DetailRow(label: "Node", value: node)) }
        if let sa = spec?["serviceAccountName"] as? String {
            rows.append(DetailRow(label: "Service Account", value: sa))
        }

        let restarts = statuses(status).reduce(0) { $0 + (($1["restartCount"] as? Int) ?? 0) }
        var items: [String] = []
        if let containers = spec?["containers"] as? [[String: Any]] {
            items = containers.map { container in
                let name = container["name"] as? String ?? "container"
                let image = container["image"] as? String ?? ""
                return "\(name)  ·  \(image)"
            }
        }
        if restarts > 0 { rows.append(DetailRow(label: "Restarts", value: "\(restarts)")) }

        var sections: [DetailSection] = []
        if !rows.isEmpty { sections.append(DetailSection(id: "pod", title: "Pod", rows: rows)) }
        if !items.isEmpty {
            sections.append(DetailSection(id: "containers", title: "Containers", items: items))
        }
        return sections
    }

    private static func statuses(_ status: [String: Any]?) -> [[String: Any]] {
        (status?["containerStatuses"] as? [[String: Any]]) ?? []
    }

    private static func workload(_ kind: String, _ object: [String: Any]) -> [DetailSection] {
        let spec = object["spec"] as? [String: Any]
        let status = object["status"] as? [String: Any]
        var rows: [DetailRow] = []
        if let desired = spec?["replicas"] as? Int {
            rows.append(DetailRow(label: "Desired", value: "\(desired)"))
        }
        if let ready = status?["readyReplicas"] as? Int {
            rows.append(DetailRow(label: "Ready", value: "\(ready)"))
        }
        if let updated = status?["updatedReplicas"] as? Int {
            rows.append(DetailRow(label: "Updated", value: "\(updated)"))
        }
        if let available = status?["availableReplicas"] as? Int {
            rows.append(DetailRow(label: "Available", value: "\(available)"))
        }
        // DaemonSets report differently.
        if let scheduled = status?["currentNumberScheduled"] as? Int {
            rows.append(DetailRow(label: "Scheduled", value: "\(scheduled)"))
        }
        if let readyNodes = status?["numberReady"] as? Int {
            rows.append(DetailRow(label: "Ready", value: "\(readyNodes)"))
        }
        guard !rows.isEmpty else { return [] }
        return [DetailSection(id: "replicas", title: "Replicas", rows: rows)]
    }

    private static func service(_ object: [String: Any]) -> [DetailSection] {
        let spec = object["spec"] as? [String: Any]
        var rows: [DetailRow] = []
        if let type = spec?["type"] as? String { rows.append(DetailRow(label: "Type", value: type)) }
        if let clusterIP = spec?["clusterIP"] as? String {
            rows.append(DetailRow(label: "Cluster IP", value: clusterIP))
        }
        var items: [String] = []
        if let ports = spec?["ports"] as? [[String: Any]] {
            items = ports.map { port in
                let proto = port["protocol"] as? String ?? "TCP"
                let portValue = (port["port"] as? Int).map(String.init) ?? "?"
                let target = port["targetPort"].map { "\($0)" } ?? portValue
                let name = (port["name"] as? String).map { "\($0): " } ?? ""
                return "\(name)\(portValue) → \(target)/\(proto)"
            }
        }
        var sections: [DetailSection] = []
        if !rows.isEmpty { sections.append(DetailSection(id: "service", title: "Service", rows: rows)) }
        if !items.isEmpty { sections.append(DetailSection(id: "ports", title: "Ports", items: items)) }
        return sections
    }

    private static func configMap(_ object: [String: Any]) -> [DetailSection] {
        let keys = (object["data"] as? [String: Any])?.keys.sorted() ?? []
        guard !keys.isEmpty else { return [] }
        return [DetailSection(id: "data", title: "Data (\(keys.count))", items: keys)]
    }

    private static func secret(_ object: [String: Any]) -> [DetailSection] {
        var rows: [DetailRow] = []
        if let type = object["type"] as? String { rows.append(DetailRow(label: "Type", value: type)) }
        let keys = (object["data"] as? [String: Any])?.keys.sorted() ?? []
        var sections: [DetailSection] = []
        if !rows.isEmpty { sections.append(DetailSection(id: "secret", title: "Secret", rows: rows)) }
        if !keys.isEmpty {
            sections.append(DetailSection(id: "keys", title: "Keys (\(keys.count))", items: keys))
        }
        return sections
    }

    private static func node(_ object: [String: Any]) -> [DetailSection] {
        let status = object["status"] as? [String: Any]
        let info = status?["nodeInfo"] as? [String: Any]
        var rows: [DetailRow] = []
        if let version = info?["kubeletVersion"] as? String {
            rows.append(DetailRow(label: "Kubelet", value: version))
        }
        if let os = info?["osImage"] as? String { rows.append(DetailRow(label: "OS", value: os)) }
        if let runtime = info?["containerRuntimeVersion"] as? String {
            rows.append(DetailRow(label: "Runtime", value: runtime))
        }
        var items: [String] = []
        if let addresses = status?["addresses"] as? [[String: Any]] {
            items = addresses.map { "\($0["type"] as? String ?? "?"): \($0["address"] as? String ?? "")" }
        }
        var sections: [DetailSection] = []
        if !rows.isEmpty { sections.append(DetailSection(id: "node", title: "Node", rows: rows)) }
        if !items.isEmpty {
            sections.append(DetailSection(id: "addresses", title: "Addresses", items: items))
        }
        return sections
    }

    private static func pvc(_ object: [String: Any]) -> [DetailSection] {
        let spec = object["spec"] as? [String: Any]
        let status = object["status"] as? [String: Any]
        var rows: [DetailRow] = []
        if let phase = status?["phase"] as? String { rows.append(DetailRow(label: "Phase", value: phase)) }
        if let capacity = (status?["capacity"] as? [String: Any])?["storage"] as? String {
            rows.append(DetailRow(label: "Capacity", value: capacity))
        }
        if let className = spec?["storageClassName"] as? String {
            rows.append(DetailRow(label: "Storage Class", value: className))
        }
        if let modes = spec?["accessModes"] as? [String] {
            rows.append(DetailRow(label: "Access Modes", value: modes.joined(separator: ", ")))
        }
        guard !rows.isEmpty else { return [] }
        return [DetailSection(id: "pvc", title: "Volume Claim", rows: rows)]
    }

    private static func ingress(_ object: [String: Any]) -> [DetailSection] {
        let spec = object["spec"] as? [String: Any]
        var items: [String] = []
        if let rules = spec?["rules"] as? [[String: Any]] {
            items = rules.compactMap { $0["host"] as? String }
        }
        guard !items.isEmpty else { return [] }
        return [DetailSection(id: "hosts", title: "Hosts", items: items)]
    }
}
