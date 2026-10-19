import Foundation
import OpenRouter

/// A ChatModel speaking OpenAI Responses.
///
/// Every request carries the whole conversation with `store: false`, so the
/// server keeps nothing between turns: reasoning survives a turn only as
/// encrypted reasoning items, replayed from ``AssistantMessage/replay``.
public struct ResponsesChatModel: ChatModel {
    let endpoint: WireEndpoint
    let includeEncryptedReasoning: Bool

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - endpoint: Where and how requests go.
    ///   - includeEncryptedReasoning: Asks for the model's reasoning in
    ///     encrypted form so the next turn can send it back. Only for models
    ///     that reason; others reject it.
    public init(endpoint: WireEndpoint, includeEncryptedReasoning: Bool = false) {
        self.endpoint = endpoint
        self.includeEncryptedReasoning = includeEncryptedReasoning
    }

    /// Streams the reply.
    ///
    /// - Parameters:
    ///   - conversation: The conversation so far.
    ///   - tools: The tools the model may call.
    ///   - options: Reasoning effort and session.
    ///   - onDelta: Receives the reply piece by piece, as it arrives.
    /// - Returns: The complete reply, once the response completed.
    /// - Throws: A ``ProviderError``, also mid-stream, or a transport error.
    public func reply(
        to conversation: [Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) async throws -> ModelReply {
        let (model, includeEncryptedReasoning) = (endpoint.model, includeEncryptedReasoning)
        return try await WireStream.send(
            {
                Self.body(
                    for: conversation, tools: tools, options: options, model: model,
                    includeEncryptedReasoning: includeEncryptedReasoning)
            },
            to: endpoint, decoder: ResponsesDecoder.self, onDelta: onDelta)
    }

    /// The request body: the conversation as `input`, the system prompt as
    /// `instructions`, always `store: false` and `stream: true`.
    static func body(
        for conversation: [Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        model: String,
        includeEncryptedReasoning: Bool,
    ) -> JSONValue {
        let (instructions, input) = Self.input(for: conversation)
        var body: [String: JSONValue] = [
            "model": .string(model), "input": .array(input), "store": false, "stream": true,
        ]
        if let instructions {
            body["instructions"] = .string(instructions)
        }
        if !tools.isEmpty {
            body["tools"] = .array(tools.map(Self.tool))
            body["tool_choice"] = "auto"
        }
        if let effort = options.reasoningEffort {
            body["reasoning"] = ["effort": .string(effort), "summary": "auto"]
        }
        if includeEncryptedReasoning {
            body["include"] = ["reasoning.encrypted_content"]
        }
        if !options.sessionID.isEmpty {
            body["prompt_cache_key"] = .string(String(options.sessionID.prefix(64)))
        }
        return .object(body)
    }

    /// The conversation as Responses `input` items, and its system messages
    /// joined for `instructions` (system-role items are rejected on some routes).
    static func input(for conversation: [Message]) -> (instructions: String?, items: [JSONValue]) {
        var system: [String] = []
        var items: [JSONValue] = []
        for message in conversation {
            switch message {
            case .system(let text):
                system.append(text)
            case .user(let text):
                let content: JSONValue = [["type": "input_text", "text": .string(text)]]
                items.append(["type": "message", "role": "user", "content": content])
            case .assistant(let assistant):
                items += Self.items(for: assistant)
            case .tool(let callID, _, let content):
                items.append(["type": "function_call_output", "call_id": .string(callID), "output": .string(content)])
            }
        }
        let instructions = system.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return (instructions.isEmpty ? nil : instructions, items)
    }

    /// An assistant turn: its own replayed reasoning first, then its text,
    /// then its calls. Other formats' replay items are left out.
    private static func items(for message: AssistantMessage) -> [JSONValue] {
        var items = message.replay.filter { $0.format == .responses }.map(\.payload)
        if let text = message.text, !text.isEmpty {
            items.append([
                "type": "message", "role": "assistant",
                "content": [["type": "output_text", "text": .string(text), "annotations": []]],
            ])
        }
        for call in message.toolCalls {
            items.append([
                "type": "function_call", "call_id": .string(call.id), "name": .string(call.name),
                "arguments": .string(call.arguments),
            ])
        }
        return items
    }

    /// A function tool. `strict` is off: the Responses API turns it on by
    /// default, and that requires schemas the tools don't promise.
    private static func tool(_ spec: ToolSpec) -> JSONValue {
        [
            "type": "function", "name": .string(spec.name), "description": .string(spec.description),
            "parameters": .object(spec.parameters), "strict": false,
        ]
    }
}
