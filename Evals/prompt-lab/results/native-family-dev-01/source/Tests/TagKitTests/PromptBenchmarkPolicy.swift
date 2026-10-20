import Foundation
import ModelKit

@testable import TagKit

enum BenchmarkFailure: Error {
    case unexpectedPrompt
    case requestLimit
}

/// Changes the experimental variable while retaining the actual rendered shell.
enum BenchmarkPolicy {
    static func applying(_ rules: [String]?, to prompt: String, tools: [ToolDefinition] = []) throws -> String {
        guard let rules else { return prompt }
        let current =
            "<rules>\n"
            + (SystemPrompt.rules + tools.flatMap(\.guidelines))
            .map { "- \($0)" }.joined(separator: "\n") + "\n</rules>"
        guard let range = prompt.range(of: current) else {
            throw BenchmarkFailure.unexpectedPrompt
        }
        let replacement =
            "<rules>\n"
            + (rules + tools.flatMap(\.guidelines))
            .map { "- \($0)" }.joined(separator: "\n") + "\n</rules>"
        return prompt.replacingCharacters(in: range, with: replacement)
    }
}

struct BenchmarkJob: Codable {
    var model: String
    var rules: [String]?
    var task: String
    var directory: String
    var output: String
    var maxCalls: Int
    var maxTokens: Int
}

struct BenchmarkResponse: Codable {
    var text: String?
    var reasoning: String?
    var toolCalls: [ModelKit.ToolCall]
    var inputTokens: Int?
    var outputTokens: Int?
    var cachedInputTokens: Int?
    var cost: Double?

    init(_ reply: ModelReply) {
        text = reply.message.text
        reasoning = reply.message.reasoning
        toolCalls = reply.message.toolCalls
        inputTokens = reply.usage?.inputTokens
        outputTokens = reply.usage?.outputTokens
        cachedInputTokens = reply.usage?.cachedInputTokens
        cost = reply.usage?.cost
    }
}

struct BenchmarkToolEvent: Codable {
    var name: String
    var arguments: String
    var output: String
    var failed: Bool
}

struct BenchmarkOutcome: Codable {
    var model: String
    var prompt: String
    var responses: [BenchmarkResponse]
    var tools: [BenchmarkToolEvent]
    var final: String
    var failure: String?
    var requestLimitReached: Bool
    var attemptedCalls: Int
}
