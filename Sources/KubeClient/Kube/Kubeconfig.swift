import Foundation
import Yams

/// A parsed kubeconfig, reduced to what Ergo needs to connect: the current
/// context's server URL + CA, and how to authenticate.
public struct Kubeconfig: Sendable, Equatable {
    public var server: URL
    /// PEM bytes of the cluster CA, if the config pins one.
    public var caPEM: Data?
    public var auth: Auth

    public enum Auth: Sendable, Equatable {
        /// A bearer token embedded directly in the config.
        case token(String)
        /// An Entra/`kubelogin` exec plugin — Ergo mints the token itself.
        /// `serverAppID` is the AKS AAD server app (`--server-id`).
        case azureExec(serverAppID: String?)
        /// Client-certificate auth — not supported yet.
        case clientCertificate
        case unknown
    }

    /// Parses the current context out of a kubeconfig's YAML bytes.
    public static func parse(_ data: Data) throws -> Kubeconfig {
        guard let text = String(data: data, encoding: .utf8),
            let root = try Yams.load(yaml: text) as? [String: Any]
        else {
            throw KubeconfigError.malformed("not valid YAML")
        }

        let contexts = root["contexts"] as? [[String: Any]] ?? []
        let clusters = root["clusters"] as? [[String: Any]] ?? []
        let users = root["users"] as? [[String: Any]] ?? []
        let currentName = root["current-context"] as? String

        let context = named(currentName, in: contexts) ?? contexts.first
        let ctx = context?["context"] as? [String: Any]
        let clusterName = ctx?["cluster"] as? String
        let userName = ctx?["user"] as? String

        guard let clusterEntry = named(clusterName, in: clusters) ?? clusters.first,
            let cluster = clusterEntry["cluster"] as? [String: Any],
            let serverString = cluster["server"] as? String,
            let server = URL(string: serverString)
        else {
            throw KubeconfigError.malformed("no cluster server")
        }

        var caPEM: Data?
        if let caData = cluster["certificate-authority-data"] as? String {
            caPEM = Data(base64Encoded: caData)
        }

        let userEntry = named(userName, in: users) ?? users.first
        let auth = Self.auth(from: userEntry?["user"] as? [String: Any] ?? [:])

        return Kubeconfig(server: server, caPEM: caPEM, auth: auth)
    }

    private static func auth(from user: [String: Any]) -> Auth {
        if let token = user["token"] as? String {
            return .token(token)
        }
        if user["client-certificate-data"] != nil || user["client-key-data"] != nil {
            return .clientCertificate
        }
        if let exec = user["exec"] as? [String: Any] {
            let args = exec["args"] as? [String] ?? []
            let command = (exec["command"] as? String) ?? ""
            let looksAzure =
                command.contains("kubelogin")
                || args.contains("azure")
                || args.contains { $0.contains("AzureCLI") || $0.contains("azure") }
            if looksAzure {
                return .azureExec(serverAppID: value(after: "--server-id", in: args))
            }
        }
        return .unknown
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    private static func named(_ name: String?, in list: [[String: Any]]) -> [String: Any]? {
        guard let name else { return nil }
        return list.first { ($0["name"] as? String) == name }
    }
}

public enum KubeconfigError: Error, Sendable, Equatable {
    case malformed(String)
    case unsupportedAuth(String)
}
