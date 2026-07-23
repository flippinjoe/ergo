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

    /// Fetches the cluster's kubeconfig via `listClusterUserCredentials`
    /// (user credentials — respects RBAC; never admin). Returns the raw
    /// kubeconfig bytes (base64-decoded from the ARM response).
    func userKubeconfig(accessToken: String, cluster: KubeCore.AzureClusterRef) async throws -> Data {
        // resourceID already begins with "/subscriptions/…"; concatenate rather
        // than appendingPathComponent, which would escape its slashes.
        guard
            let url = URL(
                string: baseURL.absoluteString + cluster.resourceID
                    + "/listClusterUserCredentials?api-version=" + Self.aksAPIVersion)
        else {
            throw AzureError.invalidCallback("bad cluster resource ID")
        }
        let request = HTTPRequest(
            method: .post,
            url: url,
            headers: ["Authorization": "Bearer \(accessToken)", "Accept": "application/json"],
            body: Data("{}".utf8)
        )
        let response = try await http.send(request)
        guard response.isSuccess else {
            throw AzureError.httpError(status: response.status, body: response.bodyText)
        }
        let result = try JSONDecoder().decode(ARMCredentialResults.self, from: response.body)
        guard let value = result.kubeconfigs.first?.value, let data = Data(base64Encoded: value) else {
            throw AzureError.invalidCallback("no kubeconfig in listClusterUserCredentials response")
        }
        return data
    }

    private func get<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        let request = HTTPRequest(
            method: .get,
            url: url,
            headers: ["Authorization": "Bearer \(accessToken)", "Accept": "application/json"]
        )
        let response = try await http.send(request)
        guard response.isSuccess else {
            throw AzureError.httpError(status: response.status, body: response.bodyText)
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
