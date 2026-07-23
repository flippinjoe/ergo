import KubeClient
import KubeCore
import SwiftUI

/// A minimal shared SwiftUI surface, kept platform-agnostic so a future
/// iOS/iPadOS companion can reuse it. It renders whatever a `ClusterClient`
/// returns; in previews and tests that client is `FakeClusterClient`.
///
/// This is scaffolding, not a feature — it exists to prove the module graph
/// links SwiftUI against the domain layers and to give the app target a view
/// to host.
public struct ClusterBrowserView: View {
    private let client: any ClusterClient
    @State private var pods: [Pod] = []
    @State private var loadError: String?

    public init(client: any ClusterClient) {
        self.client = client
    }

    public var body: some View {
        List {
            Section("Pods") {
                if let loadError {
                    Text(loadError).foregroundStyle(.secondary)
                } else if pods.isEmpty {
                    Text("Loading…").foregroundStyle(.secondary)
                } else {
                    ForEach(pods) { pod in
                        HStack {
                            Text(pod.metadata.name)
                            Spacer()
                            Text(pod.status?.phase ?? "Unknown")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task {
            do {
                pods = try await client.listPods(namespace: nil)
            } catch {
                loadError = String(describing: error)
            }
        }
    }
}

#if DEBUG
#Preview {
    ClusterBrowserView(client: FakeClusterClient())
        .frame(width: 420, height: 320)
}
#endif
