public import Foundation
import GRDB

/// A local transactional event store. SQL never runs on the UI actor.
public final class SQLiteSessionStore: SessionStore {
    let database: DatabaseQueue
    /// Owner-only storage root, already covered by Tag's protected config tree.
    public let directory: URL

    private init(directory: URL) throws {
        self.directory = directory
        try SessionFiles.prepare(directory)
        var configuration = Configuration()
        configuration.busyMode = .timeout(2)
        configuration.prepareDatabase { database in
            SessionSearchIndex.prepare(database)
            try database.execute(sql: "PRAGMA synchronous = FULL; PRAGMA fullfsync = ON")
        }
        let url = directory.appending(path: "sessions.sqlite")
        for suffix in ["-journal", "-wal", "-shm"] {
            try SessionFiles.protectIfPresent(directory.appending(path: "sessions.sqlite" + suffix))
        }
        // Pre-create with owner-only mode before SQLite opens the file.
        try SessionFiles.create(url)
        database = try DatabaseQueue(path: url.path, configuration: configuration)
        try SessionMigrations.prepare(database, directory: directory)
        try SessionFiles.protect(url)
    }

    /// Opens and migrates away from the calling actor, preserving bad stores.
    @concurrent
    public static func open(directory: URL) async throws -> SQLiteSessionStore {
        try SQLiteSessionStore(directory: directory)
    }

    /// Creates an empty session and its initial context in one transaction.
    public func create(workspace: String, context: SessionContext) async throws -> SessionSummary {
        try await database.write { database in
            let summary = SessionSummary(workspace: workspace, context: context, now: Date())
            try Self.insert(summary, database: database)
            try Self.append(summary.id, event: .context(context), database: database)
            return try Self.summary(summary.id, database: database)
        }
    }

    /// Returns indexed metadata, failing when the session is missing.
    public func summary(_ id: UUID) async throws -> SessionSummary {
        try await database.read { try Self.summary(id, database: $0) }
    }

    /// Appends one bounded event; existing history is never rewritten.
    public func append(_ id: UUID, event: SessionEvent) async throws {
        try await database.write { try Self.append(id, event: event, database: $0) }
    }

    /// Loads ordered records, optionally paging by sequence.
    public func entries(_ id: UUID, after: Int64? = nil, limit: Int? = nil) async throws -> [SessionEntry] {
        try await database.read { database in
            _ = try Self.summary(id, database: database)
            return try Self.readEntries(id, after: after, limit: limit, database: database)
        }
    }

    static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    static func summary(_ id: UUID, database: Database) throws -> SessionSummary {
        guard
            let data = try Data.fetchOne(
                database, sql: "SELECT metadata FROM sessions WHERE id = ?",
                arguments: [key(id)])
        else { throw SessionError.notFound }
        return try JSONDecoder().decode(SessionSummary.self, from: data)
    }

    static func insert(_ summary: SessionSummary, database: Database) throws {
        try database.execute(
            sql: "INSERT INTO sessions(id, workspace, title, last_opened, metadata) VALUES (?, ?, ?, ?, ?)",
            arguments: [
                key(summary.id), summary.workspace, summary.title, summary.lastOpenedAt.timeIntervalSinceReferenceDate,
                try JSONEncoder().encode(summary),
            ])
    }

    static func update(_ summary: SessionSummary, database: Database) throws {
        try database.execute(
            sql: "UPDATE sessions SET title = ?, last_opened = ?, metadata = ? WHERE id = ?",
            arguments: [
                summary.title, summary.lastOpenedAt.timeIntervalSinceReferenceDate, try JSONEncoder().encode(summary),
                key(summary.id),
            ])
    }
}
