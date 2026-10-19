import Foundation
import ModelKit

@testable import TagKit

/// A provider with a fixed catalogue, connected always or once an API key
/// is stored for it.
struct FakeProvider: Provider {
    let id: ProviderID
    var connectMethod: ConnectMethod = .apiKey(
        environment: "FAKE_KEY", keyURL: URL(string: "https://example.com/keys") ?? URL(filePath: "/"))
    var entries: [ModelEntry] = []
    var failure: ProviderError?
    var alwaysConnected = true
    var credentials: CredentialStore?

    func isConnected() -> Bool {
        alwaysConnected || credentials?.apiKey(for: id, variable: nil) != nil
    }

    func models() throws -> [ModelEntry] {
        guard isConnected() else {
            throw ProviderError.notConnected(id)
        }
        if let failure {
            throw failure
        }
        return entries
    }

    func chatModel(for entry: ModelEntry) throws -> any ModelKit.ChatModel {
        guard entries.contains(entry) else {
            throw ProviderError.unknownModel(entry.ref)
        }
        return SilentModel()
    }
}

/// A chat model that never answers.
struct SilentModel: ModelKit.ChatModel {
    func reply(
        to conversation: [ModelKit.Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        onDelta: (ModelKit.ReplyDelta) -> Void,
    ) throws -> ModelKit.ModelReply {
        throw CancellationError()
    }
}

/// Catalogue entries for tests.
enum Models {
    static let codex = ModelEntry(
        ref: ModelRef(provider: .codex, model: "gpt-5.5-codex"), name: "GPT-5.5 Codex", contextLength: 400_000,
        pricing: .included, reasoningEfforts: ["low", "medium", "high"], format: .responses)
    static let codexMini = ModelEntry(
        ref: ModelRef(provider: .codex, model: "gpt-5.5-mini"), name: "GPT-5.5 mini", contextLength: 400_000,
        pricing: .included, reasoningEfforts: ["minimal", "low", "high", "xhigh"], format: .responses)
    static let kimi = ModelEntry(
        ref: ModelRef(provider: .openCodeGo, model: "kimi-k3"), name: "Kimi K3", contextLength: 256_000,
        pricing: .included, format: .chatCompletions)
    static let gptRouter = ModelEntry(
        ref: ModelRef(provider: .openRouter, model: "openai/gpt-5.5"), name: "GPT-5.5", contextLength: 400_000,
        pricing: .perMillion(input: 1.25, output: 10), reasoningEfforts: ["low", "medium", "high"],
        format: .openRouter)
    static let deepseek = ModelEntry(
        ref: ModelRef(provider: .openRouter, model: "deepseek/deepseek-v4.1-flash"), name: "DeepSeek V4.1 Flash",
        contextLength: 1_000_000, pricing: .free, format: .openRouter)

    static let all = [codex, codexMini, kimi, gptRouter, deepseek]

    static var catalogue: Catalogue {
        var catalogue = Catalogue()
        catalogue.entries = all
        return catalogue
    }

    /// A registry of the three providers with ``all`` split between them.
    static func registry(credentials: CredentialStore? = nil, connected: Bool = true) -> ProviderRegistry {
        ProviderRegistry(providers: [
            FakeProvider(
                id: .codex, connectMethod: .browser, entries: [codex, codexMini], alwaysConnected: connected,
                credentials: credentials),
            FakeProvider(id: .openCodeGo, entries: [kimi], alwaysConnected: connected, credentials: credentials),
            FakeProvider(
                id: .openRouter, entries: [gptRouter, deepseek], alwaysConnected: connected,
                credentials: credentials),
        ])
    }
}

/// A fresh config directory under the temporary directory.
func temporaryConfigDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(
        path: "tag-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// A selection over ``Models/registry(credentials:connected:)`` with its
/// settings and credentials in `directory`.
@MainActor
func makeSelection(
    directory: URL = temporaryConfigDirectory(),
    connected: Bool = true,
    signIn: (@MainActor (ProviderID) async throws -> Void)? = nil,
) -> ModelSelection {
    let credentials = CredentialStore(directory: directory, environment: [:])
    return ModelSelection(
        registry: Models.registry(credentials: credentials, connected: connected),
        settings: SettingsStore(directory: directory),
        credentials: credentials,
        signIn: signIn,
    )
}

/// The providers a fake sign-in was asked for.
@MainActor
final class SignIns {
    var providers: [ProviderID] = []
}
