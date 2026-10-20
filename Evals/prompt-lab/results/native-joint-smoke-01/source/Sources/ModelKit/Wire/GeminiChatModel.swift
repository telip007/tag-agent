import OpenRouter

/// A ChatModel speaking Google Gemini generateContent. The endpoint's URL is
/// the model's `:streamGenerateContent?alt=sse` URL.
public struct GeminiChatModel: ChatModel {
    /// The signature Gemini accepts on a function call it didn't sign, such
    /// as one another provider's model made earlier in the conversation.
    static let unsignedCall = "skip_thought_signature_validator"

    let endpoint: WireEndpoint
    let includesThoughts: Bool

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - endpoint: Where and how requests go.
    ///   - includesThoughts: Whether to ask for the model's thought
    ///     summaries; only for models that think.
    public init(endpoint: WireEndpoint, includesThoughts: Bool = true) {
        self.endpoint = endpoint
        self.includesThoughts = includesThoughts
    }

    /// Streams the reply.
    public func reply(
        to conversation: [Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) async throws -> ModelReply {
        let thoughts = includesThoughts
        return try await WireStream.send(
            { Self.body(conversation, tools: tools, options: options, includesThoughts: thoughts) },
            to: endpoint, decoder: GeminiDecoder.self, onDelta: onDelta)
    }

    /// The request body.
    static func body(
        _ conversation: [Message], tools: [ToolSpec], options: ReplyOptions, includesThoughts: Bool,
    ) -> JSONValue {
        var body: [String: JSONValue] = ["contents": .array(contents(conversation))]
        let system = conversation.compactMap { message -> String? in
            if case .system(let text) = message { text } else { nil }
        }
        if !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": .string(system.joined(separator: "\n\n"))]]]
        }
        if !tools.isEmpty {
            body["tools"] = [["functionDeclarations": .array(tools.map(declaration))]]
        }
        var thinking: [String: JSONValue] = [:]
        if includesThoughts {
            thinking["includeThoughts"] = true
        }
        if let effort = options.reasoningEffort {
            thinking["thinkingLevel"] = .string(effort)
        }
        if !thinking.isEmpty {
            body["generationConfig"] = ["thinkingConfig": .object(thinking)]
        }
        return .object(body)
    }

    private static func declaration(_ spec: ToolSpec) -> JSONValue {
        [
            "name": .string(spec.name),
            "description": .string(spec.description),
            "parameters": GeminiSchema.sanitize(.object(spec.parameters)),
        ]
    }

    /// The conversation as Gemini contents: the user's turns and tool
    /// results (consecutive ones merged) as `user`, the model's as `model`.
    static func contents(_ conversation: [Message]) -> [JSONValue] {
        var turns: [(role: String, parts: [JSONValue])] = []
        for message in conversation {
            switch message {
            case .system:
                continue
            case .user(let text):
                turns.append(("user", [["text": .string(text)]]))
            case .assistant(let assistant):
                let parts = modelParts(assistant)
                if !parts.isEmpty {
                    turns.append(("model", parts))
                }
            case .tool(_, let name, let content):
                let part: JSONValue = [
                    "functionResponse": ["name": .string(name), "response": ["output": .string(content)]]
                ]
                if let last = turns.last, last.role == "user", last.parts.allSatisfy({ $0["functionResponse"] != nil })
                {
                    turns[turns.count - 1].parts.append(part)
                } else {
                    turns.append(("user", [part]))
                }
            }
        }
        return turns.map { ["role": .string($0.role), "parts": .array($0.parts)] }
    }

    /// A model turn's parts: the ones the API sent, verbatim, when they carry
    /// thought signatures; else rebuilt from the text and tool calls.
    private static func modelParts(_ message: AssistantMessage) -> [JSONValue] {
        if let parts = message.replay.first(where: { $0.format == .gemini })?.payload.arrayValue {
            return parts
        }
        var parts: [JSONValue] = []
        if let text = message.text, !text.isEmpty {
            parts.append(["text": .string(text)])
        }
        for (index, call) in message.toolCalls.enumerated() {
            let args = JSONValue.parse(call.arguments).flatMap { $0.objectValue == nil ? nil : $0 } ?? [:]
            var part: [String: JSONValue] = ["functionCall": ["name": .string(call.name), "args": args]]
            if index == 0 {
                part["thoughtSignature"] = .string(unsignedCall)
            }
            parts.append(.object(part))
        }
        return parts
    }
}

/// Gemini's schema dialect, an OpenAPI subset: it rejects keys such as
/// `$schema` and `additionalProperties`, and type lists.
enum GeminiSchema {
    private static let allowed: Set = [
        "type", "format", "title", "description", "nullable", "enum", "items", "minItems", "maxItems",
        "properties", "required", "minProperties", "maxProperties", "minLength", "maxLength", "pattern",
        "minimum", "maximum", "anyOf", "default", "example", "propertyOrdering",
    ]

    /// `schema` with only the keys Gemini accepts; `["string", "null"]`
    /// types become `"string"` with `nullable`, and `const` an `enum`.
    static func sanitize(_ schema: JSONValue) -> JSONValue {
        guard let object = schema.objectValue else {
            return schema
        }
        var result: [String: JSONValue] = [:]
        for (key, value) in object where allowed.contains(key) {
            switch key {
            case "properties":
                result[key] = value.objectValue.map { .object($0.mapValues(sanitize)) } ?? value
            case "items":
                result[key] = sanitize(value)
            case "anyOf":
                result[key] = value.arrayValue.map { .array($0.map(sanitize)) } ?? value
            default:
                result[key] = value
            }
        }
        if let types = object["type"]?.arrayValue {
            let named = types.compactMap(\.stringValue)
            result["type"] = named.first { $0 != "null" }.map(JSONValue.string)
            if named.contains("null") {
                result["nullable"] = true
            }
        }
        if let constant = object["const"], result["enum"] == nil {
            result["enum"] = [constant]
        }
        return .object(result)
    }
}
