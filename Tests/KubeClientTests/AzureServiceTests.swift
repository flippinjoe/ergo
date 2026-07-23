import Foundation
import KubeCore
import Testing

@testable import KubeClient

@Suite("Azure discovery (mock)")
struct AzureServiceTests {
    let service = FakeAzureClusterService()

    @Test("Sign-in returns the account identity")
    func signIn() async throws {
        let account = try await service.signIn()
        #expect(account.username == "dev@contoso.com")
    }

    @Test("Subscriptions decode from fixtures")
    func subscriptions() async throws {
        let subs = try await service.listSubscriptions()
        #expect(subs.count == 2)
        #expect(subs.contains { $0.displayName == "Contoso Production" })
    }

    @Test("Clusters are scoped to their subscription")
    func clustersScopedToSubscription() async throws {
        let prod = try await service.listClusters(inSubscription: "11111111-1111-1111-1111-111111111111")
        #expect(prod.count == 2)
        #expect(prod.allSatisfy { $0.subscriptionID == "11111111-1111-1111-1111-111111111111" })

        let sandbox = try await service.listClusters(inSubscription: "22222222-2222-2222-2222-222222222222")
        #expect(sandbox.count == 1)
        let stopped = try #require(sandbox.first)
        #expect(stopped.health == .warning)  // powerState "Stopped"
    }

    @Test("A discovered cluster converts to a persistable connection")
    func clusterToConnection() async throws {
        let clusters = try await service.listClusters(inSubscription: "11111111-1111-1111-1111-111111111111")
        let cluster = try #require(clusters.first { $0.name == "prod-eus" })
        let now = Date(timeIntervalSince1970: 1_000_000_000)

        let connection = cluster.connection(addedAt: now)
        #expect(connection.displayName == "prod-eus")
        #expect(connection.contextName == "prod-eus")
        guard case .azure(let ref) = connection.source else {
            Issue.record("expected an azure source")
            return
        }
        #expect(ref.resourceGroup == "prod-eastus")
        #expect(ref.clusterName == "prod-eus")
    }

}
