import Foundation
import OpenRouter

/// Turns one wire format's server-sent events into reply deltas and, at the
/// end, the whole reply.
protocol WireDecoder {
    /// Creates a decoder for a reply from `provider`, which errors name.
    init(provider: ProviderID)

    /// Decodes one event.
    ///
    /// - Returns: What the event adds to the reply, in order.
    /// - Throws: A ``ProviderError`` when the event reports an error.
    mutating func decode(_ event: ServerSentEvent) throws -> [ReplyDelta]

    /// The reply assembled from every event so far.
    ///
    /// - Throws: ``ProviderError/malformedResponse(_:detail:)`` when the
    ///   stream ended without a reply.
    func reply() throws -> ModelReply

    /// The error for a request that failed before the stream opened.
    ///
    /// - Parameters:
    ///   - status: The HTTP status.
    ///   - body: The response body.
    ///   - provider: The provider that answered.
    /// - Returns: The error to throw.
    static func error(status: Int, body: String, provider: ProviderID) -> ProviderError
}

extension WireDecoder {
    /// The shared mapping: ``ProviderError/from(status:body:provider:)``.
    static func error(status: Int, body: String, provider: ProviderID) -> ProviderError {
        ProviderError.from(status: status, body: body, provider: provider)
    }
}

/// Runs an adapter's request away from the caller's actor. The agent runs on
/// the main actor with the UI, and encoding a long conversation or decoding
/// every event there would hold up typing; only the deltas come back.
enum WireStream {
    private enum Piece: Sendable {
        case delta(ReplyDelta)
        case reply(ModelReply)
    }

    /// Posts the body `makeBody` builds to `endpoint` and decodes the
    /// streamed reply with a `Decoder`, all in a detached task.
    ///
    /// - Parameters:
    ///   - makeBody: Builds the request body; runs in the detached task.
    ///   - endpoint: Where the request goes.
    ///   - decoder: The wire format's decoder type.
    ///   - onDelta: Receives the reply piece by piece, on the caller's actor.
    /// - Returns: The complete reply.
    /// - Throws: A ``ProviderError`` or a transport error.
    static func send<Decoder: WireDecoder>(
        _ makeBody: @escaping @Sendable () throws -> JSONValue,
        to endpoint: WireEndpoint,
        decoder: Decoder.Type,
        onDelta: (ReplyDelta) -> Void,
    ) async throws -> ModelReply {
        try await run(onDelta: onDelta) { emit in
            let request = try await endpoint.request(body: try makeBody().encoded())
            let provider = endpoint.provider
            let events = try await endpoint.transport.events(for: request) { status, body in
                Decoder.error(status: status, body: body, provider: provider)
            }
            var decoder = Decoder(provider: provider)
            for try await event in events {
                for delta in try decoder.decode(event) {
                    emit(delta)
                }
            }
            return try decoder.reply()
        }
    }

    /// Runs `work` in a detached task, relaying the deltas it emits to
    /// `onDelta` on the caller's actor.
    ///
    /// - Parameters:
    ///   - onDelta: Receives the deltas.
    ///   - work: Produces the reply, emitting deltas as it goes.
    /// - Returns: What `work` returned.
    /// - Throws: What `work` threw, or `CancellationError` when cancelled.
    static func run(
        onDelta: (ReplyDelta) -> Void,
        work: @escaping @Sendable (_ emit: @escaping @Sendable (ReplyDelta) -> Void) async throws -> ModelReply,
    ) async throws -> ModelReply {
        let pieces = AsyncThrowingStream<Piece, any Error> { continuation in
            let task = Task.detached {
                do {
                    let reply = try await work { continuation.yield(.delta($0)) }
                    continuation.yield(.reply(reply))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        var reply: ModelReply?
        for try await piece in pieces {
            switch piece {
            case .delta(let delta): onDelta(delta)
            case .reply(let complete): reply = complete
            }
        }
        guard let reply else {
            throw CancellationError()
        }
        return reply
    }
}

extension ProviderError {
    /// The error for an HTTP failure with `status` and `body`.
    ///
    /// - Parameters:
    ///   - status: The HTTP status.
    ///   - body: The response body.
    ///   - provider: The provider that answered.
    /// - Returns: The error, with the body's message as its detail.
    static func from(status: Int, body: String, provider: ProviderID) -> Self {
        let detail = message(in: body)
        return switch status {
        case 401: .signInRequired(provider, detail: "The API key was rejected. \(detail)")
        case 403: .notEligible(provider, detail: detail)
        case 429: .usageLimit(provider, detail: detail, manageURL: nil)
        case 500...: .unavailable(provider, detail: detail)
        default: .http(provider, status: status, detail: detail)
        }
    }

    /// The error for an error object reported inside a stream.
    ///
    /// - Parameters:
    ///   - error: The error object (or message) the API sent.
    ///   - provider: The provider that sent it.
    /// - Returns: The matching error.
    static func streamed(_ error: JSONValue, provider: ProviderID) -> Self {
        let detail = error["message"]?.stringValue ?? error.stringValue ?? error.jsonText
        let kind = [error["type"], error["status"], error["code"]].compactMap { $0?.stringValue }.joined(separator: " ")
        let code = error["code"]?.intValue
        if code == 429 || kind.contains("rate_limit") || kind.contains("RESOURCE_EXHAUSTED") {
            return .usageLimit(provider, detail: detail, manageURL: nil)
        }
        if code == 401 || kind.contains("authentication") {
            return .signInRequired(provider, detail: detail)
        }
        if let code, code < 500, code >= 400 {
            return .http(provider, status: code, detail: detail)
        }
        return .unavailable(provider, detail: detail)
    }

    /// The human-readable message in an error body: `error.message`,
    /// `error`, `message` or `detail`, else the body itself, shortened.
    static func message(in body: String) -> String {
        if let json = JSONValue.parse(body) {
            let candidates = [json["error"]?["message"], json["error"], json["message"], json["detail"]]
            if let message = candidates.lazy.compactMap({ $0?.stringValue }).first(where: { !$0.isEmpty }) {
                return message
            }
        }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 500 ? String(text.prefix(500)) + "…" : text
    }
}
