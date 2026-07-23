import CryptoKit
import Foundation
import Security

/// PKCE (RFC 7636) pair for the authorization-code flow: a random `verifier`
/// and its S256 `challenge`. Public clients must use this so an intercepted
/// authorization code is useless without the verifier.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String
    public let method = "S256"

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.challenge(for: verifier)
    }

    /// The S256 challenge for a verifier: base64url(SHA256(verifier)).
    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    /// A fresh pair with a cryptographically random verifier.
    public static func generate(byteCount: Int = 32) -> PKCE {
        PKCE(verifier: randomBase64URL(byteCount: byteCount))
    }
}

/// A random base64url string of `byteCount` bytes — used for PKCE verifiers and
/// OAuth `state`.
func randomBase64URL(byteCount: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
    return Data(bytes).base64URLEncodedString()
}

extension Data {
    /// base64url without padding (RFC 4648 §5), as OAuth/PKCE require.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes base64url (padding optional), for reading JWT segments.
    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        self.init(base64Encoded: s)
    }
}
