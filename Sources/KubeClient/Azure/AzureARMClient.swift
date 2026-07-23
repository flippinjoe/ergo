import Foundation
import KubeCore

/// Reads subscriptions and AKS clusters from Azure Resource Manager. Read-only:
/// it never mutates anything in Azure.
struct AzureARMClient: Sendable {
    let http: any HTTPClient
    var baseURL: URL = AzureOAuthConfig.armBaseURL

    private static let subscriptionsAPIVersion = "2022-12-01"
    private static let aksAPIVersion = "2024-05-01"

    func subscriptions(accessToken: String) async throws -> [AzureSubscription] {
        let url =
            baseURL
            .appendingPathComponent("subscriptions")
            .appending(apiVersion: Self.subscriptionsAPIVersion)
        let list: ARMList<ARMSubscription> = try await get(url, accessToken: accessToken)
        return list.value.map {
            AzureSubscription(
                subscriptionID: $0.subscriptionId, displayName: $0.displayName, tenantID: $0.tenantId)
        }
    }

    func managedClusters(
        accessToken: String, subscriptionID: String, tenantID: String?
    ) async throws
        -> [AzureManagedCluster]
    {
        let url =
            baseURL
            .appendingPathComponent("subscriptions/\(subscriptionID)")
            .appendingPathComponent("providers/Microsoft.ContainerService/managedClusters")
            .appending(apiVersion: Self.aksAPIVersion)
        let list: ARMList<ARMManagedCluster> = try await get(url, accessToken: accessToken)
        return list.value.map { cluster in
            AzureManagedCluster(
                resourceID: cluster.id,
                name: cluster.name,
                resourceGroup: Self.resourceGroup(fromID: cluster.id) ?? "",
                location: cluster.location,
                kubernetesVersion: cluster.properties?.kubernetesVersion ?? "unknown",
                powerState: cluster.properties?.powerState?.code,
                subscriptionID: subscriptionID,
                tenantID: tenantID
            )
        }
    }

    /// api-versions to try for the credentials action, newest first, in case a
    /// tenant/region doesn't expose the action on the newest one.
    private static let credentialAPIVersions = ["2024-05-01", "2024-02-01", "2023-10-01", "2023-08-01"]

    /// Fetches the cluster's kubeconfig via `listClusterUserCredentials` (user
    /// credentials — respects RBAC; never admin). Returns the raw kubeconfig
    /// bytes (base64-decoded from the ARM response).
    func userKubeconfig(accessToken: String, cluster: KubeCore.AzureClusterRef) async throws -> Data {
        // Canonical casing: AKS returns IDs with lowercase `resourcegroups`, but
        // ARM's action dispatch wants `resourceGroups`.
        let base =
            baseURL.absoluteString
            + "/subscriptions/\(cluster.subscriptionID)"
            + "/resourceGroups/\(cluster.resourceGroup)"
            + "/providers/Microsoft.ContainerService/managedClusters/\(cluster.clusterName)"
            + "/listClusterUserCredentials"

        let auth = ["Authorization": "Bearer \(accessToken)", "Accept": "application/json"]
        var lastStatus = 0
        for version in Self.credentialAPIVersions {
            guard let url = URL(string: base + "?api-version=" + version) else { continue }
            // No request body: the action takes no parameters.
            let response = try await http.send(HTTPRequest(method: .post, url: url, headers: auth))
            if response.isSuccess {
                let result = try JSONDecoder().decode(ARMCredentialResults.self, from: response.body)
                guard let value = result.kubeconfigs.first?.value, let data = Data(base64Encoded: value)
                else {
                    throw AzureError.invalidCallback("no kubeconfig in listClusterUserCredentials response")
                }
                return data
            }
            lastStatus = response.status
            // 404 → try the next api-version; other errors won't improve.
            if response.status != 404 {
                throw AzureError.httpError(status: response.status, body: response.bodyText)
            }
        }
        // A 404 on the credentials action while the cluster resource itself is
        // readable almost always means the signed-in identity lacks the
        // "Azure Kubernetes Service Cluster User Role" (the
        // listClusterUserCredential/action permission). Point the user at the fix.
        throw AzureError.credentialsForbidden(
            "Azure returned 404 for listClusterUserCredentials on '\(cluster.clusterName)'. "
                + "Your account can read the cluster but can't fetch its credentials — this usually means it's "
                + "missing the 'Azure Kubernetes Service Cluster User Role'. Ask an admin to grant it, or run "
                + "`az aks get-credentials -g \(cluster.resourceGroup) -n \(cluster.clusterName)` and add the "
                + "cluster via Add Cluster → Kubeconfig file. (status \(lastStatus))")
    }

    private func get<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        let request = HTTPRequest(
            method: .get,
            url: url,
            headers: ["Authorization": "Bearer \(accessToken)", "Accept": "application/json"]
        )
        let response = try await http.send(request)
        guard response.isSuccess else {
            throw AzureError.httpError(
                status: response.status, body: "GET \(url.absoluteString) — \(response.bodyText)")
        }
        return try JSONDecoder().decode(T.self, from: response.body)
    }

    /// Extracts the resource group segment from an ARM resource ID
    /// (`…/resourceGroups/{rg}/…`), case-insensitively.
    static func resourceGroup(fromID id: String) -> String? {
        let parts = id.split(separator: "/")
        guard
            let index = parts.firstIndex(where: {
                $0.caseInsensitiveCompare("resourceGroups") == .orderedSame
            }),
            parts.indices.contains(index + 1)
        else { return nil }
        return String(parts[index + 1])
    }
}

// MARK: - ARM DTOs

private struct ARMList<Element: Decodable & Sendable>: Decodable, Sendable {
    let value: [Element]
}

private struct ARMSubscription: Decodable, Sendable {
    let subscriptionId: String
    let displayName: String
    let tenantId: String
}

private struct ARMCredentialResults: Decodable, Sendable {
    let kubeconfigs: [Entry]
    struct Entry: Decodable, Sendable {
        let name: String?
        let value: String
    }
}

private struct ARMManagedCluster: Decodable, Sendable {
    let id: String
    let name: String
    let location: String
    let properties: Properties?

    struct Properties: Decodable, Sendable {
        let kubernetesVersion: String?
        let powerState: PowerState?
        struct PowerState: Decodable, Sendable { let code: String? }
    }
}

extension URL {
    fileprivate func appending(apiVersion: String) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems =
            (components.queryItems ?? []) + [URLQueryItem(name: "api-version", value: apiVersion)]
        return components.url!
    }
}
