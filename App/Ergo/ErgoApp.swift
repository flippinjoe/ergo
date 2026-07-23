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
            ClusterExplorerView(
                client: FakeClusterClient(),
                // Saved clusters persist on-device. Azure discovery is live:
                // interactive Microsoft sign-in via the system browser + loopback,
                // tokens cached in the Keychain. (The per-cluster pod client is
                // still the demo FakeClusterClient until the live client lands.)
                clusterStore: FileClusterStore(),
                azureService: LiveAzureClusterService(
                    webAuthenticator: SystemWebAuthenticator(),
                    tokenStore: KeychainTokenStore()
                )
            )
            .frame(minWidth: 900, minHeight: 560)
            .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
