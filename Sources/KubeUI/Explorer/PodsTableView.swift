import KubeCore
import SwiftUI

/// The Pods content pane: a solid data table (content never sits on glass) with
/// the columns from the design — Name, Namespace, Status, Restarts, Age, Node.
struct PodsTableView: View {
    let pods: [Pod]
    let loadError: String?
    /// Injected so ages are stable in previews/tests; defaults to the wall clock.
    var now: Date = Date()

    @State private var selection: Pod.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load pods", systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
    }

    private var header: some View {
        HStack(spacing: Nocturne.Space.s3) {
            Text("Pods").font(Nocturne.Font.heading)
            Tag("all namespaces · \(pods.count)")
            Spacer()
        }
        .padding(.horizontal, Nocturne.Space.s6)
        .padding(.top, Nocturne.Space.s6)
        .padding(.bottom, Nocturne.Space.s3)
    }

    private var table: some View {
        Table(pods, selection: $selection) {
            TableColumn("Name") { pod in
                Text(pod.metadata.name).font(Nocturne.Font.mono)
            }
            TableColumn("Namespace") { pod in
                Text(pod.metadata.namespace ?? "—").font(Nocturne.Font.body)
            }
            TableColumn("Status") { pod in
                StatusLabel(pod.displayStatus, health: pod.health)
            }
            TableColumn("Restarts") { pod in
                Text("\(pod.restartCount)")
                    .font(Nocturne.Font.body)
                    .foregroundStyle(pod.restartCount > 0 ? Nocturne.statusError : Nocturne.text)
            }
            .width(70)
            TableColumn("Age") { pod in
                Text(pod.metadata.age(now: now) ?? "—").font(Nocturne.Font.body)
            }
            .width(60)
            TableColumn("Node") { pod in
                Text(pod.spec?.nodeName ?? "—")
                    .font(Nocturne.Font.mono)
                    .foregroundStyle(Nocturne.muted(0.6))
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
    }
}
