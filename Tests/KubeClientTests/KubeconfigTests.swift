import Foundation
import Testing

@testable import KubeClient

@Suite("Kubeconfig parsing")
struct KubeconfigTests {
    @Test("Parses server, CA, and an embedded token")
    func tokenConfig() throws {
        let ca = Data("-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----".utf8)
            .base64EncodedString()
        let yaml = """
            apiVersion: v1
            kind: Config
            current-context: ctx
            clusters:
            - name: c1
              cluster:
                server: https://api.example.com:443
                certificate-authority-data: \(ca)
            contexts:
            - name: ctx
              context:
                cluster: c1
                user: u1
            users:
            - name: u1
              user:
                token: abc123
            """
        let config = try Kubeconfig.parse(Data(yaml.utf8))
        #expect(config.server.absoluteString == "https://api.example.com:443")
        #expect(config.caPEM != nil)
        #expect(config.auth == .token("abc123"))
    }

    @Test("Detects an Entra/kubelogin exec plugin and its server-id")
    func azureExecConfig() throws {
        let yaml = """
            apiVersion: v1
            kind: Config
            current-context: aks
            clusters:
            - name: aks
              cluster:
                server: https://aks-abc.hcp.eastus.azmk8s.io:443
            contexts:
            - name: aks
              context:
                cluster: aks
                user: aks-user
            users:
            - name: aks-user
              user:
                exec:
                  apiVersion: client.authentication.k8s.io/v1beta1
                  command: kubelogin
                  args:
                  - get-token
                  - --server-id
                  - 6dae42f8-4368-4678-94ff-3960e28e3630
                  - --login
                  - azurecli
            """
        let config = try Kubeconfig.parse(Data(yaml.utf8))
        #expect(config.auth == .azureExec(serverAppID: "6dae42f8-4368-4678-94ff-3960e28e3630"))
    }

    @Test("Flags client-certificate auth as its own case")
    func clientCertConfig() throws {
        let yaml = """
            apiVersion: v1
            current-context: ctx
            clusters:
            - name: c1
              cluster: { server: https://api.example.com }
            contexts:
            - name: ctx
              context: { cluster: c1, user: u1 }
            users:
            - name: u1
              user: { client-certificate-data: Zm9v, client-key-data: YmFy }
            """
        let config = try Kubeconfig.parse(Data(yaml.utf8))
        #expect(config.auth == .clientCertificate)
    }

    @Test("Malformed YAML throws")
    func malformed() {
        #expect(throws: KubeconfigError.self) {
            _ = try Kubeconfig.parse(Data("- just: a list".utf8))
        }
    }

    private let multiContext = """
        apiVersion: v1
        kind: Config
        current-context: prod
        clusters:
        - name: prod-cluster
          cluster: { server: https://prod.example.com:443 }
        - name: dev-cluster
          cluster: { server: https://dev.example.com:443 }
        contexts:
        - name: prod
          context: { cluster: prod-cluster, user: prod-user }
        - name: dev
          context: { cluster: dev-cluster, user: dev-user }
        users:
        - name: prod-user
          user: { token: prod-token }
        - name: dev-user
          user: { token: dev-token }
        """

    @Test("Lists every context with its server")
    func listsContexts() throws {
        let contexts = try Kubeconfig.contexts(from: Data(multiContext.utf8))
        #expect(contexts.map(\.name) == ["prod", "dev"])
        #expect(contexts.first { $0.name == "dev" }?.server == "https://dev.example.com:443")
    }

    @Test("Parses a named context, not just current-context")
    func parsesNamedContext() throws {
        let dev = try Kubeconfig.parse(Data(multiContext.utf8), context: "dev")
        #expect(dev.server.absoluteString == "https://dev.example.com:443")
        #expect(dev.auth == .token("dev-token"))

        // Defaulting to current-context resolves prod.
        let current = try Kubeconfig.parse(Data(multiContext.utf8))
        #expect(current.auth == .token("prod-token"))
    }
}
