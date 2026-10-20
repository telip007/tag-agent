import Foundation
import ModelKit

@testable import TagKit

/// The production Agent owns the loop and tools; this wrapper records inference.
final class BenchmarkModel: ChatModel {
    let underlying: any ChatModel
    let rules: [String]?
    let tools: [ToolDefinition]
    let maxCalls: Int
    let scaffold: BenchmarkScaffold
    private(set) var prompt = ""
    private(set) var responses: [BenchmarkResponse] = []
    private(set) var attemptedCalls = 0
    private(set) var limitReached = false

    init(
        underlying: any ChatModel, rules: [String]?, tools: [ToolDefinition], maxCalls: Int,
        scaffold: BenchmarkScaffold = .standard,
    ) {
        self.underlying = underlying
        self.rules = rules
        self.tools = tools
        self.maxCalls = maxCalls
        self.scaffold = scaffold
    }

    func reply(
        to conversation: [Message], tools: [ToolSpec], options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) async throws -> ModelReply {
        guard attemptedCalls < maxCalls else {
            limitReached = true
            throw BenchmarkFailure.requestLimit
        }
        var messages = conversation
        guard case .system(let original) = messages.first else {
            throw BenchmarkFailure.unexpectedPrompt
        }
        prompt = try BenchmarkPolicy.applying(rules, to: original, tools: self.tools, scaffold: scaffold)
        messages[0] = .system(prompt)
        attemptedCalls += 1
        let result = try await underlying.reply(to: messages, tools: tools, options: options, onDelta: onDelta)
        responses.append(BenchmarkResponse(result))
        return result
    }
}

/// Common experimental generation limits; production adapters build the body.
struct BenchmarkTransport: HTTPTransport {
    let transport: URLSessionTransport
    let maxTokens: Int

    init(maxTokens: Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        transport = URLSessionTransport(session: URLSession(configuration: configuration))
        self.maxTokens = maxTokens
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await transport.data(for: request)
    }

    func lines(
        for request: URLRequest
    ) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, any Error>) {
        try await transport.lines(for: capped(request))
    }

    func capped(_ request: URLRequest) throws -> URLRequest {
        guard let data = request.httpBody,
            var body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw BenchmarkFailure.unexpectedPrompt
        }
        if request.url?.path.hasSuffix("chat/completions") == true {
            body["max_tokens"] = maxTokens
            body["temperature"] = 0
        } else if request.url?.path.hasSuffix(":streamGenerateContent") == true {
            var configuration = body["generationConfig"] as? [String: Any] ?? [:]
            configuration["maxOutputTokens"] = maxTokens
            configuration["temperature"] = 0
            body["generationConfig"] = configuration
        } else {
            throw BenchmarkFailure.unexpectedPrompt
        }
        var result = request
        result.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return result
    }
}
