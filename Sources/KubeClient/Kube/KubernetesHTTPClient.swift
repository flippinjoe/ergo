import Foundation
import Security

/// An `HTTPClient` that trusts a specific cluster CA (Kubernetes API servers use
/// a private CA that the system store doesn't know). Server trust is evaluated
/// against the CA from the kubeconfig; nothing else about the connection is
/// weakened.
///
/// `@unchecked Sendable`: the CA anchors are immutable after init and the
/// URLSession delegate is stateless.
public final class KubernetesHTTPClient: NSObject, HTTPClient, StreamingHTTPClient, URLSessionDelegate,
    @unchecked Sendable
{
    private let anchors: [SecCertificate]
    private lazy var session: URLSession = URLSession(
        configuration: .ephemeral, delegate: self, delegateQueue: nil)

    /// - Parameter caPEM: PEM bytes of the cluster CA (may contain a bundle).
    ///   If nil/unparseable, falls back to the system trust store.
    public init(caPEM: Data?) {
        self.anchors = caPEM.map(Self.certificates(fromPEM:)) ?? []
        super.init()
    }

    private func urlRequest(from request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        return urlRequest
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: urlRequest(from: request))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(status: status, body: data)
    }

    /// Streams a long-lived response line by line (for `follow=true` logs). The
    /// underlying URLSession task is cancelled when the stream is terminated.
    public func streamLines(_ request: HTTPRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: urlRequest(from: request))
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw KubernetesError.api(status: http.statusCode, body: "log stream failed")
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
