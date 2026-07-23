import AppKit
import Foundation
import KubeClient
import Network

/// The real interactive sign-in: open the system browser at Microsoft's login
/// page and catch the redirect on a loopback HTTP listener — the same technique
/// `az login` uses. Works with the well-known public client (which registers
/// `http://localhost`), so no app registration is needed.
///
/// Requires the `com.apple.security.network.server` sandbox entitlement to
/// accept the loopback connection.
struct SystemWebAuthenticator: WebAuthenticator {
    func authenticate(redirectURIBuilder: @escaping @Sendable (URL) -> URL) async throws -> AuthCallback {
        let coordinator = LoopbackAuthCoordinator(redirectURIBuilder: redirectURIBuilder)
        return try await withTaskCancellationHandler {
            try await coordinator.run()
        } onCancel: {
            coordinator.cancel()
        }
    }
}

/// Bridges the Network.framework callback API to async/await. `@unchecked
/// Sendable` because it guards all mutable state with a lock and resumes its
/// continuation exactly once.
private final class LoopbackAuthCoordinator: @unchecked Sendable {
    private let redirectURIBuilder: @Sendable (URL) -> URL
    private let lock = NSLock()
    private var listener: NWListener?
    private var continuation: CheckedContinuation<AuthCallback, Error>?
    private var redirectURI: URL?
    private var finished = false

    init(redirectURIBuilder: @escaping @Sendable (URL) -> URL) {
        self.redirectURIBuilder = redirectURIBuilder
    }

    func run() async throws -> AuthCallback {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                let listener = try NWListener(using: .tcp)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handleState(state, listener: listener)
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: .global())
            } catch {
                finish(.failure(error))
            }
        }
    }

    func cancel() {
        finish(.failure(AzureError.cancelled))
    }

    private func handleState(_ state: NWListener.State, listener: NWListener) {
        switch state {
        case .ready:
            guard let port = listener.port?.rawValue,
                let redirect = URL(string: "http://localhost:\(port)/")
            else {
                finish(.failure(AzureError.invalidCallback("could not bind loopback port")))
                return
            }
            lock.lock()
            redirectURI = redirect
            lock.unlock()
            let authorizeURL = redirectURIBuilder(redirect)
            DispatchQueue.main.async { NSWorkspace.shared.open(authorizeURL) }
        case .failed(let error):
            finish(.failure(error))
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data, let path = Self.requestPath(from: data) else {
                connection.cancel()
                return
            }
            self.lock.lock()
            let port = self.redirectURI?.port ?? 0
            let redirect = self.redirectURI
            self.lock.unlock()

            guard path.contains("code=") || path.contains("error=") else {
                // Ignore stray requests (e.g. favicon); keep waiting.
                Self.respond(connection, body: "Waiting for Microsoft…")
                return
            }
            Self.respond(connection, body: "Signed in to Azure. You can return to Ergo.")

            if let redirect, let callbackURL = URL(string: "http://localhost:\(port)\(path)") {
                self.finish(.success(AuthCallback(callbackURL: callbackURL, redirectURI: redirect)))
            } else {
                self.finish(.failure(AzureError.invalidCallback("malformed loopback callback")))
            }
        }
    }

    /// Parses the request-target from the first line: `GET /?code=… HTTP/1.1`.
    private static func requestPath(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8),
            let firstLine = text.split(separator: "\r\n", maxSplits: 1).first
        else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    private static func respond(_ connection: NWConnection, body: String) {
        let html =
            "<html><body style=\"font-family:-apple-system;padding:3rem\"><h2>\(body)</h2></body></html>"
        let response =
            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(
            content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finish(_ result: Result<AuthCallback, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let listener = self.listener
        self.listener = nil
        lock.unlock()

        listener?.cancel()
        continuation?.resume(with: result)
    }
}
