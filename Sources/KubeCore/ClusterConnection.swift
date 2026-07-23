import Foundation

/// A saved cluster the user has added to Ergo. This is *connection metadata* —
/// how to reach a cluster and where it came from — not a live client. Selecting
/// one is what a future step will turn into a `ClusterClient`.
///
/// Connections persist on-device (per the privacy stance: nothing about the
/// user's clusters leaves this Mac). Secrets (tokens, kubeconfig bytes) are held
/// separately in the Keychain, never in this value.
public struct ClusterConnection: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var displayName: String
    public var source: ClusterSource
    public var addedAt: Date
    /// API server URL, when known (shown in the manager; not required).
    public var server: String?
    /// Kubernetes context name this connection maps to, when applicable.
    public var contextName: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        source: ClusterSource,
        addedAt: Date,
        server: String? = nil,
        contextName: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.addedAt = addedAt
        self.server = server
        self.contextName = contextName
    }
}

/// Where a `ClusterConnection` came from. New sources (GKE, EKS, Rancher…) are
/// added as cases — the pillar-3 "auth & agents" seam widens here.
public enum ClusterSource: Hashable, Sendable, Codable {
    case azure(AzureClusterRef)
    case kubeconfig(KubeconfigRef)
    /// A built-in sample connection so the explorer has something to show
    /// before the user adds a real cluster.
    case mock

    public var kind: Kind {
        switch self {
        case .azure: .azure
        case .kubeconfig: .kubeconfig
        case .mock: .mock
        }
    }

    /// Stable identity of the *target* a source points at, used to dedupe when
    /// the same cluster is discovered twice.
    public var identityKey: String {
        switch self {
        case .azure(let ref): "azure:\(ref.resourceID)"
        case .kubeconfig(let ref): "kubeconfig:\(ref.path)#\(ref.contextName)"
        case .mock: "mock"
        }
    }

    /// The coarse provider identity — drives the icon/label in the UI.
    public enum Kind: String, Sendable, Codable, CaseIterable, Identifiable {
        case azure
        case kubeconfig
        case mock

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .azure: "Azure (AKS)"
            case .kubeconfig: "Kubeconfig file"
            case .mock: "Sample"
            }
        }
    }
}

/// Points at a specific AKS cluster in ARM. Enough to re-fetch credentials
/// later without re-discovering.
public struct AzureClusterRef: Hashable, Sendable, Codable {
    /// Full ARM resource ID
    /// (`/subscriptions/…/resourceGroups/…/providers/Microsoft.ContainerService/managedClusters/…`).
    public var resourceID: String
    public var subscriptionID: String
    public var resourceGroup: String
    public var clusterName: String
    public var tenantID: String?
    public var location: String?

    public init(
        resourceID: String,
        subscriptionID: String,
        resourceGroup: String,
        clusterName: String,
        tenantID: String? = nil,
        location: String? = nil
    ) {
        self.resourceID = resourceID
        self.subscriptionID = subscriptionID
        self.resourceGroup = resourceGroup
        self.clusterName = clusterName
        self.tenantID = tenantID
        self.location = location
    }
}

/// Points at a context inside a kubeconfig file on disk.
public struct KubeconfigRef: Hashable, Sendable, Codable {
    public var path: String
    public var contextName: String

    public init(path: String, contextName: String) {
        self.path = path
        self.contextName = contextName
    }
}
