public import Foundation

/// The providers Tag Agent can talk to.
public enum ProviderID: String, Sendable, Codable, CaseIterable, Comparable {
    /// OpenRouter, pay as you go with an API key.
    case openRouter = "openrouter"
    /// OpenAI models on the user's ChatGPT plan (Codex), through Sign in
    /// with ChatGPT.
    case codex
    /// The OpenCode Go subscription, with an API key.
    case openCodeGo = "opencode-go"

    /// The name shown to the user.
    public var displayName: String {
        switch self {
        case .openRouter: "OpenRouter"
        case .codex: "ChatGPT (Codex)"
        case .openCodeGo: "OpenCode Go"
        }
    }

    /// Short names accepted in `/model <provider>/<model>`.
    public var aliases: [String] {
        switch self {
        case .openRouter: ["openrouter", "or"]
        case .codex: ["codex", "chatgpt", "openai"]
        case .openCodeGo: ["opencode-go", "go", "opencode"]
        }
    }

    /// Finds a provider by name or alias, ignoring case.
    public init?(alias: String) {
        let alias = alias.lowercased()
        guard let match = Self.allCases.first(where: { $0.aliases.contains(alias) }) else {
            return nil
        }
        self = match
    }

    /// Orders providers as ``allCases`` lists them.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let order = allCases
        return order.firstIndex(of: lhs) ?? 0 < order.firstIndex(of: rhs) ?? 0
    }
}

/// A model at a provider: `codex/gpt-6.1-sol`, `openrouter/deepseek/deepseek-v4.1-flash`.
public struct ModelRef: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The provider serving the model.
    public var provider: ProviderID
    /// The provider's id for the model; it may contain `/`.
    public var model: String

    /// Creates a reference.
    ///
    /// - Parameters:
    ///   - provider: The provider serving the model.
    ///   - model: The provider's id for the model.
    public init(provider: ProviderID, model: String) {
        self.provider = provider
        self.model = model
    }

    /// Parses `provider/model`, splitting at the first `/` and accepting
    /// provider aliases. `nil` when the provider is unknown or the model empty.
    public init?(parsing text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let slash = text.firstIndex(of: "/"),
            let provider = ProviderID(alias: String(text[..<slash]))
        else {
            return nil
        }
        let model = String(text[text.index(after: slash)...])
        guard !model.isEmpty else {
            return nil
        }
        self.init(provider: provider, model: model)
    }

    /// `provider/model`.
    public var description: String {
        "\(provider.rawValue)/\(model)"
    }
}

/// The request format a model is served in.
public enum WireFormat: String, Sendable, Codable, CaseIterable {
    /// OpenAI-compatible Chat Completions.
    case chatCompletions = "chat-completions"
    /// OpenAI Responses.
    case responses
    /// Anthropic Messages.
    case anthropicMessages = "anthropic-messages"
    /// Google Gemini `generateContent`.
    case gemini
    /// OpenRouter's Chat Completions through the OpenRouter SDK.
    case openRouter = "openrouter"
}

/// What a model costs the user.
public enum Pricing: Sendable, Equatable, Codable {
    /// Paid for by a subscription the user has.
    case included
    /// Free of charge.
    case free
    /// Pay as you go, in US dollars per million input and output tokens.
    case perMillion(input: Double, output: Double)
    /// Not known.
    case unknown
}

/// A model the user can pick, as a provider's catalogue lists it.
public struct ModelEntry: Sendable, Equatable, Identifiable, Codable {
    /// Where the model is and its id there.
    public var ref: ModelRef
    /// The name to show, e.g. `"GPT-6.1 Sol"`.
    public var name: String
    /// The context window in tokens, when known.
    public var contextLength: Int?
    /// What it costs.
    public var pricing: Pricing
    /// The reasoning efforts the model accepts, mildest first; empty when it
    /// can't be told how hard to think.
    public var reasoningEfforts: [String]
    /// The request format the model is served in.
    public var format: WireFormat

    /// Creates a catalogue entry.
    ///
    /// - Parameters:
    ///   - ref: Where the model is and its id there.
    ///   - name: The name to show.
    ///   - contextLength: The context window in tokens.
    ///   - pricing: What it costs.
    ///   - reasoningEfforts: The reasoning efforts it accepts.
    ///   - format: The request format it is served in.
    public init(
        ref: ModelRef,
        name: String,
        contextLength: Int? = nil,
        pricing: Pricing = .unknown,
        reasoningEfforts: [String] = [],
        format: WireFormat,
    ) {
        self.ref = ref
        self.name = name
        self.contextLength = contextLength
        self.pricing = pricing
        self.reasoningEfforts = reasoningEfforts
        self.format = format
    }

    /// The model's reference.
    public var id: ModelRef { ref }
}

/// How the user connects a provider.
public enum ConnectMethod: Sendable, Equatable {
    /// Paste an API key, read from the environment variable `environment`
    /// when set. `keyURL` is where the user gets one.
    case apiKey(environment: String, keyURL: URL)
    /// Sign in with a browser.
    case browser
}

/// A provider Tag Agent can list models from and chat with.
public protocol Provider: Sendable {
    /// Which provider this is.
    var id: ProviderID { get }
    /// How the user connects it.
    var connectMethod: ConnectMethod { get }

    /// Whether credentials for the provider are stored or in the environment.
    func isConnected() async -> Bool

    /// The models the user can pick, in the provider's order.
    ///
    /// - Throws: A ``ProviderError`` when the provider isn't connected or
    ///   the catalogue can't be read.
    func models() async throws -> [ModelEntry]

    /// A chat model for `entry`, one of this provider's ``models()``.
    ///
    /// - Throws: ``ProviderError/notConnected(_:)`` without credentials.
    func chatModel(for entry: ModelEntry) async throws -> any ChatModel
}
