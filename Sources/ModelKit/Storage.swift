public import Foundation

/// Where Tag Agent keeps its settings and credentials:
/// `$TAG_CONFIG_DIR`, else `$XDG_CONFIG_HOME/tag`, else `~/.config/tag`.
public enum ConfigDirectory {
    /// The directory for the given environment.
    ///
    /// - Parameter environment: The process environment.
    /// - Returns: The config directory's URL.
    public static func url(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["TAG_CONFIG_DIR"], !custom.isEmpty {
            return URL(filePath: custom, directoryHint: .isDirectory)
        }
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(filePath: xdg, directoryHint: .isDirectory).appending(path: "tag", directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/tag", directoryHint: .isDirectory)
    }
}

/// Reads and writes files only the user can read: the directory is created
/// `0700`, files are written whole to a temporary `0600` file and renamed
/// into place, so a crash never leaves half a file.
public enum SecureFile {
    /// Writes `data` to `url` atomically with owner-only permissions.
    ///
    /// - Throws: File system errors.
    public static func write(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString)")
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        do {
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    /// The contents of `url`, or `nil` when there is no such file.
    ///
    /// - Throws: File system errors other than a missing file.
    public static func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }
}

/// A JSON file of a `Codable` value, read and written whole. Changes hold a
/// ``FileLock`` beside the file, so two threads or two Tag processes
/// changing it at once don't lose either change.
/// A missing or unreadable file reads as `Value()`.
public final class JSONFileStore<Value: Codable & Sendable>: Sendable {
    /// The file.
    public let url: URL
    private let fileLock: FileLock
    private let empty: @Sendable () -> Value

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - url: The file.
    ///   - empty: The value of a missing file.
    public init(url: URL, empty: @escaping @Sendable () -> Value) {
        self.url = url
        self.fileLock = FileLock(url: url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).lock"))
        self.empty = empty
    }

    /// The stored value.
    public func load() -> Value {
        // Writes replace the file whole, so a read needs no lock.
        unlockedLoad()
    }

    /// Changes the stored value and writes it back.
    ///
    /// - Throws: Encoding or file system errors.
    @discardableResult
    public func update<Result>(_ change: (inout Value) throws -> Result) throws -> Result {
        try fileLock.withLock { try unlockedUpdate(change) }
    }

    private func unlockedUpdate<Result>(_ change: (inout Value) throws -> Result) throws -> Result {
        var value = unlockedLoad()
        let result = try change(&value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try SecureFile.write(try encoder.encode(value), to: url)
        return result
    }

    private func unlockedLoad() -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? SecureFile.read(url), let value = try? decoder.decode(Value.self, from: data) else {
            return empty()
        }
        return value
    }
}

/// A ChatGPT sign-in for plan usage, as the token endpoint issued it.
public struct ChatGPTAccount: Sendable, Equatable, Codable {
    /// The account's email, from the ID token; shown to the user.
    public var email: String?
    /// The ID token's `sub`: who signed in.
    public var subject: String
    /// The client id issued to Tag Agent for this account at registration.
    public var clientID: String
    /// The latest ID token, sent back as `id_token_hint` on the next sign-in.
    public var idToken: String
    /// The bearer token for inference.
    public var accessToken: String
    /// The rotating token that renews ``accessToken``.
    public var refreshToken: String
    /// When ``accessToken`` expires.
    public var expiresAt: Date
    /// The scopes granted.
    public var scopes: [String]

    /// Creates an account record.
    public init(
        email: String?,
        subject: String,
        clientID: String,
        idToken: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        scopes: [String],
    ) {
        self.email = email
        self.subject = subject
        self.clientID = clientID
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }
}

/// Everything in `credentials.json`.
public struct Credentials: Sendable, Equatable, Codable {
    /// API keys by ``ProviderID`` raw value.
    public var apiKeys: [String: String] = [:]
    /// The ChatGPT sign-in, if any.
    public var chatGPT: ChatGPTAccount?
    /// This machine's opaque `ext_agent_host_id`; made once and kept, also
    /// after signing out.
    public var chatGPTHostID: String?
    /// The client id issued at the last registration, kept after signing out
    /// so signing in again reuses it.
    public var chatGPTClientID: String?

    /// No credentials.
    public init() {}
}

/// The user's credentials in `credentials.json` (`0600`), with API keys from
/// the environment taking precedence over stored ones.
public final class CredentialStore: Sendable {
    /// The config directory the credentials live in.
    public let directory: URL
    private let file: JSONFileStore<Credentials>
    private let environment: [String: String]
    /// Held across processes while a ChatGPT token is refreshed.
    let refreshLock: FileLock

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - directory: The config directory.
    ///   - environment: The process environment, for API key variables.
    public init(
        directory: URL = ConfigDirectory.url(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) {
        self.directory = directory
        self.file = JSONFileStore(url: directory.appending(path: "credentials.json")) { Credentials() }
        self.environment = environment
        self.refreshLock = FileLock(url: directory.appending(path: ".chatgpt-refresh.lock"))
    }

    /// Everything stored.
    public func load() -> Credentials {
        file.load()
    }

    /// Changes the stored credentials.
    ///
    /// - Throws: Encoding or file system errors.
    public func update(_ change: (inout Credentials) -> Void) throws {
        try file.update(change)
    }

    /// The API key for `provider`: the environment variable `variable` when
    /// set, else the stored key.
    public func apiKey(for provider: ProviderID, variable: String?) -> String? {
        if let variable, let key = environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !key.isEmpty
        {
            return key
        }
        return load().apiKeys[provider.rawValue]
    }

    /// Stores `key` for `provider`, or removes it when `nil`.
    ///
    /// - Throws: Encoding or file system errors.
    public func setAPIKey(_ key: String?, for provider: ProviderID) throws {
        try update { $0.apiKeys[provider.rawValue] = key }
    }

    /// This machine's ChatGPT host id, made (`urn:uuid:…`) and stored on first use.
    ///
    /// - Throws: Encoding or file system errors.
    public func chatGPTHostID() throws -> String {
        try file.update { credentials in
            if let id = credentials.chatGPTHostID {
                return id
            }
            let id = "urn:uuid:\(UUID().uuidString.lowercased())"
            credentials.chatGPTHostID = id
            return id
        }
    }
}

/// What Tag Agent remembers between sessions.
public struct Settings: Sendable, Equatable, Codable {
    /// The model used last; the next session starts with it.
    public var lastModel: ModelRef?
    /// The reasoning effort chosen per model, by ``ModelRef/description``.
    public var reasoningEfforts: [String: String] = [:]
    /// Recently used models, newest first.
    public var recentModels: [ModelRef] = []
    /// Whether the one-time "You're using your ChatGPT plan" notice was shown.
    public var chatGPTWelcomeShown = false

    /// How many recent models are kept.
    public static let recentLimit = 6

    /// No settings yet.
    public init() {}

    /// Records `ref`, with `effort`, as the model in use.
    public mutating func use(_ ref: ModelRef, effort: String?) {
        lastModel = ref
        reasoningEfforts[ref.description] = effort
        recentModels.removeAll { $0 == ref }
        recentModels.insert(ref, at: 0)
        recentModels = Array(recentModels.prefix(Self.recentLimit))
    }

    /// The reasoning effort last chosen for `ref`.
    public func effort(for ref: ModelRef) -> String? {
        reasoningEfforts[ref.description]
    }
}

/// `settings.json` in the config directory.
public typealias SettingsStore = JSONFileStore<Settings>

extension JSONFileStore where Value == Settings {
    /// The settings file in `directory`.
    public convenience init(directory: URL = ConfigDirectory.url()) {
        self.init(url: directory.appending(path: "settings.json")) { Settings() }
    }
}
