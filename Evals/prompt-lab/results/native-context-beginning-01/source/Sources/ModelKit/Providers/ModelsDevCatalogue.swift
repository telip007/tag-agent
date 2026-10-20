public import Foundation

/// Model metadata from [models.dev](https://models.dev), the open catalogue
/// of models by provider: names, limits, prices, reasoning options and the
/// request format. The JSON is cached in the config directory for a day, and
/// a stale cache stands in when the site can't be reached.
public actor ModelsDevCatalogue {
    /// Where the catalogue comes from.
    public static let sourceURL = URL(validLiteral: "https://models.dev/api.json")
    /// The catalogue in the config directory, shared by the providers that
    /// read it.
    public static let shared = ModelsDevCatalogue()

    private let cacheURL: URL
    private let transport: any HTTPTransport
    private let maxAge: TimeInterval
    private let now: @Sendable () -> Date
    private var loaded: (providers: [String: ModelsDevProvider], fresh: Bool)?

    /// Creates a catalogue.
    ///
    /// - Parameters:
    ///   - cacheURL: The cache file.
    ///   - transport: What fetches the catalogue.
    ///   - maxAge: How long the cache is fresh, in seconds.
    ///   - now: The current time.
    public init(
        cacheURL: URL = ConfigDirectory.url().appending(path: "cache/models-dev.json"),
        transport: any HTTPTransport = URLSessionTransport(),
        maxAge: TimeInterval = 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.cacheURL = cacheURL
        self.transport = transport
        self.maxAge = maxAge
        self.now = now
    }

    /// The metadata of the provider models.dev calls `id` (`"opencode-go"`,
    /// `"openrouter"`), or `nil` when the catalogue can't be read or lacks it.
    ///
    /// - Parameter id: The provider's models.dev id.
    /// - Returns: The provider's metadata.
    public func provider(_ id: String) async -> ModelsDevProvider? {
        await providers()[id]
    }

    private func providers() async -> [String: ModelsDevProvider] {
        if let loaded, loaded.fresh {
            return loaded.providers
        }
        let cached = cachedProviders()
        if let cached, cached.fresh {
            loaded = cached
            return cached.providers
        }
        if let fetched = await fetch() {
            loaded = (fetched, true)
            return fetched
        }
        loaded = cached.map { ($0.providers, false) }
        return cached?.providers ?? [:]
    }

    private func cachedProviders() -> (providers: [String: ModelsDevProvider], fresh: Bool)? {
        guard let data = try? SecureFile.read(cacheURL), let providers = Self.decode(data) else {
            return nil
        }
        let modified = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let fresh = modified.map { now().timeIntervalSince($0) < maxAge } ?? false
        return (providers, fresh)
    }

    private func fetch() async -> [String: ModelsDevProvider]? {
        var request = URLRequest(url: Self.sourceURL)
        request.setValue(TagUserAgent.value, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await transport.data(for: request), response.statusCode == 200,
            let providers = Self.decode(data)
        else {
            return nil
        }
        try? SecureFile.write(data, to: cacheURL)
        return providers
    }

    /// Decodes models.dev's JSON, skipping what doesn't fit.
    static func decode(_ data: Data) -> [String: ModelsDevProvider]? {
        let providers = try? JSONDecoder().decode([String: Lenient<ModelsDevProvider>].self, from: data)
        return providers?.compactMapValues(\.value)
    }
}

/// A provider as models.dev describes it.
public struct ModelsDevProvider: Sendable, Equatable, Decodable {
    /// The AI SDK package that talks to the provider, which tells the
    /// request format of models that don't name their own.
    public var npm: String?
    /// The provider's models by id.
    public var models: [String: ModelsDevModel]

    /// Creates provider metadata.
    ///
    /// - Parameters:
    ///   - npm: The provider's AI SDK package.
    ///   - models: The models by id.
    public init(npm: String? = nil, models: [String: ModelsDevModel]) {
        self.npm = npm
        self.models = models
    }

    private enum CodingKeys: String, CodingKey {
        case npm, models
    }

    /// Decodes the provider, dropping models that don't decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        npm = try? container.decodeIfPresent(String.self, forKey: .npm)
        let models = (try? container.decode([String: Lenient<ModelsDevModel>].self, forKey: .models)) ?? [:]
        self.models = models.compactMapValues(\.value)
    }

    /// The request format of the model `id`: from its AI SDK package, or the
    /// provider's.
    ///
    /// - Parameter id: The model's id.
    /// - Returns: The format, or `nil` when the model isn't listed.
    public func format(of id: String) -> WireFormat? {
        guard let model = models[id] else {
            return nil
        }
        return switch model.npm ?? npm {
        case "@ai-sdk/anthropic": .anthropicMessages
        case "@ai-sdk/google": .gemini
        case "@ai-sdk/openai": .responses
        default: .chatCompletions
        }
    }
}

/// A value that decodes to `nil` instead of failing.
struct Lenient<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
