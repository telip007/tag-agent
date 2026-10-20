import Foundation
import Network
import Synchronization

/// The start of an HTTP request the loopback server received.
struct LoopbackRequest: Sendable, Equatable {
    /// The method, e.g. `GET`.
    var method: String
    /// The request target: path and query, e.g. `/auth/callback?code=…`.
    var target: String

    /// The target's path.
    var path: String {
        URLComponents(string: target)?.path ?? target
    }

    /// The target's query parameters by name; the first of repeated names wins.
    var query: [String: String] {
        var query: [String: String] = [:]
        for item in URLComponents(string: target)?.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        return query
    }

    /// Parses the request line of a request head, once `data` holds the
    /// whole head (up to the blank line). `nil` while it is incomplete or
    /// when it isn't HTTP.
    static func parse(_ data: Data) -> Self? {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)),
            let head = String(data: data[..<end.lowerBound], encoding: .utf8),
            let line = head.split(separator: "\r\n", omittingEmptySubsequences: false).first
        else {
            return nil
        }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/") else {
            return nil
        }
        return Self(method: String(parts[0]), target: String(parts[1]))
    }
}

/// A received request and the way to answer it.
struct LoopbackExchange: Sendable {
    /// What the browser asked for.
    var request: LoopbackRequest
    /// Sends an HTML page with a status and closes the connection.
    var respond: @Sendable (_ status: Int, _ html: String) -> Void
}

/// A tiny HTTP server on `127.0.0.1` that receives the OAuth redirect. It
/// only reads request heads, answers each request once and closes the
/// connection.
final class LoopbackServer: Sendable {
    /// The port it listens on.
    let port: UInt16
    /// The requests, in arrival order; finishes when the server stops.
    let requests: AsyncStream<LoopbackExchange>

    private let listener: NWListener
    private let continuation: AsyncStream<LoopbackExchange>.Continuation
    private let connections = Mutex<[ObjectIdentifier: NWConnection]>([:])
    private static let queue = DispatchQueue(label: "tag.loopback-server")
    private static let maximumHeadLength = 16_384

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
        (requests, continuation) = AsyncStream.makeStream()
    }

    deinit {
        stop()
    }

    /// Starts listening on `127.0.0.1`.
    ///
    /// - Parameter port: The port, or `0` for any free one.
    /// - Returns: The running server.
    /// - Throws: ``ChatGPTSignInError/callbackPortInUse(_:)`` when the port
    ///   is taken, or the listener's error.
    static func start(port: UInt16) async throws -> LoopbackServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        let listener = try NWListener(using: parameters)
        let ready = try await waitUntilReady(listener, port: port)
        let server = LoopbackServer(listener: listener, port: ready)
        listener.newConnectionHandler = { [weak server] connection in
            server?.accept(connection)
        }
        return server
    }

    /// Stops listening, closes every open connection (browsers keep spare
    /// ones that a later sign-in's redirect could otherwise land on) and
    /// finishes ``requests``.
    func stop() {
        listener.cancel()
        let open = connections.withLock { connections in
            defer { connections.removeAll() }
            return Array(connections.values)
        }
        for connection in open {
            connection.cancel()
        }
        continuation.finish()
    }

    private static func waitUntilReady(_ listener: NWListener, port: UInt16) async throws -> UInt16 {
        let resumed = Mutex(false)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, any Error>) in
            let finish: @Sendable (Result<UInt16, any Error>) -> Void = { result in
                let first = resumed.withLock { resumed in
                    defer { resumed = true }
                    return !resumed
                }
                if first {
                    continuation.resume(with: result)
                }
            }
            listener.newConnectionHandler = { $0.cancel() }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.success(listener.port?.rawValue ?? port))
                case .failed(let error), .waiting(let error):
                    listener.cancel()
                    finish(.failure(Self.startError(error, port: port)))
                case .cancelled:
                    finish(.failure(CancellationError()))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private static func startError(_ error: NWError, port: UInt16) -> any Error {
        if case .posix(let code) = error, code == .EADDRINUSE {
            return ChatGPTSignInError.callbackPortInUse(Int(port))
        }
        return error
    }

    private func accept(_ connection: NWConnection) {
        connections.withLock { $0[ObjectIdentifier(connection)] = connection }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.forget(connection)
            default:
                break
            }
        }
        connection.start(queue: Self.queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumHeadLength) {
            [weak self] content, _, isComplete, error in
            guard let self else {
                return
            }
            let buffer = buffer + (content ?? Data())
            if let request = LoopbackRequest.parse(buffer) {
                continuation.yield(
                    LoopbackExchange(request: request) { [weak self] status, html in
                        // Answered connections close themselves once sent, so stop() leaves them be.
                        self?.forget(connection)
                        Self.send(status: status, html: html, on: connection)
                    })
            } else if error != nil || isComplete || buffer.count > Self.maximumHeadLength {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private func forget(_ connection: NWConnection) {
        connections.withLock { _ = $0.removeValue(forKey: ObjectIdentifier(connection)) }
    }

    private static func send(status: Int, html: String, on connection: NWConnection) {
        let body = Data(html.utf8)
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        let head =
            "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        connection.send(
            content: Data(head.utf8) + body,
            completion: .contentProcessed { _ in connection.cancel() })
    }
}
