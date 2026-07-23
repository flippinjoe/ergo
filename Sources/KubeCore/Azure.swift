import Foundation

/// The signed-in Azure identity. The access/refresh tokens live in the
/// Keychain, never in this value — this is just who we are and which tenant.
public struct AzureAccount: Hashable, Sendable, Codable {
    public var username: String
    public var tenantID: String

    public init(username: String, tenantID: String) {
        self.username = username
        self.tenantID = tenantID
    }
}

/// An Azure subscription, as returned by ARM's subscriptions list.
public struct AzureSubscription: Identifiable, Hashable, Sendable, Codable {
    public var subscriptionID: String
    public var displayName: String
    public var tenantID: String

    public var id: String { subscriptionID }

    public init(subscriptionID: String, displayName: String, tenantID: String) {
        self.subscriptionID = subscriptionID
        self.displayName = displayName
        self.tenantID = tenantID
    }
}

/// An AKS cluster discovered under a subscription
/// (`Microsoft.ContainerService/managedClusters`).
public struct AzureManagedCluster: Identifiable, Hashable, Sendable, Codable {
    public var resourceID: String
    public var name: String
    public var resourceGroup: String
    public var location: String
    public var kubernetesVersion: String
    public var powerState: String?
    public var subscriptionID: String
    public var tenantID: String?

    public var id: String { resourceID }

    public init(
        resourceID: String,
        name: String,
        resourceGroup: String,
        location: String,
        kubernetesVersion: String,
        powerState: String? = nil,
        subscriptionID: String,
        tenantID: String? = nil
    ) {
        self.resourceID = resourceID
        self.name = name
        self.resourceGroup = resourceGroup
        self.location = location
        self.kubernetesVersion = kubernetesVersion
        self.powerState = powerState
        self.subscriptionID = subscriptionID
        self.tenantID = tenantID
    }

    /// Health bucket from the cluster's power state (Running → ok, Stopped →
    /// warning). Reuses the shared `HealthStatus` vocabulary.
    public var health: HealthStatus {
        guard let powerState else { return .unknown }
        return HealthStatus(kubernetesStatus: powerState)
    }

    /// A persistable reference to this cluster.
    public var ref: AzureClusterRef {
        AzureClusterRef(
            resourceID: resourceID,
            subscriptionID: subscriptionID,
            resourceGroup: resourceGroup,
            clusterName: name,
            tenantID: tenantID,
            location: location
        )
    }

    /// Builds a saved connection for this cluster.
    public func connection(addedAt: Date) -> ClusterConnection {
        ClusterConnection(
            displayName: name,
            source: .azure(ref),
            addedAt: addedAt,
            contextName: name
        )
    }
}
