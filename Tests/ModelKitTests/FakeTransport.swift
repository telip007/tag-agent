import Foundation
import OpenRouter
import Synchronization
import Testing

@testable import ModelKit

/// An ``HTTPTransport`` that answers from a script and records the requests.
final class FakeTransport: HTTPTransport {
    /// A scripted answer: status and body.
    struct Answer: Sendable {
        var status: Int
        var body: String
    }

    private let answer: @Sendable (URLRequest) -> Answer?
    private let recorded = Mutex<[URLRequest]>([])

    /// Answers every request with `status` and `body`.
    convenience init(status: Int = 200, body: String) {
        self.init { _ in Answer(status: status, body: body) }
    }

    /// Answers each request with what `answer` returns; `nil` fails it as
    /// if offline.
    init(answer: @escaping @Sendable (URLRequest) -> Answer?) {
        self.answer = answer
    }

    /// The requests sent so far.
    var requests: [URLRequest] {
        recorded.withLock { $0 }
    }

    /// The last request's body as JSON.
    func lastBody() throws -> JSONValue {
        let data = try #require(requests.last?.httpBody)
        return try #require(JSONValue.parse(data))
    }

    func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let answer = try respond(to: request)
        return (Data(answer.body.utf8), try response(answer, request))
    }

    func lines(for request: URLRequest) throws -> (HTTPURLResponse, AsyncThrowingStream<String, any Error>) {
        let answer = try respond(to: request)
        let lines = answer.body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let stream = AsyncThrowingStream<String, any Error> { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return (try response(answer, request), stream)
    }

    private func respond(to request: URLRequest) throws -> Answer {
        recorded.withLock { $0.append(request) }
        guard let answer = answer(request) else {
            throw URLError(.notConnectedToInternet)
        }
        return answer
    }

    private func response(_ answer: Answer, _ request: URLRequest) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil, headerFields: nil))
    }
}

/// Builders shared by the wire format tests.
enum Fixtures {
    /// An endpoint at `url` that sends through `transport`.
    static func endpoint(
        _ transport: FakeTransport, url: String = "https://api.test/v1/x", model: String = "test-model",
    ) throws -> WireEndpoint {
        WireEndpoint(
            url: try #require(URL(string: url)), model: model, provider: .openCodeGo,
            headers: { ["Authorization": "Bearer key"] }, transport: transport)
    }

    /// Server-sent events with `data:` lines for each payload, named when
    /// a name is given.
    static func sse(_ events: [(name: String?, data: String)]) -> String {
        events.map { event in
            (event.name.map { "event: \($0)\n" } ?? "") + "data: \(event.data)\n\n"
        }.joined()
    }

    /// Server-sent events of unnamed payloads.
    static func sse(_ payloads: [String]) -> String {
        sse(payloads.map { (nil, $0) })
    }

    /// A tool for requests.
    static let readTool = ToolSpec(
        name: "read_file", description: "Reads a file.",
        parameters: [
            "$schema": "http://json-schema.org/draft-07/schema#",
            "type": "object",
            "properties": ["path": ["type": "string"]],
            "required": ["path"],
            "additionalProperties": false,
        ])

    /// A conversation with every kind of message.
    static let conversation: [Message] = [
        .system("Be brief."),
        .user("Read a.txt and b.txt"),
        .assistant(
            AssistantMessage(
                text: "Reading.",
                toolCalls: [
                    ToolCall(id: "c1", name: "read_file", arguments: #"{"path":"a.txt"}"#),
                    ToolCall(id: "c2", name: "read_file", arguments: #"{"path":"b.txt"}"#),
                ])),
        .tool(callID: "c1", name: "read_file", content: "A"),
        .tool(callID: "c2", name: "read_file", content: "B"),
    ]

    /// Options with a session and, optionally, an effort.
    static func options(effort: String? = nil) -> ReplyOptions {
        ReplyOptions(reasoningEffort: effort, sessionID: "session-1")
    }
}
