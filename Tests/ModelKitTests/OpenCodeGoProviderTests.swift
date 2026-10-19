import Foundation
import OpenRouter
import Testing

@testable import ModelKit

struct OpenCodeGoProviderTests {
    static let liveList = #"""
        {"object":"list","data":[{"id":"kimi-k3"},{"id":"claude-haiku-5-5"},{"id":"old-model"},
        {"id":"qwen9-max"},{"id":"gemini-9"},{"id":"grok-9"},{"id":"mystery-free"}]}
        """#

    /// Minimal streams per format, so a reply completes.
    static let replies: [String: String] = [
        "chat/completions": Fixtures.sse([#"{"choices":[{"delta":{"content":"ok"}}]}"#, "[DONE]"]),
        "messages": Fixtures.sse([
            #"{"type":"message_start","message":{"usage":{"input_tokens":1}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"ok"}}"#,
        ]),
        "streamGenerateContent": Fixtures.sse([#"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#]),
    ]

    /// A transport playing models.dev, Go's model list and its endpoints.
    static func transport(listStatus: Int = 200, chatStatus: Int = 200, offline: Bool = false) -> FakeTransport {
        FakeTransport { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasPrefix(ModelsDevCatalogue.sourceURL.absoluteString) {
                return FakeTransport.Answer(status: 200, body: ModelsDevCatalogueTests.json)
            }
            if url.hasSuffix("/v1/models") {
                return offline ? nil : FakeTransport.Answer(status: listStatus, body: liveList)
            }
            let reply = replies.first { url.contains($0.key) }?.value ?? ""
            return FakeTransport.Answer(status: chatStatus, body: chatStatus == 200 ? reply : #"{"error":"Limit"}"#)
        }
    }

    static func provider(_ transport: FakeTransport, key: String? = "go-key") -> OpenCodeGoProvider {
        let directory = FileManager.default.temporaryDirectory.appending(path: "tag-go-\(UUID().uuidString)")
        let environment = key.map { ["OPENCODE_API_KEY": $0] } ?? [:]
        return OpenCodeGoProvider(
            credentials: CredentialStore(directory: directory, environment: environment),
            catalogue: ModelsDevCatalogue(
                cacheURL: directory.appending(path: "cache/models-dev.json"), transport: transport),
            transport: transport)
    }

    @Test func needsAKey() async throws {
        let provider = Self.provider(Self.transport(), key: nil)
        #expect(!provider.isConnected())
        #expect(provider.id == .openCodeGo)
        #expect(
            provider.connectMethod
                == .apiKey(environment: "OPENCODE_API_KEY", keyURL: OpenCodeGoProvider.consoleURL))
        await #expect(throws: ProviderError.notConnected(.openCodeGo)) { try await provider.models() }
        let entry = ModelEntry(
            ref: ModelRef(provider: .openCodeGo, model: "kimi-k3"), name: "K", format: .chatCompletions)
        await #expect(throws: ProviderError.notConnected(.openCodeGo)) { try await provider.chatModel(for: entry) }
    }

    @Test func listsLiveModelsWithModelsDevMetadata() async throws {
        let transport = Self.transport()
        let provider = Self.provider(transport)
        #expect(provider.isConnected())
        let entries = try await provider.models()
        #expect(
            entries.map(\.ref.model) == [
                "kimi-k3", "claude-haiku-5-5", "old-model", "qwen9-max", "gemini-9", "grok-9", "mystery-free",
            ])
        #expect(
            entries.map(\.format) == [
                .chatCompletions, .anthropicMessages, .chatCompletions, .anthropicMessages, .gemini, .responses,
                .chatCompletions,
            ])
        #expect(
            entries[0]
                == ModelEntry(
                    ref: ModelRef(provider: .openCodeGo, model: "kimi-k3"), name: "Kimi K3", contextLength: 1_048_576,
                    pricing: .included, reasoningEfforts: ["max"], format: .chatCompletions))
        #expect(entries[3].name == "qwen9-max")
        #expect(entries[3].pricing == .included)
        #expect(entries[6].pricing == .free)
        let list = try #require(transport.requests.first { $0.url?.path().hasSuffix("/v1/models") == true })
        #expect(list.url?.absoluteString == "https://opencode.ai/inference/go/v1/models")
        #expect(list.value(forHTTPHeaderField: "Authorization") == "Bearer go-key")
        #expect(list.value(forHTTPHeaderField: "User-Agent") == TagUserAgent.value)
    }

    @Test func fallsBackToModelsDevWhenTheListIsUnreachable() async throws {
        let entries = try await Self.provider(Self.transport(offline: true)).models()
        #expect(
            entries.map(\.ref.model) == [
                "beam-free", "claude-haiku-5-5", "gemini-4-argon-contributor", "gpt-6-luna", "kimi-k3",
            ])
        #expect(entries.first?.pricing == .free)
    }

    @Test func reportsAListThatFails() async throws {
        await #expect(throws: ProviderError.signInRequired(.openCodeGo, detail: "The API key was rejected. kimi-k3")) {
            try await Self.provider(FakeTransport(status: 401, body: #"{"message":"kimi-k3"}"#)).models()
        }
        await #expect(throws: ProviderError.unavailable(.openCodeGo, detail: "The model list couldn't be loaded.")) {
            try await Self.provider(FakeTransport { _ in nil }).models()
        }
        await #expect(throws: ProviderError.self) {
            try await Self.provider(FakeTransport(body: "[]")).models()
        }
    }

    @Test(arguments: [
        (WireFormat.chatCompletions, "kimi-k3", "https://opencode.ai/inference/go/openai/v1/chat/completions"),
        (.anthropicMessages, "claude-haiku-5-5", "https://opencode.ai/inference/go/anthropic/v1/messages"),
        (
            .gemini, "gemini-4-argon-contributor",
            "https://opencode.ai/inference/go/google/v1beta/models/gemini-4-argon-contributor:streamGenerateContent?alt=sse"
        ),
    ])
    func talksToEachFormatsEndpointWithTheSession(format: WireFormat, model: String, url: String) async throws {
        let transport = Self.transport()
        let provider = Self.provider(transport)
        let entry = ModelEntry(ref: ModelRef(provider: .openCodeGo, model: model), name: model, format: format)
        let reply = try await provider.chatModel(for: entry)
            .reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
        #expect(reply.message.text == "ok")
        let request = try #require(transport.requests.last)
        #expect(request.url?.absoluteString == url)
        #expect(request.value(forHTTPHeaderField: "x-opencode-session") == "session-1")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == TagUserAgent.value)
        let auth = ["Authorization", "x-api-key", "x-goog-api-key"].compactMap { request.value(forHTTPHeaderField: $0) }
        #expect(auth == [format == .chatCompletions ? "Bearer go-key" : "go-key"])
    }

    @Test func pointsUsageLimitsAtTheConsole() async throws {
        let provider = Self.provider(Self.transport(chatStatus: 429))
        let entry = ModelEntry(
            ref: ModelRef(provider: .openCodeGo, model: "kimi-k3"), name: "K", format: .chatCompletions)
        await #expect(
            throws: ProviderError.usageLimit(.openCodeGo, detail: "Limit", manageURL: OpenCodeGoProvider.consoleURL)
        ) {
            try await provider.chatModel(for: entry).reply(to: [.user("hi")], tools: [], options: Fixtures.options()) {
                _ in
            }
        }
        let other = ModelEntry(ref: ModelRef(provider: .openCodeGo, model: "x"), name: "X", format: .openRouter)
        await #expect(throws: ProviderError.self) { try await provider.chatModel(for: other) }
    }

    @Test func tunesAdaptersWithModelsDevMetadata() throws {
        let haiku = ModelsDevModel(name: "Haiku", outputLimit: 128_000, reasoning: true)
        let entry = ModelEntry(
            ref: ModelRef(provider: .openCodeGo, model: "claude-haiku-5-5"), name: "H", format: .anthropicMessages)
        let endpoint = try Fixtures.endpoint(FakeTransport(body: ""))
        let anthropic = try #require(
            try OpenCodeGoProvider.adapter(for: entry, metadata: haiku)(endpoint) as? AnthropicChatModel)
        #expect(anthropic.maxTokens == 128_000)
        #expect(anthropic.thinking == .adaptive)
        var qwen = entry
        qwen.ref.model = "qwen3.8-max"
        let budget = try #require(
            try OpenCodeGoProvider.adapter(for: qwen, metadata: nil)(endpoint) as? AnthropicChatModel)
        #expect(budget.maxTokens == 32_000)
        #expect(budget.thinking == .budget)
        var chat = entry
        chat.format = .chatCompletions
        let silent = try #require(
            try OpenCodeGoProvider.adapter(for: chat, metadata: haiku)(endpoint) as? ChatCompletionsChatModel)
        #expect(silent.reasoningField == nil)
        var responses = entry
        responses.format = .responses
        #expect(try OpenCodeGoProvider.adapter(for: responses, metadata: nil)(endpoint) is ResponsesChatModel)
        var gemini = entry
        gemini.format = .gemini
        let thinking = try #require(
            try OpenCodeGoProvider.adapter(for: gemini, metadata: ModelsDevModel(name: "G"))(endpoint)
                as? GeminiChatModel)
        #expect(!thinking.includesThoughts)
    }
}
