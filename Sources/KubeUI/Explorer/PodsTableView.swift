import KubeCore
import SwiftUI

/// The Pods content pane: a solid data table (content never sits on glass) with
/// the columns from the design — Name, Namespace, Status, Restarts, Age, Node.
struct PodsTableView: View {
    let pods: [Pod]
    let loadError: String?
    var isLoading: Bool = false
    /// Injected so ages are stable in previews/tests; defaults to the wall clock.
    var now: Date = Date()

    @State private var selection: Pod.ID?
    @State private var sortOrder: [KeyPathComparator<Pod>] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load pods", systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading && pods.isEmpty {
                VStack(spacing: Nocturne.Space.s3) {
                    ProgressView()
                    Text("Connecting to cluster…").font(Nocturne.Font.small).foregroundStyle(
                        Nocturne.muted(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pods.isEmpty {
                ContentUnavailableView("No pods", systemImage: "shippingbox")
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

    private var sortedPods: [Pod] {
        sortOrder.isEmpty ? pods : pods.sorted(using: sortOrder)
    }

    private var table: some View {
        Table(sortedPods, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.sortName) { pod in
                Text(pod.metadata.name).font(Nocturne.Font.mono)
            }
            TableColumn("Namespace", value: \.sortNamespace) { pod in
                Text(pod.metadata.namespace ?? "—").font(Nocturne.Font.body)
            }
            TableColumn("Status", value: \.sortStatus) { pod in
                StatusLabel(pod.displayStatus, health: pod.health)
            }
            TableColumn("Restarts", value: \.restartCount) { pod in
                Text("\(pod.restartCount)")
                    .font(Nocturne.Font.body)
                    .foregroundStyle(pod.restartCount > 0 ? Nocturne.statusError : Nocturne.text)
            }
            .width(70)
            TableColumn("Age", value: \.sortCreated) { pod in
                Text(pod.metadata.age(now: now) ?? "—").font(Nocturne.Font.body)
            }
            .width(60)
            TableColumn("Node", value: \.sortNode) { pod in
                Text(pod.spec?.nodeName ?? "—")
                    .font(Nocturne.Font.mono)
                    .foregroundStyle(Nocturne.muted(0.6))
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .threeStateSort($sortOrder)
    }
}

extension KubeCore.Pod {
    /// Non-optional keys for `Table` column sorting.
    fileprivate var sortName: String { metadata.name }
    fileprivate var sortNamespace: String { metadata.namespace ?? "" }
    fileprivate var sortStatus: String { displayStatus }
    fileprivate var sortNode: String { spec?.nodeName ?? "" }
    fileprivate var sortCreated: Date { metadata.creationTimestamp ?? .distantPast }
}
