public import Foundation
import OpenRouter
import Synchronization

/// OpenAI models on the user's ChatGPT plan, through Sign in with ChatGPT
/// and the public `api.openai.com/v1` Responses API.
public final class CodexProvider: Provider {
    /// ``ProviderID/codex``.
    public let id = ProviderID.codex
    /// ``ConnectMethod/browser``: the user signs in with ChatGPT.
    public let connectMethod = ConnectMethod.browser
    /// The tokens of the signed-in account.
    public let session: ChatGPTSession

    private let store: CredentialStore
    private let transport: any HTTPTransport
    private let flow: ChatGPTSignIn
    private let cachedModels = Mutex<[ModelEntry]?>(nil)

    private static let modelsURL = URL(string: "https://api.openai.com/v1/models")
    private static let responsesURL = URL(string: "https://api.openai.com/v1/responses")

    /// Creates the provider.
    ///
    /// - Parameters:
    ///   - store: Where the ChatGPT account is kept.
    ///   - transport: What sends requests.
    ///   - openBrowser: Opens the sign-in page; the system browser by default.
    ///   - now: The clock, for token expiry.
    public init(
        store: CredentialStore,
        transport: any HTTPTransport = URLSessionTransport(),
        openBrowser: @escaping @Sendable (URL) throws -> Void = ChatGPTSignIn.openInSystemBrowser,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.store = store
        self.transport = transport
        self.flow = ChatGPTSignIn(store: store, transport: transport, openBrowser: openBrowser, now: now)
        self.session = ChatGPTSession(store: store, transport: transport, now: now)
    }

    /// Creates the provider from its parts, for tests and custom flows.
    ///
    /// - Parameters:
    ///   - store: Where the ChatGPT account is kept.
    ///   - transport: What sends requests.
    ///   - signIn: The browser sign-in.
    ///   - session: The token session.
    public init(store: CredentialStore, transport: any HTTPTransport, signIn: ChatGPTSignIn, session: ChatGPTSession) {
        self.store = store
        self.transport = transport
        self.flow = signIn
        self.session = session
    }

    /// Whether a ChatGPT account is stored.
    public func isConnected() -> Bool {
        store.load().chatGPT != nil
    }

    /// The signed-in account, if any.
    public func account() -> ChatGPTAccount? {
        store.load().chatGPT
    }

    /// Signs in with ChatGPT in the browser and forgets the model list, which
    /// depends on the account.
    ///
    /// - Parameter forceConsent: Asks the user to approve plan usage again.
    /// - Returns: The signed-in account.
    /// - Throws: As ``ChatGPTSignIn/signIn(forceConsent:)``.
    public func signIn(forceConsent: Bool = false) async throws -> ChatGPTAccount {
        let account = try await flow.signIn(forceConsent: forceConsent)
        cachedModels.withLock { $0 = nil }
        return account
    }

    /// Signs out, revoking the session.
    ///
    /// - Returns: Whether the server confirmed the revocation.
    /// - Throws: File system errors.
    @discardableResult
    public func signOut() async throws -> Bool {
        cachedModels.withLock { $0 = nil }
        return try await session.signOut()
    }

    /// The account's models, in the server's order, fetched once.
    ///
    /// - Returns: The models with `visibility: "list"`.
    /// - Throws: ``ProviderError/notConnected(_:)`` without a sign-in, or a
    ///   ``ProviderError`` for the request.
    public func models() async throws -> [ModelEntry] {
        if let cached = cachedModels.withLock({ $0 }) {
            return cached
        }
        guard let url = Self.modelsURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await session.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(TagUserAgent.value, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let body = String(bytes: data, encoding: .utf8) ?? ""
            throw ResponsesError.from(status: response.statusCode, body: body, provider: .codex)
        }
        let models = try Self.entries(from: data)
        cachedModels.withLock { $0 = models }
        return models
    }

    /// A Responses model on `api.openai.com` authorized with the account's
    /// token, refreshed per request as needed.
    ///
    /// - Parameter entry: One of ``models()``.
    /// - Returns: The chat model.
    /// - Throws: ``ProviderError/notConnected(_:)`` without a sign-in,
    ///   ``ProviderError/unknownModel(_:)`` for another provider's entry.
    public func chatModel(for entry: ModelEntry) throws -> any ChatModel {
        guard entry.ref.provider == .codex else {
            throw ProviderError.unknownModel(entry.ref)
        }
        guard isConnected() else {
            throw ProviderError.notConnected(.codex)
        }
        guard let url = Self.responsesURL else {
            throw URLError(.badURL)
        }
        let session = session
        let endpoint = WireEndpoint(
            url: url, model: entry.ref.model, provider: .codex,
            headers: { ["Authorization": "Bearer \(try await session.accessToken())"] }, transport: transport)
        return ResponsesChatModel(endpoint: endpoint, includeEncryptedReasoning: !entry.reasoningEfforts.isEmpty)
    }

    /// The catalogue entries in a `/v1/models` response.
    ///
    /// - Throws: ``ProviderError/malformedResponse(_:detail:)`` without a
    ///   `models` array.
    static func entries(from data: Data) throws -> [ModelEntry] {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data), let models = json["models"]?.arrayValue
        else {
            throw ProviderError.malformedResponse(.codex, detail: "The model list had no models.")
        }
        return models.compactMap { model in
            guard model["visibility"]?.stringValue == "list", let slug = model["slug"]?.stringValue else {
                return nil
            }
            return ModelEntry(
                ref: ModelRef(provider: .codex, model: slug), name: model["display_name"]?.stringValue ?? slug,
                contextLength: contextLength(of: model), pricing: .included,
                reasoningEfforts: reasoningEfforts(of: model, slug: slug), format: .responses)
        }
    }

    private static func contextLength(of model: JSONValue) -> Int? {
        ["context_window", "context_length", "max_context_window"].lazy.compactMap { model[$0]?.intValue }.first
    }

    /// The listed efforts (strings, or objects with an `effort`), else the
    /// usual three for OpenAI's reasoning families.
    private static func reasoningEfforts(of model: JSONValue, slug: String) -> [String] {
        let listed = ["supported_reasoning_levels", "supported_reasoning_efforts", "reasoning_efforts"]
            .lazy.compactMap { model[$0]?.arrayValue }.first
        if let listed {
            return listed.compactMap { $0.stringValue ?? $0["effort"]?.stringValue }
        }
        return slug.hasPrefix("gpt-") || slug.hasPrefix("o") ? ["low", "medium", "high"] : []
    }
}
