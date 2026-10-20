import Foundation
public import OpenRouter

/// OpenRouter: pay as you go with an API key from `OPENROUTER_API_KEY` or
/// the credential store. Lists the catalogue's models that can call tools.
public final class OpenRouterProvider: Provider {
    /// The environment variable read for the API key.
    public static let keyVariable = "OPENROUTER_API_KEY"

    /// Which provider this is.
    public let id = ProviderID.openRouter
    /// Paste an API key.
    public let connectMethod = ConnectMethod.apiKey(
        environment: OpenRouterProvider.keyVariable,
        keyURL: URL(string: "https://openrouter.ai/settings/keys") ?? URL(filePath: "/"),
    )

    private let credentials: CredentialStore
    private let makeClient: @Sendable (String) -> OpenRouterClient
    private let cache = CatalogueCache()

    /// Creates the provider.
    ///
    /// - Parameters:
    ///   - credentials: Where the API key is stored.
    ///   - makeClient: Builds a client for an API key.
    public init(
        credentials: CredentialStore,
        makeClient: @escaping @Sendable (String) -> OpenRouterClient = OpenRouterProvider.client,
    ) {
        self.credentials = credentials
        self.makeClient = makeClient
    }

    /// A client for `apiKey` that names Tag Agent to OpenRouter.
    @Sendable
    public static func client(apiKey: String) -> OpenRouterClient {
        var configuration = OpenRouterClient.Configuration()
        configuration.appTitle = "Tag Agent"
        return OpenRouterClient(apiKey: apiKey, configuration: configuration)
    }

    /// Whether an API key is set.
    public func isConnected() -> Bool {
        apiKey != nil
    }

    /// The catalogue's models that can call tools, fetched once.
    ///
    /// - Throws: ``ProviderError/notConnected(_:)`` without a key, or the
    ///   catalogue request's error.
    public func models() async throws -> [ModelEntry] {
        if let cached = await cache.entries {
            return cached
        }
        let client = try connectedClient()
        let entries = try await client.models.all().compactMap(Self.entry)
        await cache.store(entries)
        return entries
    }

    /// A chat model for `entry`.
    ///
    /// - Throws: ``ProviderError/notConnected(_:)`` without a key.
    public func chatModel(for entry: ModelEntry) throws -> any ChatModel {
        OpenRouterChatModel(client: try connectedClient(), modelID: entry.ref.model)
    }

    private var apiKey: String? {
        credentials.apiKey(for: id, variable: Self.keyVariable)
    }

    private func connectedClient() throws -> OpenRouterClient {
        guard let apiKey else {
            throw ProviderError.notConnected(id)
        }
        return makeClient(apiKey)
    }

    /// The catalogue entry for an OpenRouter model, or `nil` when it can't
    /// call tools (the agent needs them).
    static func entry(_ info: ModelInfo) -> ModelEntry? {
        guard info.supportedParameters.contains("tools") else {
            return nil
        }
        let reasons = info.supportedParameters.contains("reasoning")
        return ModelEntry(
            ref: ModelRef(provider: .openRouter, model: info.id),
            name: displayName(info.name),
            contextLength: info.contextLength,
            pricing: pricing(prompt: info.pricing.prompt, completion: info.pricing.completion),
            reasoningEfforts: reasons ? ["minimal", "low", "medium", "high"] : [],
            format: .openRouter,
        )
    }

    /// Per-token prices as OpenRouter writes them (`"0.00000027"`), per million.
    static func pricing(prompt: String, completion: String) -> Pricing {
        guard let input = Double(prompt), let output = Double(completion) else {
            return .unknown
        }
        if input == 0, output == 0 {
            return .free
        }
        return .perMillion(input: input * 1_000_000, output: output * 1_000_000)
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

/// A catalogue fetched once and kept for the provider's lifetime.
actor CatalogueCache {
    /// The entries, once fetched.
    private(set) var entries: [ModelEntry]?

    /// Keeps `entries`.
    func store(_ entries: [ModelEntry]) {
        self.entries = entries
    }
}
