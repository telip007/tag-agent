public import Foundation
import OpenRouter

/// The OpenCode Go subscription: open coding models (and a few others)
/// behind one API key, each served in its own request format.
public struct OpenCodeGoProvider: Provider {
    /// The console, where the user gets an API key and tracks usage.
    public static let consoleURL = URL(validLiteral: "https://opencode.ai/console")
    /// Where Go's endpoints live.
    public static let defaultBaseURL = URL(validLiteral: "https://opencode.ai/inference/go")
    /// The environment variable that holds the API key.
    public static let environmentVariable = "OPENCODE_API_KEY"
    /// The header carrying a stable id per conversation, which Go asks for
    /// to route requests and cache prompts.
    static let sessionHeader = "x-opencode-session"
    /// models.dev's id for Go.
    static let modelsDevID = "opencode-go"

    private let credentials: CredentialStore
    private let catalogue: ModelsDevCatalogue
    private let transport: any HTTPTransport
    private let baseURL: URL

    /// Creates the provider.
    ///
    /// - Parameters:
    ///   - credentials: Where the API key is stored.
    ///   - catalogue: The models.dev metadata.
    ///   - transport: What sends the requests.
    ///   - baseURL: Where Go's endpoints live.
    public init(
        credentials: CredentialStore = CredentialStore(),
        catalogue: ModelsDevCatalogue = .shared,
        transport: any HTTPTransport = URLSessionTransport(),
        baseURL: URL = defaultBaseURL,
    ) {
        self.credentials = credentials
        self.catalogue = catalogue
        self.transport = transport
        self.baseURL = baseURL
    }

    /// ``ProviderID/openCodeGo``.
    public var id: ProviderID { .openCodeGo }

    /// An API key from the console, or `OPENCODE_API_KEY`.
    public var connectMethod: ConnectMethod {
        .apiKey(environment: Self.environmentVariable, keyURL: Self.consoleURL)
    }

    /// Whether an API key is stored or in the environment.
    public func isConnected() -> Bool {
        apiKey() != nil
    }

    /// The models Go serves now, named and described by models.dev. Without
    /// the live list, models.dev's current models stand in.
    ///
    /// - Throws: ``ProviderError/notConnected(_:)`` without a key, the
    ///   API's error, or ``ProviderError/unavailable(_:detail:)`` when no
    ///   list can be read.
    public func models() async throws -> [ModelEntry] {
        guard let key = apiKey() else {
            throw ProviderError.notConnected(id)
        }
        async let metadata = catalogue.provider(Self.modelsDevID)
        let live: [String]?
        do {
            live = try await liveModelIDs(key: key)
        } catch let error as ProviderError {
            throw error
        } catch {
            live = nil
        }
        let known = await metadata
        guard let ids = live ?? known.map(Self.currentIDs) else {
            throw ProviderError.unavailable(id, detail: "The model list couldn't be loaded.")
        }
        return Self.entries(ids: ids, metadata: known)
    }

    /// A chat model for `entry`, in the entry's request format.
    ///
    /// - Throws: ``ProviderError/notConnected(_:)`` without a key.
    public func chatModel(for entry: ModelEntry) async throws -> any ChatModel {
        guard let key = apiKey() else {
            throw ProviderError.notConnected(id)
        }
        let model = await catalogue.provider(Self.modelsDevID)?.models[entry.ref.model]
        let endpoint = try endpoint(for: entry, key: key)
        let build = try Self.adapter(for: entry, metadata: model)
        return SessionChatModel(
            endpoint: endpoint, header: Self.sessionHeader, usageURL: Self.consoleURL, build: build)
    }

    private func apiKey() -> String? {
        credentials.apiKey(for: id, variable: Self.environmentVariable)
    }

    private func liveModelIDs(key: String) async throws -> [String] {
        var request = URLRequest(url: baseURL.appending(path: "v1/models"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(TagUserAgent.value, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 else {
            let body = String(bytes: data, encoding: .utf8) ?? ""
            throw ProviderError.from(status: response.statusCode, body: body, provider: id)
        }
        guard let models = JSONValue.parse(data)?["data"]?.arrayValue else {
            throw ProviderError.malformedResponse(id, detail: "The model list wasn't a list.")
        }
        return models.compactMap { $0["id"]?.stringValue }
    }

    private func endpoint(for entry: ModelEntry, key: String) throws -> WireEndpoint {
        let model = entry.ref.model
        let (url, auth): (URL, [String: String]) =
            switch entry.format {
            case .chatCompletions:
                (baseURL.appending(path: "openai/v1/chat/completions"), ["Authorization": "Bearer \(key)"])
            case .responses:
                (baseURL.appending(path: "openai/v1/responses"), ["Authorization": "Bearer \(key)"])
            case .anthropicMessages:
                (baseURL.appending(path: "anthropic/v1/messages"), ["x-api-key": key])
            case .gemini:
                (
                    baseURL.appending(path: "google/v1beta/models/\(model):streamGenerateContent")
                        .appending(queryItems: [URLQueryItem(name: "alt", value: "sse")]),
                    ["x-goog-api-key": key]
                )
            case .openRouter:
                throw ProviderError.unsupported(id, detail: "\(model) isn't served in a format OpenCode Go speaks.")
            }
        return WireEndpoint(url: url, model: model, provider: id, headers: { auth }, transport: transport)
    }
}
