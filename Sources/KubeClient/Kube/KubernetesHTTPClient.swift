import Foundation
import Security

/// An `HTTPClient` that trusts a specific cluster CA (Kubernetes API servers use
/// a private CA that the system store doesn't know). Server trust is evaluated
/// against the CA from the kubeconfig; nothing else about the connection is
/// weakened.
///
/// `@unchecked Sendable`: the CA anchors are immutable after init and the
/// URLSession delegate is stateless.
public final class KubernetesHTTPClient: NSObject, HTTPClient, URLSessionDelegate, @unchecked Sendable {
    private let anchors: [SecCertificate]
    private lazy var session: URLSession = URLSession(
        configuration: .ephemeral, delegate: self, delegateQueue: nil)

    /// - Parameter caPEM: PEM bytes of the cluster CA (may contain a bundle).
    ///   If nil/unparseable, falls back to the system trust store.
    public init(caPEM: Data?) {
        self.anchors = caPEM.map(Self.certificates(fromPEM:)) ?? []
        super.init()
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(status: status, body: data)
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if !anchors.isEmpty {
            SecTrustSetAnchorCertificates(trust, anchors as CFArray)
            // Trust ONLY the cluster CA, not the system store.
            SecTrustSetAnchorCertificatesOnly(trust, true)
        }
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Splits a PEM bundle into `SecCertificate`s.
    static func certificates(fromPEM pem: Data) -> [SecCertificate] {
        guard let text = String(data: pem, encoding: .utf8) else { return [] }
        let marker = "-----BEGIN CERTIFICATE-----"
        return text.components(separatedBy: marker)
            .dropFirst()
            .compactMap { block in
                let base64 =
                    block
                    .components(separatedBy: "-----END CERTIFICATE-----").first?
                    .components(separatedBy: .whitespacesAndNewlines).joined() ?? ""
                guard let der = Data(base64Encoded: base64) else { return nil }
                return SecCertificateCreateWithData(nil, der as CFData)
            }
    }
}
