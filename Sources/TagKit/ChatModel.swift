public import OpenRouter

/// Something that writes the next reply in a conversation. The seam between
/// the agent loop and the model API, so tests can script replies.
public protocol ChatModel {
    /// Generate the next reply to a conversation
    ///
    /// - Parameters:
    ///   - conversation: The conversation history
    ///   - tools: The tools the model may call
    /// - Returns: The result of generating the next chat reply
    /// - Throws: Whatever the model API throws.
    func reply(to conversation: [ChatMessage], tools: [ChatTool]) async throws -> ChatResult
}

/// A ``ChatModel`` backed by OpenRouter.
public struct OpenRouterChatModel: ChatModel {
    private let openRouterClient: OpenRouterClient

    /// Creates a model that reads its API key from `OPENROUTER_API_KEY`.
    public init() throws {
        self.openRouterClient = try OpenRouterClient.fromEnvironment()
    }

    /// Sends the conversation and tools to OpenRouter.
    public func reply(to conversation: [ChatMessage], tools: [ChatTool]) async throws -> ChatResult {
        try await openRouterClient.chat.send(
            .init(
                messages: conversation,
                model: "deepseek/deepseek-v4.1-flash",
                toolChoice: tools.isEmpty ? nil : .auto,
                tools: tools.isEmpty ? nil : tools,
            )
        )
    }
}
