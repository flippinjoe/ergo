import Foundation
import KubeCore
import Security

/// A persisted token bundle. Held only in secure storage (Keychain), never in a
/// `ClusterConnection` or on disk in the clear.
public struct StoredToken: Sendable, Codable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var account: AzureAccount

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, account: AzureAccount) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.account = account
    }

    /// True when the access token is at/near expiry (default 60s leeway).
    public func isExpired(now: Date, leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// Secure storage for the signed-in token bundle. A boundary so tests use memory
/// and the app uses the Keychain.
public protocol TokenStore: Sendable {
    func load() async throws -> StoredToken?
    func save(_ token: StoredToken) async throws
    func clear() async throws
}

/// In-memory token store for tests/previews.
public actor InMemoryTokenStore: TokenStore {
    private var token: StoredToken?

    public init(_ token: StoredToken? = nil) { self.token = token }

    public func load() async throws -> StoredToken? { token }
    public func save(_ token: StoredToken) async throws { self.token = token }
    public func clear() async throws { token = nil }
}

/// Keychain-backed token store. In a sandboxed app the item lives in the app's
/// own keychain — nothing leaves this Mac.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.ergo.Ergo.azure", account: String = "default") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() async throws -> StoredToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AzureError.keychain(status)
        }
        return try JSONDecoder().decode(StoredToken.self, from: data)
    }

    public func save(_ token: StoredToken) async throws {
        let data = try JSONEncoder().encode(token)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AzureError.keychain(addStatus) }
            return
        }
        throw AzureError.keychain(updateStatus)
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AzureError.keychain(status)
        }
    }
}
