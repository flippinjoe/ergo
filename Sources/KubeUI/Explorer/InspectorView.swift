import KubeCore
import SwiftUI

/// What the inspector shows for a selected object — built from the raw watch
/// object's metadata plus its related events (pillar 1: relationships & time).
struct InspectorData: Identifiable {
    let id: String
    let kind: ResourceKind
    let meta: ObjectMeta
    let statusText: String?
    let health: HealthStatus
    var events: [EventRecord]
}

/// A glass inspector panel (right of the content, per the design) with the
/// object's identity, metadata, owner chain, and recent events.
struct InspectorView: View {
    let data: InspectorData
    let onClose: () -> Void
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Nocturne.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: Nocturne.Space.s6) {
                    metadataSection
                    if let owners = data.meta.ownerReferences, !owners.isEmpty {
                        ownersSection(owners)
                    }
                    eventsSection
                }
                .padding(Nocturne.Space.s4)
            }
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .glassPanel(cornerRadius: Nocturne.Radius.lg)
        .padding(Nocturne.Space.s3)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Nocturne.Space.s3) {
            Image(systemName: data.kind.systemImage)
                .foregroundStyle(Nocturne.accent200)
            VStack(alignment: .leading, spacing: 2) {
                Text(data.meta.name).font(Nocturne.Font.bodyEmphasis).textSelection(.enabled)
                StatusLabel(data.statusText ?? label(for: data.health), health: data.health)
            }
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(Nocturne.muted(0.6))
        }
        .padding(Nocturne.Space.s4)
    }

    private var metadataSection: some View {
        section("Metadata") {
            field("Namespace", data.meta.namespace ?? "—")
            if let created = data.meta.creationTimestamp {
                field("Age", RelativeAge.string(from: created, now: now))
            }
            if let uid = data.meta.uid {
                field("UID", uid, mono: true)
            }
            if let labels = data.meta.labels, !labels.isEmpty {
                VStack(alignment: .leading, spacing: Nocturne.Space.s2) {
                    Text("Labels").font(Nocturne.Font.small).foregroundStyle(Nocturne.muted(0.5))
                    FlowChips(labels.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" })
                }
            }
        }
    }

    private func ownersSection(_ owners: [OwnerReference]) -> some View {
        section("Owner references") {
            ForEach(owners, id: \.uid) { owner in
                HStack(spacing: Nocturne.Space.s2) {
                    Image(systemName: "arrow.up.forward").font(.system(size: 10))
                        .foregroundStyle(Nocturne.muted(0.5))
                    Text(owner.kind).font(Nocturne.Font.small).foregroundStyle(Nocturne.muted(0.6))
                    Text(owner.name).font(Nocturne.Font.mono).textSelection(.enabled)
                }
            }
        }
    }

    private var eventsSection: some View {
        section("Events") {
            if data.events.isEmpty {
                Text("No recent events.").font(Nocturne.Font.small).foregroundStyle(Nocturne.muted(0.4))
            } else {
                ForEach(data.events) { event in
                    HStack(alignment: .top, spacing: Nocturne.Space.s2) {
                        StatusDot(health: event.type == "Warning" ? .warning : .ok, size: 6)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: Nocturne.Space.s2) {
                                Text(event.reason ?? "Event").font(Nocturne.Font.small)
                                Spacer()
                                if let ts = event.lastTimestamp {
                                    Text(RelativeAge.string(from: ts, now: now))
                                        .font(.system(size: 10)).foregroundStyle(Nocturne.muted(0.4))
                                }
                            }
                            if let message = event.message {
                                Text(message).font(.system(size: 11))
                                    .foregroundStyle(Nocturne.muted(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: helpers

    @ViewBuilder private func section(
        _ title: String, @ViewBuilder _ content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: Nocturne.Space.s3) {
            Text(title.uppercased())
                .font(Nocturne.Font.caption).kerning(0.8)
                .foregroundStyle(Nocturne.muted(0.42))
            content()
        }
    }

    private func field(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label).font(Nocturne.Font.small).foregroundStyle(Nocturne.muted(0.5))
            Spacer()
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : Nocturne.Font.small)
                .foregroundStyle(Nocturne.muted(0.85))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func label(for health: HealthStatus) -> String {
        switch health {
        case .ok: "Ready"
        case .warning: "Pending"
        case .error: "Error"
        case .info: "Info"
        case .unknown: "—"
        }
    }
}

/// A simple wrapping row of chips for labels.
private struct FlowChips: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }

    var body: some View {
        VStack(alignment: .leading, spacing: Nocturne.Space.s2) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Nocturne.accent200)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, Nocturne.Space.s2)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: Nocturne.Radius.sm, style: .continuous)
                            .fill(Color.white.opacity(0.06)))
            }
        }
    }
}
