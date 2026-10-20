import Foundation
public import ModelKit
public import Observation

/// Which model the session uses, the models it can switch to, and the
/// providers the user connected.
///
/// The catalogue loads in the background (``load()``); until it has, ``catalogue``
/// is `nil`. Choosing a model (``select(_:effort:)``) builds the provider's chat
/// model, makes it ``current`` and remembers it, with its reasoning effort,
/// for the next session (``restoreLastModel()``).
@MainActor
@Observable
public final class ModelSelection {
    /// The providers and their catalogues.
    @ObservationIgnored public let registry: ProviderRegistry
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let credentials: CredentialStore
    @ObservationIgnored private let signInAction: (@MainActor (ProviderID) async throws -> Void)?

    /// The model in use, once one is chosen.
    public private(set) var current: ActiveModel?
    /// The models of the connected providers; `nil` until the first load ends.
    public private(set) var catalogue: Catalogue?
    /// Whether a catalogue load is running.
    public private(set) var isLoading = false
    /// The providers with credentials, as of the last load.
    public private(set) var connected: Set<ProviderID> = []
    /// Recently used models, newest first.
    public private(set) var recent: [ModelRef] = []
    /// Whether the one-time "You're using your ChatGPT plan" notice is due.
    public private(set) var isChatGPTWelcomeDue = false

    /// Creates a selection with nothing chosen yet.
    ///
    /// - Parameters:
    ///   - registry: The providers.
    ///   - settings: Where the last model, its effort and the recent models are kept.
    ///   - credentials: Where pasted API keys are stored.
    ///   - signIn: Runs a provider's browser sign-in, returning once signed in.
    ///     Without it, signing in fails.
    public init(
        registry: ProviderRegistry,
        settings: SettingsStore = SettingsStore(),
        credentials: CredentialStore = CredentialStore(),
        signIn: (@MainActor (ProviderID) async throws -> Void)? = nil,
    ) {
        self.registry = registry
        self.settings = settings
        self.credentials = credentials
        self.signInAction = signIn
        recent = settings.load().recentModels
    }

    /// Reads which providers are connected and the models they list.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        connected = Set(await registry.connected())
        catalogue = await registry.catalogue()
    }

    /// Makes the last model used, with its effort, the current one.
    ///
    /// - Returns: `false` when no model was used yet or it can't be used now.
    public func restoreLastModel() async -> Bool {
        guard let ref = settings.load().lastModel else {
            return false
        }
        var entry = catalogue?.entries.first { $0.ref == ref }
        if entry == nil {
            entry = try? await registry.entry(for: ref)
        }
        guard let entry else {
            return false
        }
        do {
            try await select(entry, effort: effort(for: entry))
            return true
        } catch {
            return false
        }
    }

    /// Makes `entry` the current model and remembers it for the next session.
    ///
    /// - Throws: The provider's error when it can't make a chat model.
    public func select(_ entry: ModelEntry, effort: String?) async throws {
        guard let provider = registry.provider(entry.ref.provider) else {
            throw ProviderError.unknownModel(entry.ref)
        }
        let chatModel = try await provider.chatModel(for: entry)
        let effort = effort.flatMap { entry.reasoningEfforts.contains($0) ? $0 : nil }
        current = ActiveModel(entry: entry, chatModel: chatModel, effort: effort)
        let stored = try? settings.update { settings in
            settings.use(entry.ref, effort: effort)
            return settings
        }
        let remembered = stored ?? settings.load()
        recent = remembered.recentModels
        isChatGPTWelcomeDue = entry.ref.provider == .codex && !remembered.chatGPTWelcomeShown
    }

    /// The effort to offer for `entry`: the one chosen last for it, else
    /// `medium`, else the middle one; `nil` when it takes none.
    public func effort(for entry: ModelEntry) -> String? {
        let efforts = entry.reasoningEfforts
        if let remembered = settings.load().effort(for: entry.ref), efforts.contains(remembered) {
            return remembered
        }
        return Self.defaultEffort(of: efforts)
    }

    /// `medium` when offered, else the middle effort.
    static func defaultEffort(of efforts: [String]) -> String? {
        guard !efforts.isEmpty else {
            return nil
        }
        return efforts.contains("medium") ? "medium" : efforts[efforts.count / 2]
    }

    /// Switches to the model `text` names exactly (`codex/gpt-6.1-sol`).
    ///
    /// - Returns: The model switched to, or `nil` when no model matches or it
    ///   couldn't be used; the picker then opens with `text` as its search.
    public func quickSwitch(_ text: String) async -> ModelEntry? {
        guard let ref = ModelRef(parsing: text) else {
            return nil
        }
        if catalogue == nil {
            await load()
        }
        let model = ref.model.lowercased()
        guard
            let entry = catalogue?.entries.first(where: {
                $0.ref.provider == ref.provider && $0.ref.model.lowercased() == model
            }),
            (try? await select(entry, effort: effort(for: entry))) != nil
        else {
            return nil
        }
        return entry
    }

    /// Records that the ChatGPT plan notice was shown, so it isn't again.
    public func dismissChatGPTWelcome() {
        isChatGPTWelcomeDue = false
        _ = try? settings.update { $0.chatGPTWelcomeShown = true }
    }
}

extension ModelSelection {
    /// Stores an API key for `provider`, then reloads the catalogue.
    ///
    /// - Throws: File system errors.
    public func saveAPIKey(_ key: String, for provider: ProviderID) async throws {
        try credentials.setAPIKey(key, for: provider)
        await load()
    }

    /// Runs `provider`'s browser sign-in, then reloads the catalogue.
    ///
    /// - Throws: The sign-in's error, or `CancellationError`.
    public func signIn(_ provider: ProviderID) async throws {
        guard let signInAction else {
            throw SignInUnavailable()
        }
        try await signInAction(provider)
        await load()
    }
}

/// The sign-in a ``ModelSelection`` gets when none is wired up.
struct SignInUnavailable: LocalizedError {
    var errorDescription: String? { "Signing in isn't available in this build." }
}
