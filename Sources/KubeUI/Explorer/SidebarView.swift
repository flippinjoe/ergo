import KubeCore
import SwiftUI

/// The glass navigation sidebar: a cluster switcher, the discovered resource
/// types grouped by API group, and a privacy footer.
struct SidebarView: View {
    @Binding var selection: APIResource?
    @Binding var grouping: SidebarGrouping
    let sections: [SidebarSection]
    let counts: [String: Int]
    let expanded: Set<String>
    let onToggleSection: (String) -> Void
    let clusters: ClustersModel
    let onAddCluster: () -> Void
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClusterSwitcher(clusters: clusters, onAddCluster: onAddCluster, onManage: onManage)
                .padding(Nocturne.Space.s3)
                .padding(.bottom, Nocturne.Space.s1)

            Picker("Grouping", selection: $grouping) {
                ForEach(SidebarGrouping.allCases, id: \.self) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, Nocturne.Space.s3)
            .padding(.bottom, Nocturne.Space.s2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Nocturne.Space.s1) {
                    ForEach(sections) { section in
                        sectionHeader(section)
                        if expanded.contains(section.id) {
                            ForEach(section.resources) { resource in
                                SidebarRow(
                                    resource: resource,
                                    isSelected: selection == resource,
                                    count: counts[resource.id]
                                ) { selection = resource }
                            }
                        }
                    }
                }
                .padding(.horizontal, Nocturne.Space.s3)
                .padding(.bottom, Nocturne.Space.s3)
            }

            Label("kubeconfig stays on this Mac", systemImage: "lock")
                .font(Nocturne.Font.small)
                .foregroundStyle(Nocturne.muted(0.55))
                .labelStyle(.titleAndIcon)
                .padding(Nocturne.Space.s4)
                .tint(Nocturne.statusOK)
        }
        .frame(minWidth: 220)
    }

    private func sectionHeader(_ section: SidebarSection) -> some View {
        let isOpen = expanded.contains(section.id)
        return Button {
            onToggleSection(section.id)
        } label: {
            HStack(spacing: Nocturne.Space.s2) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .foregroundStyle(Nocturne.muted(0.4))
                Text(section.title)
                    .font(Nocturne.Font.caption)
                    .foregroundStyle(Nocturne.muted(0.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(section.resources.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(Nocturne.muted(0.3))
            }
            .padding(.horizontal, Nocturne.Space.s3)
            .padding(.top, Nocturne.Space.s4)
            .padding(.bottom, Nocturne.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The top-of-sidebar cluster identity + switcher menu: switch between saved
/// clusters, add one, or open the manager.
private struct ClusterSwitcher: View {
    let clusters: ClustersModel
    let onAddCluster: () -> Void
    let onManage: () -> Void

    var body: some View {
        Menu {
            ForEach(clusters.connections) { connection in
                Button {
                    clusters.select(connection)
                } label: {
                    if clusters.selectedID == connection.id {
                        Label(connection.displayName, systemImage: "checkmark")
                    } else {
                        Text(connection.displayName)
                    }
                }
            }
            Divider()
            Button {
                onAddCluster()
            } label: {
                Label("Add Cluster…", systemImage: "plus")
            }
            Button {
                onManage()
            } label: {
                Label("Manage Clusters…", systemImage: "slider.horizontal.3")
            }
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var label: some View {
        HStack(spacing: Nocturne.Space.s3) {
            StatusDot(health: .ok)
            VStack(alignment: .leading, spacing: 1) {
                Text(clusters.selected?.displayName ?? "No cluster")
                    .font(Nocturne.Font.bodyEmphasis)
                    .foregroundStyle(Nocturne.text)
                Text(clusters.selected?.subtitle ?? "Add a cluster to begin")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Nocturne.muted(0.46))
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11))
                .foregroundStyle(Nocturne.muted(0.48))
        }
        .padding(.horizontal, Nocturne.Space.s3)
        .padding(.vertical, Nocturne.Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Nocturne.Radius.md + 2, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .contentShape(Rectangle())
    }
}

/// One sidebar row: icon + label + an optional live count, with the
/// accent-tinted selected state from the design.
struct SidebarRow: View {
    let resource: APIResource
    let isSelected: Bool
    let count: Int?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Nocturne.Space.s3) {
                Image(systemName: ResourceCatalog.icon(for: resource))
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(resource.displayName)
                    .font(Nocturne.Font.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Nocturne.Space.s2)
                if let count {
                    Text("\(count)")
                        .font(Nocturne.Font.small)
                        .foregroundStyle(Nocturne.muted(isSelected ? 0.7 : 0.55))
                }
            }
            .foregroundStyle(isSelected ? Nocturne.text : Nocturne.muted(0.74))
            .padding(.horizontal, Nocturne.Space.s3)
            .padding(.vertical, Nocturne.Space.s2 + 1)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Nocturne.Radius.md + 1, style: .continuous)
        if isSelected {
            shape.fill(Nocturne.accent.opacity(0.28))
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        } else if isHovering {
            shape.fill(Color.white.opacity(0.07))
        } else {
            shape.fill(.clear)
        }
    }
}
