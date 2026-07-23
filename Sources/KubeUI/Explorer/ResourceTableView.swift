import KubeCore
import SwiftUI

/// A generic content pane for any resource kind that isn't Pods: a solid table
/// with Name, Namespace, Status, an optional kind-specific detail column, and
/// Age. Driven entirely by `[ResourceRow]`.
struct ResourceTableView: View {
    let title: String
    let rows: [ResourceRow]
    /// Title of the kind-specific column (e.g. "Ready"); nil to omit it.
    let detailTitle: String?
    let loadError: String?
    let isLoading: Bool

    @State private var selection: ResourceRow.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load \(title.lowercased())", systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading && rows.isEmpty {
                VStack(spacing: Nocturne.Space.s3) {
                    ProgressView()
                    Text("Loading…").font(Nocturne.Font.small).foregroundStyle(Nocturne.muted(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView("No \(title.lowercased())", systemImage: "tray")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
    }

    private var header: some View {
        HStack(spacing: Nocturne.Space.s3) {
            Text(title).font(Nocturne.Font.heading)
            Tag("\(rows.count)")
            Spacer()
        }
        .padding(.horizontal, Nocturne.Space.s6)
        .padding(.top, Nocturne.Space.s6)
        .padding(.bottom, Nocturne.Space.s3)
    }

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("Name") { row in
                Text(row.name).font(Nocturne.Font.mono)
            }
            TableColumn("Namespace") { row in
                Text(row.namespace ?? "—").font(Nocturne.Font.body)
            }
            TableColumn("Status") { row in
                StatusLabel(row.statusText ?? Self.label(for: row.health), health: row.health)
            }
            if let detailTitle {
                TableColumn(detailTitle) { row in
                    Text(row.detail ?? "—")
                        .font(Nocturne.Font.body)
                        .foregroundStyle(row.health == .ok ? Nocturne.text : Nocturne.statusWarn)
                }
                .width(70)
            }
            TableColumn("Age") { row in
                Text(row.age ?? "—").font(Nocturne.Font.body)
            }
            .width(60)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
    }

    /// Fallback status text when the resource exposes no explicit status string.
    private static func label(for health: HealthStatus) -> String {
        switch health {
        case .ok: "Ready"
        case .warning: "Pending"
        case .error: "Error"
        case .info: "Info"
        case .unknown: "—"
        }
    }
}
