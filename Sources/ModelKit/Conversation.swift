public import OpenRouter

/// One message in a conversation, in a shape no provider owns. Each wire
/// format adapter translates it to and from its API.
public enum Message: Sendable, Equatable {
    /// The system prompt.
    case system(String)
    /// What the user wrote.
    case user(String)
    /// What the model wrote.
    case assistant(AssistantMessage)
    /// A tool's result for the call `callID` to the tool `name`.
    case tool(callID: String, name: String, content: String)
}

/// A message the model wrote: text, reasoning and tool calls.
public struct AssistantMessage: Sendable, Equatable, Codable {
    /// The reply's text, if any.
    public var text: String?
    /// The model's readable reasoning, if any.
    public var reasoning: String?
    /// Provider data to send back with this message on the next turn
    /// (encrypted reasoning, thinking signatures). An adapter replays only
    /// the items of its own ``WireFormat`` and ignores the rest, so a
    /// conversation survives a switch to another provider.
    public var replay: [ReplayItem]
    /// The tools the model wants called, in order.
    public var toolCalls: [ToolCall]

    /// Creates an assistant message.
    ///
    /// - Parameters:
    ///   - text: The reply's text.
    ///   - reasoning: The readable reasoning.
    ///   - replay: Provider data to send back on the next turn.
    ///   - toolCalls: The tools the model wants called.
    public init(text: String? = nil, reasoning: String? = nil, replay: [ReplayItem] = [], toolCalls: [ToolCall] = []) {
        self.text = text
        self.reasoning = reasoning
        self.replay = replay
        self.toolCalls = toolCalls
    }
}

/// Opaque provider data attached to an assistant message, replayed only to
/// an adapter of the same format.
public struct ReplayItem: Sendable, Equatable, Codable {
    /// The wire format that produced the item and understands it.
    public var format: WireFormat
    /// The item as the API sent it.
    public var payload: JSONValue

    /// Creates a replay item.
    ///
    /// - Parameters:
    ///   - format: The wire format that produced the item.
    ///   - payload: The item as the API sent it.
    public init(format: WireFormat, payload: JSONValue) {
        self.format = format
        self.payload = payload
    }
}

/// A call the model wants made.
public struct ToolCall: Sendable, Equatable, Codable {
    /// The call's id, echoed back with its result.
    public var id: String
    /// The tool's name.
    public var name: String
    /// The arguments, as the JSON text the model wrote.
    public var arguments: String

    /// Creates a tool call.
    ///
    /// - Parameters:
    ///   - id: The call's id.
    ///   - name: The tool's name.
    ///   - arguments: The arguments as JSON text.
    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// A tool as every API describes it: a name, what it does, and the JSON
/// Schema of its input.
public struct ToolSpec: Sendable, Equatable {
    /// The name the model calls it by.
    public var name: String
    /// What the tool does. The model reads this.
    public var description: String
    /// A JSON Schema object describing the input.
    public var parameters: [String: JSONValue]

    /// Creates a tool description.
    ///
    /// - Parameters:
    ///   - name: The name the model calls it by.
    ///   - description: What the tool does.
    ///   - parameters: A JSON Schema object describing the input.
    public init(name: String, description: String, parameters: [String: JSONValue]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Token counts and cost of one reply.
public struct Usage: Sendable, Equatable, Codable {
    /// Tokens sent, cached ones included.
    public var inputTokens: Int
    /// Tokens written, reasoning included.
    public var outputTokens: Int
    /// What the reply cost in US dollars, when the API reports it. Plan
    /// usage reports none.
    public var cost: Double?

    /// Input tokens read from cache, or `nil` when the provider didn't report them.
    public var cachedInputTokens: Int?
    /// Input tokens written to cache, or `nil` when the provider didn't report them.
    public var cacheWriteInputTokens: Int?

    /// Creates usage figures.
    ///
    /// - Parameters:
    ///   - inputTokens: Tokens sent.
    ///   - outputTokens: Tokens written.
    ///   - cost: The cost in US dollars, when known.
    ///   - cachedInputTokens: Input tokens read from cache, when reported.
    ///   - cacheWriteInputTokens: Input tokens written to cache, when reported.
    public init(
        inputTokens: Int, outputTokens: Int, cost: Double? = nil,
        cachedInputTokens: Int? = nil, cacheWriteInputTokens: Int? = nil,
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cost = cost
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
    }

    /// Everything the context holds after the reply.
    public var totalTokens: Int {
        inputTokens + outputTokens
    }
}

/// A piece of a reply that is still streaming.
public enum ReplyDelta: Sendable, Equatable {
    /// More of the reply's text.
    case text(String)
    /// More of the model's reasoning, before or between its text.
    case reasoning(String)
    /// The model started writing a call to the tool `name`; its arguments follow.
    case toolCall(name: String)
}

/// A complete reply from a ``ChatModel``.
public struct ModelReply: Sendable, Equatable {
    /// The assistant message, ready to append to the conversation.
    public var message: AssistantMessage
    /// Token counts and cost, when the API reported them.
    public var usage: Usage?

    /// Creates a reply.
    ///
    /// - Parameters:
    ///   - message: The assistant message.
    ///   - usage: Token counts and cost, when known.
    public init(message: AssistantMessage, usage: Usage? = nil) {
        self.message = message
        self.usage = usage
    }
}

/// Per-request settings that are not part of the conversation.
public struct ReplyOptions: Sendable, Equatable {
    /// How hard the model should think (`"low"`, `"high"`, …), or `nil` for
    /// the model's default. Only values from ``ModelEntry/reasoningEfforts``.
    public var reasoningEffort: String?
    /// A stable id for the conversation, for providers that route or cache
    /// by session. A new conversation gets a new id.
    public var sessionID: String

    /// Creates options.
    ///
    /// - Parameters:
    ///   - reasoningEffort: How hard the model should think.
    ///   - sessionID: A stable id for the conversation.
    public init(reasoningEffort: String? = nil, sessionID: String) {
        self.reasoningEffort = reasoningEffort
        self.sessionID = sessionID
    }
}

/// Something that writes the next reply in a conversation: the seam between
/// the agent loop and a provider's API, so tests can script replies.
public protocol ChatModel {
    /// Generates the next reply to a conversation, streaming it.
    ///
    /// - Parameters:
    ///   - conversation: The conversation so far.
    ///   - tools: The tools the model may call.
    ///   - options: Reasoning effort and session.
    ///   - onDelta: Receives the reply piece by piece, as it arrives.
    /// - Returns: The complete reply.
    /// - Throws: A ``ProviderError`` or a transport error, also after
    ///   streaming started.
    func reply(
        to conversation: [Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) async throws -> ModelReply
}
