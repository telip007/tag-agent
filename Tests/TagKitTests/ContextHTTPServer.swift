import Foundation
import Network
import Synchronization

/// Loopback-only HTTP fixture exercising URLSession's real streaming/redirect behavior.
final class ContextHTTPServer: Sendable {
    private final class State: Sendable {
        let connections = Mutex<[NWConnection]>([])
        let requests = Mutex<[String]>([])
    }
    private let listener: NWListener
    private let state = State()

    init(response: @escaping @Sendable (String) -> Data?) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let state = state
        listener.newConnectionHandler = { connection in
            state.connections.withLock { $0.append(connection) }
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                state.requests.withLock { $0.append(request) }
                guard let bytes = response(request) else { return }
                connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    var requests: [String] { state.requests.withLock { $0 } }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: DispatchQueue(label: "tag.context-http-tests"))
        }
        guard let port = listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/") else {
            throw URLError(.cannotConnectToHost)
        }
        return url
    }

    deinit {
        listener.cancel()
        state.connections.withLock { connections in
            for connection in connections { connection.cancel() }
        }
    }

    static func reply(
        _ body: String, status: Int = 200, type: String = "text/plain; charset=utf-8", headers: String = "",
        declaringLength: Bool = true
    ) -> Data {
        let length = declaringLength ? "Content-Length: \(body.utf8.count)\r\n" : ""
        return Data(
            "HTTP/1.1 \(status) Result\r\nContent-Type: \(type)\r\n\(length)\(headers)Connection: close\r\n\r\n\(body)"
                .utf8)
    }
}
