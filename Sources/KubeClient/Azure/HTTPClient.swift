import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The network boundary. Token and ARM clients depend on this, not on
/// `URLSession`, so tests inject canned responses and never hit the network.
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public struct HTTPRequest: Sendable {
    public enum Method: String, Sendable { case get = "GET", post = "POST" }

    public var method: Method
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: Method, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data
    public var headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
    public var bodyText: String { String(decoding: body, as: UTF8.self) }
}

/// The real client, backed by `URLSession`.
///
/// It preserves the HTTP method and body across redirects. URLSession's default
/// is to downgrade POST→GET on 301/302/303, which breaks ARM action endpoints
/// like `listClusterUserCredentials` (POST-only) — a redirected GET there
/// returns a plain-text 404. We keep the original method/body/headers on
/// same-host redirects.
public final class URLSessionHTTPClient: NSObject, HTTPClient, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    public override init() { super.init() }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: urlRequest)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(status: http?.statusCode ?? 0, body: data, headers: headers)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let original = task.originalRequest else {
            completionHandler(request)
            return
        }
        // Restore the original method + body across the redirect. URLSession
        // downgrades POST→GET on 302/303, and ARM redirects action POSTs to a
        // regional endpoint — a downgraded GET there returns a plain-text 404.
        var preserved = request
        preserved.httpMethod = original.httpMethod
        preserved.httpBody = original.httpBody
        for (key, value) in original.allHTTPHeaderFields ?? [:] {
            if preserved.value(forHTTPHeaderField: key) == nil {
                preserved.setValue(value, forHTTPHeaderField: key)
            }
        }
        completionHandler(preserved)
    }
}
