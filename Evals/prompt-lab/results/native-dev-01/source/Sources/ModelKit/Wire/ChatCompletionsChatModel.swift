import OpenRouter

/// A ChatModel speaking OpenAI-compatible Chat Completions.
public struct ChatCompletionsChatModel: ChatModel {
    let endpoint: WireEndpoint
    let reasoningField: String?

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - endpoint: Where and how requests go.
    ///   - reasoningField: The assistant message field the model wants its
    ///     earlier reasoning sent back in (`"reasoning_content"`), or `nil`
    ///     to send none back.
    public init(endpoint: WireEndpoint, reasoningField: String? = "reasoning_content") {
        self.endpoint = endpoint
        self.reasoningField = reasoningField
    }

    /// Streams the reply.
    public func reply(
        to conversation: [Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) async throws -> ModelReply {
        let model = endpoint.model
        let field = reasoningField
        return try await WireStream.send(
            { Self.body(conversation, tools: tools, options: options, model: model, reasoningField: field) },
            to: endpoint, decoder: ChatCompletionsDecoder.self, onDelta: onDelta)
    }

    /// The request body.
    static func body(
        _ conversation: [Message], tools: [ToolSpec], options: ReplyOptions, model: String, reasoningField: String?,
    ) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(model),
            "messages": .array(conversation.map { message($0, reasoningField: reasoningField) }),
            "stream": true,
            "stream_options": ["include_usage": true],
        ]
        if !tools.isEmpty {
            body["tools"] = .array(tools.map(tool))
        }
        if let effort = options.reasoningEffort {
            body["reasoning_effort"] = .string(effort)
        }
        return .object(body)
    }

    private static func tool(_ spec: ToolSpec) -> JSONValue {
        [
            "type": "function",
            "function": [
                "name": .string(spec.name),
                "description": .string(spec.description),
                "parameters": .object(spec.parameters),
            ],
        ]
    }

    private static func message(_ message: Message, reasoningField: String?) -> JSONValue {
        switch message {
        case .system(let text):
            ["role": "system", "content": .string(text)]
        case .user(let text):
            ["role": "user", "content": .string(text)]
        case .tool(let callID, _, let content):
            ["role": "tool", "tool_call_id": .string(callID), "content": .string(content)]
        case .assistant(let assistant):
            self.assistant(assistant, reasoningField: reasoningField)
        }
    }

    private static func assistant(_ message: AssistantMessage, reasoningField: String?) -> JSONValue {
        var object: [String: JSONValue] = ["role": "assistant"]
        if let text = message.text, !text.isEmpty {
            object["content"] = .string(text)
        } else {
            object["content"] = message.toolCalls.isEmpty ? "" : .null
        }
        if !message.toolCalls.isEmpty {
            object["tool_calls"] = .array(
                message.toolCalls.map { call in
                    [
                        "id": .string(call.id),
                        "type": "function",
                        "function": ["name": .string(call.name), "arguments": .string(call.arguments)],
                    ]
                })
        }
        let replayed = message.replay.first { $0.format == .chatCompletions }?.payload["reasoning"]?.stringValue
        if let reasoningField, let replayed, !replayed.isEmpty {
            object[reasoningField] = .string(replayed)
        }
        return .object(object)
    }
}

/// Decodes Chat Completions chunks: content, reasoning (in
/// `reasoning_content` or `reasoning`, both exist), tool call fragments by
/// index, and the closing usage chunk.
struct ChatCompletionsDecoder: WireDecoder {
    private struct PartialCall {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private let provider: ProviderID
    private var text = ""
    private var reasoning = ""
    private var calls: [Int: PartialCall] = [:]
    private var callOrder: [Int] = []
    private var usage: Usage?
    private var sawChunk = false

    init(provider: ProviderID) {
        self.provider = provider
    }

    mutating func decode(_ event: ServerSentEvent) throws -> [ReplyDelta] {
        guard event.data != "[DONE]" else {
            return []
        }
        guard let chunk = JSONValue.parse(event.data) else {
            throw ProviderError.malformedResponse(provider, detail: "A stream chunk wasn't JSON.")
        }
        if let error = chunk["error"] {
            throw ProviderError.streamed(error, provider: provider)
        }
        sawChunk = true
        if let usage = chunk["usage"], usage.objectValue != nil {
            self.usage = Usage(
                inputTokens: usage["prompt_tokens"]?.intValue ?? 0,
                outputTokens: usage["completion_tokens"]?.intValue ?? 0,
                cost: usage["cost"]?.doubleValue,
                cachedInputTokens: usage["prompt_tokens_details"]?["cached_tokens"]?.intValue,
                cacheWriteInputTokens: usage["prompt_tokens_details"]?["cache_write_tokens"]?.intValue)
        }
        guard let delta = chunk["choices"]?.arrayValue?.first?["delta"] else {
            return []
        }
        return decodeDelta(delta)
    }

    private mutating func decodeDelta(_ delta: JSONValue) -> [ReplyDelta] {
        var deltas: [ReplyDelta] = []
        let reasoningPiece = [delta["reasoning_content"], delta["reasoning"]]
            .lazy.compactMap { $0?.stringValue }.first { !$0.isEmpty }
        if let reasoningPiece {
            reasoning += reasoningPiece
            deltas.append(.reasoning(reasoningPiece))
        }
        if let content = delta["content"]?.stringValue, !content.isEmpty {
            text += content
            deltas.append(.text(content))
        }
        for fragment in delta["tool_calls"]?.arrayValue ?? [] {
            if let name = addFragment(fragment) {
                deltas.append(.toolCall(name: name))
            }
        }
        return deltas
    }

    /// Adds a tool call fragment; returns the call's name when the fragment
    /// starts it.
    private mutating func addFragment(_ fragment: JSONValue) -> String? {
        let index = fragment["index"]?.intValue ?? callOrder.last ?? 0
        if calls[index] == nil {
            calls[index] = PartialCall()
            callOrder.append(index)
        }
        var call = calls[index] ?? PartialCall()
        defer { calls[index] = call }
        if let id = fragment["id"]?.stringValue, !id.isEmpty {
            call.id = id
        }
        call.arguments += fragment["function"]?["arguments"]?.stringValue ?? ""
        guard let name = fragment["function"]?["name"]?.stringValue, !name.isEmpty, call.name.isEmpty else {
            return nil
        }
        call.name = name
        return name
    }

    func reply() throws -> ModelReply {
        guard sawChunk else {
            throw ProviderError.malformedResponse(provider, detail: "The stream ended without a reply.")
        }
        let toolCalls = callOrder.compactMap { index in
            calls[index].map { call in
                ToolCall(
                    id: call.id.isEmpty ? "call_\(index)" : call.id, name: call.name,
                    arguments: call.arguments.isEmpty ? "{}" : call.arguments)
            }
        }
        let replay =
            reasoning.isEmpty ? [] : [ReplayItem(format: .chatCompletions, payload: ["reasoning": .string(reasoning)])]
        let message = AssistantMessage(
            text: text.isEmpty ? nil : text, reasoning: reasoning.isEmpty ? nil : reasoning, replay: replay,
            toolCalls: toolCalls)
        return ModelReply(message: message, usage: usage)
    }
}
