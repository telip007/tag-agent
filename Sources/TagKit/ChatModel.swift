public import OpenRouter

/// Something that writes the next reply in a conversation. The seam between
/// the agent loop and the model API, so tests can script replies.
public protocol ChatModel {
    /// Describes the model for the status line.
    ///
    /// - Returns: The model's human-readable name and, when the catalogue
    ///   knows it, its context window.
    func modelDescription() async -> ModelDescription

    /// Generate the next reply to a conversation
    ///
    /// - Parameters:
    ///   - conversation: The conversation history
    ///   - tools: The tools the model may call
    /// - Returns: The result of generating the next chat reply
    /// - Throws: Whatever the model API throws.
    func reply(to conversation: [ChatMessage], tools: [ChatTool]) async throws -> ChatResult
}

/// A human-readable description of a model, shown in the status line.
public struct ModelDescription: Sendable, Equatable {
    /// The name to show, e.g. `"DeepSeek V4.1 Flash"`.
    public var name: String
    /// The model's context window in tokens, when the catalogue reports it.
    public var contextLength: Int?

    /// Creates a model description.
    ///
    /// - Parameters:
    ///   - name: The name to show.
    ///   - contextLength: The context window in tokens, when known.
    public init(name: String, contextLength: Int? = nil) {
        self.name = name
        self.contextLength = contextLength
    }

    /// A catalogue name without its author prefix: OpenRouter's
    /// `"DeepSeek: DeepSeek V4.1 Flash"` becomes `"DeepSeek V4.1 Flash"`.
    static func displayName(_ catalogueName: String) -> String {
        guard let separator = catalogueName.firstRange(of: ": ") else {
            return catalogueName
        }
        let name = catalogueName[separator.upperBound...]
        return name.isEmpty ? catalogueName : String(name)
    }
}

/// A ``ChatModel`` backed by OpenRouter.
public struct OpenRouterChatModel: ChatModel {
    /// The model Tag Agent chats with unless another is given.
    public static let defaultModel = "deepseek/deepseek-v4.1-flash"

    private let openRouterClient: OpenRouterClient
    private let modelID: String

    /// Creates a model that reads its API key from `OPENROUTER_API_KEY`.
    ///
    /// - Parameter modelID: The OpenRouter model id, e.g. `"openai/gpt-4o-mini"`.
    /// - Throws: When `OPENROUTER_API_KEY` is unset or empty.
    public init(modelID: String = Self.defaultModel) throws {
        self.openRouterClient = try OpenRouterClient.fromEnvironment()
        self.modelID = modelID
    }

    /// Reads the model's display name and context window from the catalogue.
    ///
    /// Falls back to the model id and no context window when the catalogue
    /// can't be reached.
    public func modelDescription() async -> ModelDescription {
        do {
            let info = try await openRouterClient.models.get(modelID)
            return ModelDescription(name: ModelDescription.displayName(info.name), contextLength: info.contextLength)
        } catch {
            return ModelDescription(name: modelID)
        }
    }

    /// Sends the conversation and tools to OpenRouter.
    public func reply(to conversation: [ChatMessage], tools: [ChatTool]) async throws -> ChatResult {
        try await openRouterClient.chat.send(
            .init(
                messages: conversation,
                model: modelID,
                toolChoice: tools.isEmpty ? nil : .auto,
                tools: tools.isEmpty ? nil : tools,
            )
        )
    }
}
