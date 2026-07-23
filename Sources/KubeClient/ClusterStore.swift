import Foundation
import KubeCore

/// Persists the user's saved cluster connections. A boundary so the UI and
/// tests don't care whether storage is a file, memory, or something else later.
/// Holds only connection *metadata* — never secrets (those go to the Keychain).
public protocol ClusterStore: Sendable {
    func load() async throws -> [ClusterConnection]
    func save(_ connections: [ClusterConnection]) async throws
}

/// In-memory store for tests and previews. An actor so concurrent access is
/// safe under strict concurrency.
public actor InMemoryClusterStore: ClusterStore {
    private var connections: [ClusterConnection]

    public init(_ connections: [ClusterConnection] = []) {
        self.connections = connections
    }

    public func load() async throws -> [ClusterConnection] { connections }

    public func save(_ connections: [ClusterConnection]) async throws {
        self.connections = connections
    }
}

/// On-device JSON store. Writes connection metadata to a file under Application
/// Support (the default) — nothing leaves this Mac.
public struct FileClusterStore: ClusterStore {
    private let url: URL

    /// - Parameter url: where the JSON lives. Defaults to
    ///   `~/Library/Application Support/Ergo/clusters.json`.
    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.url = base.appendingPathComponent("Ergo/clusters.json")
        }
    }

    public func load() async throws -> [ClusterConnection] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.iso8601.decode([ClusterConnection].self, from: data)
    }

    public func save(_ connections: [ClusterConnection]) async throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.iso8601Pretty.encode(connections)
        try data.write(to: url, options: .atomic)
    }
}

extension JSONDecoder {
    /// Shared decoder for on-disk / fixture JSON using RFC 3339 timestamps.
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var iso8601Pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
