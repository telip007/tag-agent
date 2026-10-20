import OpenRouter

/// A ChatModel speaking Anthropic Messages.
public struct AnthropicChatModel: ChatModel {
    /// How the model is told how hard to think.
    public enum Thinking: Sendable, Equatable {
        /// Adaptive thinking, with the effort in `output_config` (current
        /// Claude models).
        case adaptive
        /// Thinking with a token budget that grows with the effort (older
        /// Claude models and other models served in this format).
        case budget
    }

    /// The `anthropic-version` header the requests are written for.
    static let version = "2023-06-01"

    let endpoint: WireEndpoint
    let maxTokens: Int
    let thinking: Thinking

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - endpoint: Where and how requests go.
    ///   - maxTokens: The reply's token limit, which the API requires;
    ///     usually the model's output limit.
    ///   - thinking: How the model is told how hard to think.
    public init(endpoint: WireEndpoint, maxTokens: Int = 32_000, thinking: Thinking = .budget) {
        self.endpoint = endpoint
        self.maxTokens = maxTokens
        self.thinking = thinking
    }

    /// Streams the reply.
    public func reply(
        to conversation: [Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) async throws -> ModelReply {
        var endpoint = endpoint
        let headers = endpoint.headers
        endpoint.headers = {
            var all = try await headers()
            all["anthropic-version"] = Self.version
            return all
        }
        let settings = Settings(model: endpoint.model, maxTokens: maxTokens, thinking: thinking)
        return try await WireStream.send(
            { Self.body(conversation, tools: tools, options: options, settings: settings) },
            to: endpoint, decoder: AnthropicDecoder.self, onDelta: onDelta)
    }

    /// What the body needs besides the conversation.
    struct Settings: Sendable {
        var model: String
        var maxTokens: Int
        var thinking: Thinking
    }

    /// The request body.
    static func body(
        _ conversation: [Message], tools: [ToolSpec], options: ReplyOptions, settings: Settings
    ) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(settings.model),
            "max_tokens": .int(settings.maxTokens),
            "stream": true,
            "messages": .array(messages(conversation)),
        ]
        let system = conversation.compactMap { message -> String? in
            if case .system(let text) = message { text } else { nil }
        }
        if !system.isEmpty {
            body["system"] = [
                ["type": "text", "text": .string(system.joined(separator: "\n\n")), "cache_control": cache]
            ]
        }
        if !tools.isEmpty {
            body["tools"] = .array(tools.enumerated().map { tool($1, cached: $0 == tools.count - 1) })
        }
        for (key, value) in thinkingFields(effort: options.reasoningEffort, settings: settings) {
            body[key] = value
        }
        return .object(body)
    }

    private static let cache: JSONValue = ["type": "ephemeral"]

    /// The token budget per effort for ``Thinking/budget``.
    static let budgets = [
        "minimal": 1024, "low": 4096, "medium": 10_000, "high": 16_000, "xhigh": 32_000, "max": 64_000,
    ]

    private static func thinkingFields(effort: String?, settings: Settings) -> [String: JSONValue] {
        guard let effort else {
            return [:]
        }
        if effort == "none" {
            return ["thinking": ["type": "disabled"]]
        }
        switch settings.thinking {
        case .adaptive:
            return [
                "thinking": ["type": "adaptive", "display": "summarized"], "output_config": ["effort": .string(effort)],
            ]
        case .budget:
            let budget = min(budgets[effort] ?? 10_000, settings.maxTokens - 1024)
            guard budget >= 1024 else {
                return [:]
            }
            return ["thinking": ["type": "enabled", "budget_tokens": .int(budget)]]
        }
    }

    private static func tool(_ spec: ToolSpec, cached: Bool) -> JSONValue {
        var object: [String: JSONValue] = [
            "name": .string(spec.name),
            "description": .string(spec.description),
            "input_schema": .object(spec.parameters),
        ]
        if cached {
            object["cache_control"] = cache
        }
        return .object(object)
    }

    /// The conversation as Messages turns: tool results go in a user turn,
    /// consecutive ones merged. The last two user turns keep both the new
    /// write boundary and the previous request's readable cache entry.
    static func messages(_ conversation: [Message]) -> [JSONValue] {
        var turns: [(role: String, content: [JSONValue])] = []
        for message in conversation {
            switch message {
            case .system:
                continue
            case .user(let text):
                turns.append(("user", [["type": "text", "text": .string(text)]]))
            case .assistant(let assistant):
                let content = assistantContent(assistant)
                if !content.isEmpty {
                    turns.append(("assistant", content))
                }
            case .tool(let callID, _, let content):
                let result: JSONValue = [
                    "type": "tool_result", "tool_use_id": .string(callID), "content": .string(content),
                ]
                if let last = turns.last, last.role == "user", last.content.allSatisfy(isToolResult) {
                    turns[turns.count - 1].content.append(result)
                } else {
                    turns.append(("user", [result]))
                }
            }
        }
        for index in turns.indices.filter({ turns[$0].role == "user" }).suffix(2) {
            guard case .object(var block)? = turns[index].content.last else { continue }
            block["cache_control"] = cache
            turns[index].content[turns[index].content.count - 1] = .object(block)
        }
        return turns.map { ["role": .string($0.role), "content": .array($0.content)] }
    }

    private static func isToolResult(_ block: JSONValue) -> Bool {
        block["type"]?.stringValue == "tool_result"
    }

    /// An assistant turn's blocks: the ones the API sent, verbatim, when they
    /// carry thinking; else rebuilt from the text and tool calls.
    private static func assistantContent(_ message: AssistantMessage) -> [JSONValue] {
        if let blocks = message.replay.first(where: { $0.format == .anthropicMessages })?.payload.arrayValue {
            return blocks
        }
        var blocks: [JSONValue] = []
        if let text = message.text, !text.isEmpty {
            blocks.append(["type": "text", "text": .string(text)])
        }
        for call in message.toolCalls {
            let input = JSONValue.parse(call.arguments).flatMap { $0.objectValue == nil ? nil : $0 } ?? [:]
            blocks.append(["type": "tool_use", "id": .string(call.id), "name": .string(call.name), "input": input])
        }
        return blocks
    }
}
