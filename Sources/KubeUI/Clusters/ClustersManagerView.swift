import KubeCore
import SwiftUI

/// Manage saved clusters: see them all, select one, remove one, or start the
/// add flow. Presented as a sheet from the sidebar's cluster switcher.
struct ClustersManagerView: View {
    let clusters: ClustersModel
    let onAddCluster: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Clusters").font(Nocturne.Font.heading)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderless)
            }
            .padding(Nocturne.Space.s4)
            Divider().overlay(Nocturne.divider)

            if clusters.connections.isEmpty {
                ContentUnavailableView(
                    "No clusters yet", systemImage: "cube.transparent",
                    description: Text("Add one to get started.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(clusters.connections) { connection in
                        row(connection)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }

            Divider().overlay(Nocturne.divider)
            HStack {
                Button {
                    onAddCluster()
                } label: {
                    Label("Add Cluster…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(Nocturne.Space.s4)
        }
        .frame(width: 520, height: 420)
        .background(Nocturne.surface)
        .tint(Nocturne.accent)
    }

    private func row(_ connection: ClusterConnection) -> some View {
        HStack(spacing: Nocturne.Space.s3) {
            Image(systemName: connection.source.kind.systemImage)
                .foregroundStyle(Nocturne.accent200)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.displayName).font(Nocturne.Font.body)
                Text("\(connection.source.kind.title) · \(connection.subtitle)")
                    .font(.system(size: 10))
                    .foregroundStyle(Nocturne.muted(0.5))
            }
            Spacer()
            if clusters.selectedID == connection.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Nocturne.statusOK)
            }
            Button(role: .destructive) {
                Task { await clusters.remove(connection) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Nocturne.muted(0.5))
        }
        .contentShape(Rectangle())
        .onTapGesture { clusters.select(connection) }
    }
}
