public import Foundation
import GRDB

/// Capabilities reported by the library actually linked into Tag.
public struct SessionStoreDiagnostics: Sendable {
    /// Linked SQLite version, not a separate command-line executable.
    public var version: String
    /// Linked SQLite source identifier, without inferring vendor patch status.
    public var sourceID: String
    /// Existing store's journal mode.
    public var journalMode: String
    /// SQLite's synchronous value; 2 means FULL.
    public var synchronous: Int
    /// Whether Apple's stronger flush mode is enabled.
    public var fullFSync: Bool
    /// Whether an actual temporary FTS5 table can be created.
    public var fts5: Bool
}

extension SQLiteSessionStore {
    /// Reads capabilities from the application connection.
    public func diagnostics() async throws -> SessionStoreDiagnostics {
        try await database.write { database in
            SessionStoreDiagnostics(
                version: try String.fetchOne(database, sql: "SELECT sqlite_version()") ?? "unknown",
                sourceID: try String.fetchOne(database, sql: "SELECT sqlite_source_id()") ?? "unknown",
                journalMode: try String.fetchOne(database, sql: "PRAGMA journal_mode") ?? "unknown",
                synchronous: try Int.fetchOne(database, sql: "PRAGMA synchronous") ?? -1,
                fullFSync: try Bool.fetchOne(database, sql: "PRAGMA fullfsync") ?? false,
                fts5: try Self.probeFTS5(database))
        }
    }

    static func probeFTS5(_ database: Database) throws -> Bool {
        do {
            try database.execute(sql: "CREATE VIRTUAL TABLE temp.session_fts_probe USING fts5(text)")
            try database.execute(sql: "DROP TABLE temp.session_fts_probe")
            return true
        } catch let error as DatabaseError where error.message?.contains("no such module: fts5") == true {
            return false
        }
    }

    /// Creates a consistent, owner-only backup without copying live journal files.
    @concurrent
    public func backup(to directory: URL) async throws {
        try SessionFiles.prepare(directory)
        let url = directory.appending(path: "sessions.sqlite")
        // Refuse to overwrite an existing backup.
        try Data().write(to: url, options: .withoutOverwriting)
        try SessionFiles.protect(url)
        let destination = try DatabaseQueue(path: url.path)
        try database.backup(to: destination)
    }
}
