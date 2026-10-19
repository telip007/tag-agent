import Foundation

extension OpenCodeGoProvider {
    /// Catalogue entries for the model `ids`, in order, with models.dev's
    /// metadata where it has the model and guesses from the id where not.
    ///
    /// - Parameters:
    ///   - ids: The model ids.
    ///   - metadata: models.dev's Go provider, if it could be read.
    /// - Returns: The entries.
    static func entries(ids: [String], metadata: ModelsDevProvider?) -> [ModelEntry] {
        ids.map { id in
            let model = metadata?.models[id]
            let free = model?.isFree ?? id.hasSuffix("-free")
            return ModelEntry(
                ref: ModelRef(provider: .openCodeGo, model: id),
                name: model?.name ?? id,
                contextLength: model?.contextLength,
                pricing: free ? .free : .included,
                reasoningEfforts: model?.reasoningEfforts ?? [],
                format: metadata?.format(of: id) ?? guessedFormat(of: id))
        }
    }

    /// models.dev's models that aren't deprecated, by name: the stand-in when
    /// Go's own list can't be read.
    static func currentIDs(_ metadata: ModelsDevProvider) -> [String] {
        metadata.models.filter { !$0.value.deprecated }
            .sorted { ($0.value.name.lowercased(), $0.key) < ($1.value.name.lowercased(), $1.key) }
            .map(\.key)
    }

    /// The request format of a model models.dev doesn't know, from its id.
    static func guessedFormat(of id: String) -> WireFormat {
        let id = id.lowercased()
        if id.hasPrefix("claude-") || id.hasPrefix("qwen") || id.hasPrefix("minimax") {
            return .anthropicMessages
        }
        if id.hasPrefix("gemini-") {
            return .gemini
        }
        if id.hasPrefix("gpt-") || id.hasPrefix("grok-") || id.hasPrefix("muse-") {
            return .responses
        }
        return .chatCompletions
    }

    /// What builds the adapter for `entry` from an endpoint, tuned with the
    /// model's metadata.
    ///
    /// - Throws: ``ProviderError/unsupported(_:detail:)`` for a format Go
    ///   doesn't serve.
    static func adapter(
        for entry: ModelEntry, metadata: ModelsDevModel?,
    ) throws -> @Sendable (WireEndpoint) -> any ChatModel {
        switch entry.format {
        case .chatCompletions:
            let field = metadata == nil ? "reasoning_content" : metadata?.interleavedField
            return { ChatCompletionsChatModel(endpoint: $0, reasoningField: field) }
        case .responses:
            return { ResponsesChatModel(endpoint: $0) }
        case .anthropicMessages:
            let maxTokens = metadata?.outputLimit ?? 32_000
            let thinking: AnthropicChatModel.Thinking = entry.ref.model.hasPrefix("claude-") ? .adaptive : .budget
            return { AnthropicChatModel(endpoint: $0, maxTokens: maxTokens, thinking: thinking) }
        case .gemini:
            let thoughts = metadata?.reasoning ?? true
            return { GeminiChatModel(endpoint: $0, includesThoughts: thoughts) }
        case .openRouter:
            throw ProviderError.unsupported(.openCodeGo, detail: "OpenCode Go doesn't serve OpenRouter's format.")
        }
    }
}

/// A wire format adapter in a conversation with a provider that wants a
/// stable session id in a header on every request, and names a page for
/// managing usage when a limit is hit.
struct SessionChatModel: ChatModel {
    let endpoint: WireEndpoint
    let header: String
    let usageURL: URL?
    let build: @Sendable (WireEndpoint) -> any ChatModel

    /// Streams the reply through an adapter whose requests carry the session.
    func reply(
        to conversation: [Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) async throws -> ModelReply {
        var endpoint = endpoint
        let headers = endpoint.headers
        let header = header
        let session = options.sessionID
        endpoint.headers = {
            var all = try await headers()
            all[header] = session
            return all
        }
        do {
            return try await build(endpoint).reply(to: conversation, tools: tools, options: options, onDelta: onDelta)
        } catch ProviderError.usageLimit(let provider, let detail, nil) {
            throw ProviderError.usageLimit(provider, detail: detail, manageURL: usageURL)
        }
    }
}
