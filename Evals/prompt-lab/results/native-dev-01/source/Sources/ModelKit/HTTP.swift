public import Foundation

/// Sends HTTP requests: the seam between the adapters and the network, so
/// tests can answer requests without one.
public protocol HTTPTransport: Sendable {
    /// Sends `request` and returns the whole body.
    ///
    /// - Throws: Transport errors; HTTP errors come back as a status.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// Sends `request` and returns the body line by line as it arrives,
    /// empty lines included (server-sent events separate events with them).
    ///
    /// - Throws: Transport errors; HTTP errors come back as a status.
    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, any Error>)
}

/// The ``HTTPTransport`` that goes over the network with `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// Creates a transport.
    ///
    /// - Parameter session: The session to send with.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Sends `request` and returns the whole body.
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }

    /// Sends `request` and streams the body's lines.
    public func lines(
        for request: URLRequest
    ) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, any Error>) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let lines = AsyncThrowingStream<String, any Error> { continuation in
            let task = Task {
                do {
                    var splitter = LineSplitter()
                    for try await byte in bytes {
                        if let line = splitter.add(byte) {
                            continuation.yield(line)
                        }
                    }
                    if let last = splitter.finish() {
                        continuation.yield(last)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (response, lines)
    }
}

/// Splits bytes into UTF-8 lines at `\n`, dropping a `\r` before it and
/// keeping empty lines, unlike `AsyncBytes.lines`.
struct LineSplitter {
    private var buffer: [UInt8] = []

    /// Adds a byte; returns a line when `byte` ends one.
    mutating func add(_ byte: UInt8) -> String? {
        guard byte == UInt8(ascii: "\n") else {
            buffer.append(byte)
            return nil
        }
        if buffer.last == UInt8(ascii: "\r") {
            buffer.removeLast()
        }
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(bytes: buffer, encoding: .utf8) ?? ""
    }

    /// The last line, when the body didn't end with a newline.
    mutating func finish() -> String? {
        guard !buffer.isEmpty else {
            return nil
        }
        defer { buffer = [] }
        return String(bytes: buffer, encoding: .utf8) ?? ""
    }
}

/// One server-sent event: its `event:` name, if any, and its `data:` lines
/// joined with newlines.
public struct ServerSentEvent: Sendable, Equatable {
    /// The event's name, or `nil` for the default `message` event.
    public var event: String?
    /// The event's data.
    public var data: String

    /// Creates an event.
    ///
    /// - Parameters:
    ///   - event: The event's name.
    ///   - data: The event's data.
    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }
}

/// Parses server-sent events line by line.
public struct ServerSentEventParser: Sendable {
    private var event: String?
    private var data: [String] = []

    /// Creates a parser.
    public init() {}

    /// Feeds one line; returns an event when `line` completes one.
    public mutating func feed(_ line: String) -> ServerSentEvent? {
        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil
        }
        let (field, value) = Self.split(line)
        switch field {
        case "event": event = value
        case "data": data.append(value)
        default: break
        }
        return nil
    }

    /// The event still open when the stream ended, if any.
    public mutating func finish() -> ServerSentEvent? {
        dispatch()
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            event = nil
            data = []
        }
        guard !data.isEmpty else {
            return nil
        }
        return ServerSentEvent(event: event, data: data.joined(separator: "\n"))
    }

    private static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else {
            return (line, "")
        }
        var value = line[line.index(after: colon)...]
        if value.first == " " {
            value = value.dropFirst()
        }
        return (String(line[..<colon]), String(value))
    }
}

extension HTTPTransport {
    /// Sends `request` and yields its server-sent events. A non-2xx status
    /// throws through `failure` with the body collected.
    ///
    /// - Parameters:
    ///   - request: The request to send.
    ///   - failure: Turns an HTTP status and body into the error to throw.
    /// - Returns: The events, in order.
    /// - Throws: Transport errors, or `failure`'s error for a non-2xx status.
    public func events(
        for request: URLRequest,
        failure: @escaping @Sendable (Int, String) -> any Error,
    ) async throws -> AsyncThrowingStream<ServerSentEvent, any Error> {
        let (response, lines) = try await lines(for: request)
        guard (200..<300).contains(response.statusCode) else {
            var body = ""
            for try await line in lines {
                body += line + "\n"
            }
            throw failure(response.statusCode, body)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = ServerSentEventParser()
                    for try await line in lines {
                        if let event = parser.feed(line) {
                            continuation.yield(event)
                        }
                    }
                    if let event = parser.finish() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// The `User-Agent` Tag Agent sends, its own name rather than a library's
/// (OpenCode Go asks clients to identify themselves).
public enum TagUserAgent {
    /// `tag-agent/<version>`.
    public static let value = "tag-agent/0.1"
}
