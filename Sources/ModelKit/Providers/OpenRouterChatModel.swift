import Foundation
public import OpenRouter

/// A ``ChatModel`` backed by OpenRouter, through the OpenRouter SDK.
public struct OpenRouterChatModel: ChatModel {
    private let client: OpenRouterClient
    private let modelID: String

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - client: The OpenRouter client, with the user's API key.
    ///   - modelID: The OpenRouter model id, e.g. `"deepseek/deepseek-v4.1-flash"`.
    public init(client: OpenRouterClient, modelID: String) {
        self.client = client
        self.modelID = modelID
    }

    /// Streams the reply to the conversation and tools from OpenRouter.
    public func reply(
        to conversation: [Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) async throws -> ModelReply {
        let request = Self.request(conversation, tools: tools, model: modelID, options: options)
        var accumulator = ChatStreamAccumulator()
        for try await chunk in Self.chunks(of: request, from: client) {
            accumulator.add(chunk)
            for delta in Self.deltas(in: chunk) {
                onDelta(delta)
            }
        }
        return Self.reply(from: accumulator)
    }

    /// The request for a conversation.
    static func request(
        _ conversation: [Message], tools: [ToolSpec], model: String, options: ReplyOptions
    )
        -> ChatRequest
    {
        let chatTools: [ChatTool] = tools.map {
            .function(name: $0.name, description: $0.description, parameters: $0.parameters)
        }
        var request = ChatRequest(
            messages: cachedMessages(conversation, model: model),
            model: model,
            toolChoice: chatTools.isEmpty ? nil : .auto,
            tools: chatTools.isEmpty ? nil : chatTools,
        )
        request.reasoningEffort = options.reasoningEffort
        request.sessionId = options.sessionID.isEmpty ? nil : String(options.sessionID.prefix(256))
        request.cacheControl = .init(_type: .ephemeral)
        return request
    }

    /// A message as OpenRouter's Chat Completions expects it.
    static func chatMessage(_ message: Message) -> ChatMessage {
        switch message {
        case .system(let text):
            return .system(text)
        case .user(let text):
            return .user(text)
        case .tool(let callID, _, let content):
            return .tool(callID: callID, content: content)
        case .assistant(let assistant):
            let calls = assistant.toolCalls.map { call in
                ChatToolCall(function: .init(arguments: call.arguments, name: call.name), id: call.id, _type: .function)
            }
            var message = ChatAssistantMessage(text: assistant.text, toolCalls: calls)
            message.reasoning = assistant.reasoning
            let details = assistant.replay.filter { $0.format == .openRouter }.compactMap(reasoningDetail)
            message.reasoningDetails = details.isEmpty ? nil : details
            return .assistant(message)
        }
    }

    /// The finished reply: its text, reasoning, tool calls and usage.
    static func reply(from accumulator: ChatStreamAccumulator) -> ModelReply {
        let message = AssistantMessage(
            text: accumulator.text.isEmpty ? nil : accumulator.text,
            reasoning: accumulator.reasoning.isEmpty ? nil : accumulator.reasoning,
            replay: accumulator.reasoningDetails.compactMap(replayItem),
            toolCalls: accumulator.toolCalls.map {
                ToolCall(id: $0.id, name: $0.function.name, arguments: $0.function.arguments)
            },
        )
        let usage = accumulator.usage.map {
            Usage(
                inputTokens: $0.promptTokens, outputTokens: $0.completionTokens, cost: $0.cost,
                cachedInputTokens: $0.promptTokensDetails?.cachedTokens,
                cacheWriteInputTokens: $0.promptTokensDetails?.cacheWriteTokens)
        }
        return ModelReply(message: message, usage: usage)
    }

    /// Sends `request` and decodes the reply's chunks off the caller's actor.
    /// The agent runs on the main actor with the UI, and encoding a long
    /// conversation or decoding every chunk there would hold up typing.
    private static func chunks(
        of request: ChatRequest, from client: OpenRouterClient,
    ) -> AsyncThrowingStream<ChatStreamChunk, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    for try await chunk in try await client.chat.stream(request) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// What a streamed chunk adds: reasoning, text, and the names of tool
    /// calls it starts (a call's first fragment carries its name).
    static func deltas(in chunk: ChatStreamChunk) -> [ReplyDelta] {
        var deltas: [ReplyDelta] = []
        if let reasoning = chunk.reasoningDelta, !reasoning.isEmpty {
            deltas.append(.reasoning(reasoning))
        }
        if let text = chunk.textDelta, !text.isEmpty {
            deltas.append(.text(text))
        }
        for fragment in chunk.choices.first?.delta.toolCalls ?? [] {
            if let name = fragment.function?.name, !name.isEmpty {
                deltas.append(.toolCall(name: name))
            }
        }
        return deltas
    }

    private static func replayItem(_ detail: ReasoningDetail) -> ReplayItem? {
        guard let data = try? JSONEncoder().encode(detail),
            let payload = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return nil
        }
        return ReplayItem(format: .openRouter, payload: payload)
    }

    private static func reasoningDetail(_ item: ReplayItem) -> ReasoningDetail? {
        guard let data = try? JSONEncoder().encode(item.payload) else {
            return nil
        }
        return try? JSONDecoder().decode(ReasoningDetail.self, from: data)
    }
}
