import Foundation
import Testing

@testable import KubeUI

@Suite("Sidebar layout")
struct SidebarLayoutTests {
    @Test("Reorder moves an item before a target")
    func moveBefore() {
        let ids = ["a", "b", "c", "d"]
        #expect(SidebarLayout.reorder(ids, moving: "d", before: "b") == ["a", "d", "b", "c"])
        #expect(SidebarLayout.reorder(ids, moving: "a", before: "c") == ["b", "a", "c", "d"])
    }

    @Test("Reorder with a nil target moves the item to the end")
    func moveToEnd() {
        #expect(SidebarLayout.reorder(["a", "b", "c"], moving: "a", before: nil) == ["b", "c", "a"])
    }

    @Test("Reorder is a no-op for an unknown id")
    func unknownID() {
        #expect(SidebarLayout.reorder(["a", "b"], moving: "z", before: "a") == ["a", "b"])
    }

    @Test("Store round-trips a layout per cluster key")
    func storeRoundTrip() {
        let suite = "ergo.sidebar.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSidebarLayoutStore(defaults: defaults)

        #expect(store.layout(for: "cluster-1").pinned.isEmpty)
        store.save(SidebarLayout(pinned: ["v1/pods", "apps/v1/deployments"]), for: "cluster-1")
        store.save(SidebarLayout(pinned: ["v1/services"]), for: "cluster-2")

        #expect(store.layout(for: "cluster-1").pinned == ["v1/pods", "apps/v1/deployments"])
        #expect(store.layout(for: "cluster-2").pinned == ["v1/services"])
    }
}
