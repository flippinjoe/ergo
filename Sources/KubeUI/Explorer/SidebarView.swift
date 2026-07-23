import KubeCore
import SwiftUI

/// The glass navigation sidebar: a cluster switcher, the resource sections, and
/// a privacy footer. Counts are illustrative except Pods, which reflects loaded
/// data.
struct SidebarView: View {
    @Binding var selection: ResourceKind
    let podCount: Int

    // Illustrative counts / statuses for kinds not yet wired to live data.
    private func trailing(for kind: ResourceKind) -> SidebarRow.Trailing {
        switch kind {
        case .pods: .count(podCount)
        case .deployments: .count(17)
        case .statefulSets: .count(4)
        case .certificates: .status(.warning)
        case .applications: .count(22)
        case .scaledObjects: .none
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Nocturne.Space.s1) {
            ClusterSwitcher()
                .padding(.bottom, Nocturne.Space.s2)

            ForEach(ResourceKind.Section.allCases) { section in
                Text(section.rawValue.uppercased())
                    .font(Nocturne.Font.caption)
                    .kerning(1.1)
                    .foregroundStyle(Nocturne.muted(0.42))
                    .padding(.horizontal, Nocturne.Space.s3)
                    .padding(.top, Nocturne.Space.s6)
                    .padding(.bottom, Nocturne.Space.s2)

                ForEach(section.kinds) { kind in
                    SidebarRow(
                        kind: kind,
                        isSelected: selection == kind,
                        trailing: trailing(for: kind)
                    ) { selection = kind }
                }
            }

            Spacer(minLength: 0)

            Label("kubeconfig stays on this Mac", systemImage: "lock")
                .font(Nocturne.Font.small)
                .foregroundStyle(Nocturne.muted(0.55))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, Nocturne.Space.s3)
                .padding(.vertical, Nocturne.Space.s3)
                .tint(Nocturne.statusOK)
        }
        .padding(Nocturne.Space.s3)
        .frame(minWidth: 220)
    }
}

/// The top-of-sidebar cluster identity + switcher affordance.
private struct ClusterSwitcher: View {
    var body: some View {
        HStack(spacing: Nocturne.Space.s3) {
            StatusDot(health: .ok)
            VStack(alignment: .leading, spacing: 1) {
                Text("prod-eks").font(Nocturne.Font.bodyEmphasis)
                Text("us-east-1 · EKS 1.31")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Nocturne.muted(0.46))
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
    }
}

/// One sidebar row: icon + label + a trailing count or status dot, with the
/// accent-tinted selected state from the design.
struct SidebarRow: View {
    enum Trailing {
        case count(Int)
        case status(HealthStatus)
        case none
    }

    let kind: ResourceKind
    let isSelected: Bool
    let trailing: Trailing
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Nocturne.Space.s3) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(kind.title)
                    .font(Nocturne.Font.body)
                Spacer(minLength: Nocturne.Space.s2)
                trailingView
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

    @ViewBuilder private var trailingView: some View {
        switch trailing {
        case .count(let n):
            Text("\(n)")
                .font(Nocturne.Font.small)
                .foregroundStyle(Nocturne.muted(isSelected ? 0.7 : 0.55))
        case .status(let health):
            StatusDot(health: health, size: 7)
        case .none:
            EmptyView()
        }
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
