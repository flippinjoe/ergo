import KubeClient
import KubeCore
import SwiftUI
import Testing

@testable import KubeUI

/// Smoke tests that force each key view to actually evaluate its `body` by
/// rasterizing it with `ImageRenderer`. They don't assert pixels — they catch
/// crashes, bad bindings, and layout traps that only surface at render time,
/// which plain value construction (which never touches `body`) would miss.
@MainActor
@Suite("View rendering")
struct RenderSmokeTests {
    private func renders(_ view: some View) -> Bool {
        let renderer = ImageRenderer(content: view.frame(width: 360, height: 640))
        return renderer.cgImage != nil
    }

    private func meta(_ name: String) -> ObjectMeta {
        ObjectMeta(
            name: name, namespace: "default", uid: "uid-\(name)", creationTimestamp: Date(),
            labels: ["app": name], annotations: ["note": "hi"])
    }

    @Test("Inspector renders with custom detail sections")
    func inspector() {
        let data = InspectorData(
            id: "1", kindTitle: "Pod", iconName: "shippingbox", meta: meta("api"),
            statusText: "Running", health: .ok, manifest: "{\n  \"kind\": \"Pod\"\n}", events: [],
            detailSections: [
                DetailSection(
                    id: "pod", title: "Pod",
                    rows: [DetailRow(label: "Phase", value: "Running")]),
                DetailSection(id: "containers", title: "Containers", items: ["app · nginx:1.25"]),
            ])
        #expect(renders(InspectorView(data: data, onClose: {})))
    }

    @Test("Resource table renders with rows")
    func resourceTable() {
        let rows = [
            ResourceRow(
                id: "1", name: "web", namespace: "default", statusText: "Ready", health: .ok,
                detail: "3/3", age: "2d", created: Date())
        ]
        #expect(
            renders(
                ResourceTableView(
                    title: "Deployments", description: "A Deployment.", rows: rows,
                    detailTitle: "Ready", loadError: nil, isLoading: false, selection: .constant(nil))))
    }

    @Test("Pods table renders with pods")
    func podsTable() {
        let pods = [
            Pod(
                metadata: meta("api-0"), spec: Pod.Spec(nodeName: "node-1"),
                status: Pod.Status(phase: "Running"))
        ]
        #expect(
            renders(
                PodsTableView(
                    pods: pods, description: "A Pod.", loadError: nil, isLoading: false,
                    selection: .constant(nil))))
    }

    @Test("Sidebar renders with pinned + grouped sections")
    func sidebar() {
        let pod = APIResource(group: "", version: "v1", resource: "pods", kind: "Pod", namespaced: true)
        let deploy = APIResource(
            group: "apps", version: "v1", resource: "deployments", kind: "Deployment", namespaced: true)
        let sections = ResourceCatalog.sections(from: [pod, deploy], grouping: .curated)
        let clusters = ClustersModel(store: InMemoryClusterStore(), azure: FakeAzureClusterService())
        let view = SidebarView(
            selection: .constant(pod), grouping: .constant(.curated), sections: sections,
            counts: [pod.id: 4], expanded: ["Workloads"], onToggleSection: { _ in },
            pinned: [pod], pinnedIDs: [pod.id], onTogglePin: { _ in }, onMovePinned: { _, _ in },
            clusters: clusters, onAddCluster: {}, onManage: {})
        #expect(renders(view))
    }
}
