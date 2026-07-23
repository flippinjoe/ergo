import Foundation

/// Per-cluster sidebar customization: which resource types the user has pinned
/// to the top, in what order. Persisted on-device (per the privacy stance) and
/// keyed by a cluster's *stable identity*, so re-adding the same cluster keeps
/// its layout.
struct SidebarLayout: Codable, Equatable, Sendable {
    /// Ordered `APIResource.id`s pinned above the grouped sections.
    var pinned: [String] = []

    /// Returns `pinned` with `draggedID` moved to sit before `targetID`
    /// (or appended to the end when `targetID` is nil). A no-op if the dragged
    /// id isn't present.
    static func reorder(_ ids: [String], moving draggedID: String, before targetID: String?) -> [String] {
        guard let from = ids.firstIndex(of: draggedID) else { return ids }
        var ids = ids
        ids.remove(at: from)
        if let targetID, let index = ids.firstIndex(of: targetID) {
            ids.insert(draggedID, at: index)
        } else {
            ids.append(draggedID)
        }
        return ids
    }
}

/// Reads/writes a `SidebarLayout` per cluster. A protocol so the explorer can be
/// driven by an in-memory double in tests.
protocol SidebarLayoutStore {
    func layout(for clusterKey: String) -> SidebarLayout
    func save(_ layout: SidebarLayout, for clusterKey: String)
}

/// `UserDefaults`-backed store: one JSON blob per cluster under a namespaced key.
struct UserDefaultsSidebarLayoutStore: SidebarLayoutStore {
    private let defaults: UserDefaults
    private let prefix = "ergo.sidebarLayout."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func layout(for clusterKey: String) -> SidebarLayout {
        guard let data = defaults.data(forKey: prefix + clusterKey),
            let layout = try? JSONDecoder().decode(SidebarLayout.self, from: data)
        else { return SidebarLayout() }
        return layout
    }

    func save(_ layout: SidebarLayout, for clusterKey: String) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: prefix + clusterKey)
    }
}
