/// A ChatModel speaking OpenAI-compatible Chat Completions.
public struct ChatCompletionsChatModel: ChatModel {
    let endpoint: WireEndpoint

    /// Creates a model.
    ///
    /// - Parameter endpoint: Where and how requests go.
    public init(endpoint: WireEndpoint) {
        self.endpoint = endpoint
    }

    /// Streams the reply.
    public func reply(
        to conversation: [Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) async throws -> ModelReply {
        _ = try await endpoint.headers()
        throw ProviderError.unsupported(
            endpoint.provider, detail: "OpenAI-compatible Chat Completions is not built yet.")
    }
}
