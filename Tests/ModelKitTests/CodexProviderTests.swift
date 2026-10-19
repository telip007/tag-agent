import Foundation
import Testing

@testable import ModelKit

struct CodexProviderTests {
    private static let catalogue = """
        {"models": [
          {"slug": "gpt-6.1-sol", "display_name": "GPT-6.1 Sol", "visibility": "list", "context_window": 400000,
           "supported_reasoning_levels": [{"effort": "low"}, {"effort": "high"}]},
          {"slug": "hidden", "display_name": "Hidden", "visibility": "hide"},
          {"slug": "o9", "visibility": "list"},
          {"slug": "codex-mini", "display_name": "Codex Mini", "visibility": "list", "reasoning_efforts": ["medium"]},
          {"slug": "whisper", "visibility": "list"}
        ]}
        """

    private static func provider(_ transport: CodexTestTransport, signedIn: Bool = true) throws -> CodexProvider {
        let store = CodexFixtures.store()
        if signedIn {
            try store.update { $0.chatGPT = CodexFixtures.account(expiresAt: .now + 3600) }
        }
        return CodexProvider(store: store, transport: transport, openBrowser: { _ in })
    }

    @Test func describesItself() throws {
        let provider = try Self.provider(CodexTestTransport(body: ""), signedIn: false)
        #expect(provider.id == .codex)
        #expect(provider.connectMethod == .browser)
    }

    @Test func isConnectedWithAStoredAccount() throws {
        #expect(try !Self.provider(CodexTestTransport(body: ""), signedIn: false).isConnected())
        let provider = try Self.provider(CodexTestTransport(body: ""))
        #expect(provider.isConnected())
        #expect(provider.account()?.subject == "user-1")
    }

    @Test func listsTheAccountsModelsOnce() async throws {
        let transport = CodexTestTransport(body: Self.catalogue)
        let provider = try Self.provider(transport)
        let models = try await provider.models()
        #expect(try await provider.models() == models)
        #expect(transport.requests.count == 1)
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-0")
        #expect(models.map(\.ref.model) == ["gpt-6.1-sol", "o9", "codex-mini", "whisper"])
        #expect(models.map(\.name) == ["GPT-6.1 Sol", "o9", "Codex Mini", "whisper"])
        #expect(models.map(\.reasoningEfforts) == [["low", "high"], ["low", "medium", "high"], ["medium"], []])
        #expect(models.first?.contextLength == 400_000)
        #expect(models.allSatisfy { $0.pricing == .included && $0.format == .responses })
    }

    @Test func reportsCatalogueFailures() async throws {
        await #expect(throws: ProviderError.signInRequired(.codex, detail: "Expired.")) {
            _ = try await Self.provider(CodexTestTransport(status: 401, body: #"{"detail":"Expired."}"#)).models()
        }
        await #expect(throws: ProviderError.malformedResponse(.codex, detail: "The model list had no models.")) {
            _ = try await Self.provider(CodexTestTransport(body: #"{"data":[]}"#)).models()
        }
        await #expect(throws: ProviderError.notConnected(.codex)) {
            _ = try await Self.provider(CodexTestTransport(body: ""), signedIn: false).models()
        }
    }

    @Test func chatsThroughTheResponsesAPIWithTheAccountsToken() async throws {
        let transport = CodexTestTransport(body: CodexFixtures.sse([#"{"type":"response.completed","response":{}}"#]))
        let provider = try Self.provider(transport)
        let entry = ModelEntry(
            ref: ModelRef(provider: .codex, model: "gpt-6.1-sol"), name: "GPT-6.1 Sol", reasoningEfforts: ["low"],
            format: .responses)
        let model = try #require(try provider.chatModel(for: entry) as? ResponsesChatModel)
        #expect(model.includeEncryptedReasoning)
        _ = try await model.reply(to: [.user("Hi")], tools: [], options: ReplyOptions(sessionID: "s")) { _ in }
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-0")
        #expect(CodexFixtures.json(request)["model"] as? String == "gpt-6.1-sol")
        #expect(CodexFixtures.json(request)["include"] as? [String] == ["reasoning.encrypted_content"])
    }

    @Test func refusesOtherProvidersModelsAndMissingSignIns() throws {
        let other = ModelEntry(ref: ModelRef(provider: .openRouter, model: "x"), name: "X", format: .openRouter)
        #expect(throws: ProviderError.unknownModel(other.ref)) {
            _ = try Self.provider(CodexTestTransport(body: "")).chatModel(for: other)
        }
        let entry = ModelEntry(ref: ModelRef(provider: .codex, model: "x"), name: "X", format: .responses)
        #expect(throws: ProviderError.notConnected(.codex)) {
            _ = try Self.provider(CodexTestTransport(body: ""), signedIn: false).chatModel(for: entry)
        }
    }

    @Test func forgetsTheModelsOnSignOut() async throws {
        let transport = CodexTestTransport { request in
            switch request.url?.path() {
            case "/v1/models": .reply(status: 200, body: Self.catalogue)
            case "/.well-known/openid-configuration":
                .reply(status: 200, body: #"{"revocation_endpoint":"https://auth.openai.com/oauth/revoke"}"#)
            default: .reply(status: 200, body: "")
            }
        }
        let provider = try Self.provider(transport)
        _ = try await provider.models()
        #expect(try await provider.signOut())
        #expect(!provider.isConnected())
        await #expect(throws: ProviderError.notConnected(.codex)) {
            _ = try await provider.models()
        }
    }

    @Test func signsInThroughTheBrowserFlow() async throws {
        let store = CodexFixtures.store()
        let flow = ChatGPTSignIn(
            store: store, transport: CodexTestTransport(body: ""), openBrowser: { _ in }, timeout: .milliseconds(50),
            port: 0)
        let provider = CodexProvider(
            store: store, transport: CodexTestTransport(body: ""), signIn: flow,
            session: ChatGPTSession(store: store))
        await #expect(throws: ChatGPTSignInError.timedOut) {
            _ = try await provider.signIn()
        }
    }
}
