import Foundation
import Yams

/// A parsed kubeconfig context, reduced to what Ergo needs to connect: the
/// server URL + CA, and how to authenticate.
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

    /// A selectable context in a kubeconfig (for the picker).
    public struct Context: Sendable, Equatable, Identifiable {
        public var name: String
        public var server: String
        public var id: String { name }
    }

    /// Lists every context in a kubeconfig, so the user can choose which to add.
    public static func contexts(from data: Data) throws -> [Context] {
        let root = try parseRoot(data)
        let clusters = root["clusters"] as? [[String: Any]] ?? []
        return (root["contexts"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let name = entry["name"] as? String else { return nil }
            let ctx = entry["context"] as? [String: Any]
            let clusterName = ctx?["cluster"] as? String
            let server =
                (named(clusterName, in: clusters)?["cluster"] as? [String: Any])?["server"] as? String
            return Context(name: name, server: server ?? "")
        }
    }

    /// Parses a specific context (by name), or the `current-context` when `name`
    /// is nil.
    public static func parse(_ data: Data, context name: String? = nil) throws -> Kubeconfig {
        let root = try parseRoot(data)
        let contexts = root["contexts"] as? [[String: Any]] ?? []
        let clusters = root["clusters"] as? [[String: Any]] ?? []
        let users = root["users"] as? [[String: Any]] ?? []

        let wanted = name ?? (root["current-context"] as? String)
        let context = named(wanted, in: contexts) ?? contexts.first
        let ctx = context?["context"] as? [String: Any]

        guard let clusterEntry = named(ctx?["cluster"] as? String, in: clusters) ?? clusters.first,
            let cluster = clusterEntry["cluster"] as? [String: Any],
            let serverString = cluster["server"] as? String,
            let server = URL(string: serverString)
        else {
            throw KubeconfigError.malformed("no cluster server for context \(wanted ?? "?")")
        }

        var caPEM: Data?
        if let caData = cluster["certificate-authority-data"] as? String {
            caPEM = Data(base64Encoded: caData)
        }

        let userEntry = named(ctx?["user"] as? String, in: users) ?? users.first
        let auth = Self.auth(from: userEntry?["user"] as? [String: Any] ?? [:])

        return Kubeconfig(server: server, caPEM: caPEM, auth: auth)
    }

    private static func parseRoot(_ data: Data) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8),
            let root = try Yams.load(yaml: text) as? [String: Any]
        else {
            throw KubeconfigError.malformed("not valid YAML")
        }
        return root
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
