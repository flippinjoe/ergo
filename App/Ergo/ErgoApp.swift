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
            explorer
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }

    /// Composition root. Live Azure sign-in + discovery; the client factory
    /// builds a live `LiveKubernetesClient` per selected cluster (demo data for
    /// the sample connection). Everything on-device: kubeconfig stays local,
    /// tokens in the Keychain.
    private var explorer: some View {
        let tokenStore = KeychainTokenStore()
        let azure = LiveAzureClusterService(
            webAuthenticator: SystemWebAuthenticator(),
            tokenStore: tokenStore
        )
        let factory = DefaultClusterClientFactory(
            azure: azure,
            tokenStore: tokenStore,
            demoClient: FakeClusterClient()
        )
        return ClusterExplorerView(
            clientProvider: factory,
            clusterStore: FileClusterStore(),
            azureService: azure
        )
    }
}
