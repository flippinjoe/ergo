import KubeClient
import KubeUI
import SwiftUI

/// The macOS app entry point. It composes the shared, platform-agnostic
/// `KubeUI` surface with a concrete `ClusterClient`. The skeleton wires the
/// hermetic `FakeClusterClient` so the app launches and renders sample data
/// without ever touching a real cluster.
@main
struct ErgoApp: App {
    var body: some Scene {
        WindowGroup {
            ClusterExplorerView(client: FakeClusterClient())
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
