import Foundation
import GRDB

enum SessionMigrations {
    static func prepare(_ queue: DatabaseQueue, directory: URL) throws {
        let lock = try FileHandle(forUpdating: migrationLock(directory))
        defer { try? lock.close() }
        guard flock(lock.fileDescriptor, LOCK_EX) == 0 else { throw SessionError.sessionInUse }
        defer { flock(lock.fileDescriptor, LOCK_UN) }
        try validate(queue)
        let version = try queue.read { try Int.fetchOne($0, sql: "PRAGMA user_version") ?? 0 }
        if version > 0, version < 5 { try backup(queue, directory: directory, version: version) }
        var migrator = DatabaseMigrator()
        migrator.registerMigration("sessions-v1") { database in
            try database.execute(sql: schema)
        }
        migrator.registerMigration("sessions-v2-search") { database in
            try SessionSearchIndex.migrate(database)
        }
        migrator.registerMigration("sessions-v3-literal") { database in
            try database.execute(
                sql: """
                    DROP TRIGGER IF EXISTS entry_search_insert;
                    DROP TABLE IF EXISTS entry_search_fts;
                    PRAGMA user_version = 3;
                    """)
            if try !database.columns(in: "entry_search").contains(where: { $0.name == "folded" }) {
                try database.execute(sql: "ALTER TABLE entry_search ADD COLUMN folded BLOB NOT NULL DEFAULT X''")
            }
            try SessionSearchIndex.rebuild(database)
        }
        migrator.registerMigration("sessions-v4-outputs", migrate: OutputMigration.migrate)
        migrator.registerMigration("sessions-v5-output-search", migrate: OutputIndex.migrate)
        try migrator.migrate(queue)
    }

    private static func backup(_ queue: DatabaseQueue, directory: URL, version: Int) throws {
        try SessionFiles.prepare(directory.appending(path: "backups"))
        let destination = directory.appending(path: "backups/pre-v\(version + 1)")
        try SessionFiles.prepare(destination)
        let file = destination.appending(path: "sessions.sqlite")
        try SessionFiles.create(file)
        let copy = try DatabaseQueue(path: file.path)
        try queue.backup(to: copy)
    }

    private static func migrationLock(_ directory: URL) throws -> URL {
        let url = directory.appending(path: ".migration.lock")
        try SessionFiles.create(url)
        return url
    }

    private static func validate(_ queue: DatabaseQueue) throws {
        try queue.read { database in
            let version = try Int.fetchOne(database, sql: "PRAGMA user_version") ?? 0
            guard version <= 5 else { throw SessionError.unsupportedVersion(version) }
            if version > 0 {
                let expected = Array(
                    [
                        "sessions-v1", "sessions-v2-search", "sessions-v3-literal", "sessions-v4-outputs",
                        "sessions-v5-output-search",
                    ].prefix(version))
                let applied = try String.fetchAll(
                    database, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
                guard applied == expected else { throw SessionError.invalidEvent }
            }
            let mode = try String.fetchOne(database, sql: "PRAGMA journal_mode") ?? "unknown"
            guard mode == "delete" else { throw SessionError.unsupportedJournal(mode) }
            let tables =
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'") ?? 0
            if version == 0, tables > 0 {
                // GRDB creates its metadata table before running the migration.
                // A crash in that window must still permit first-time setup.
                guard tables == 1, try database.tableExists("grdb_migrations"),
                    try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM grdb_migrations") == 0
                else { throw SessionError.invalidEvent }
            }
        }
    }

    private static let schema = """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY NOT NULL,
            workspace TEXT NOT NULL,
            title TEXT NOT NULL,
            last_opened REAL NOT NULL,
            metadata BLOB NOT NULL
        );
        CREATE INDEX sessions_workspace_recent ON sessions(workspace, last_opened DESC, id DESC);
        CREATE INDEX sessions_recent ON sessions(last_opened DESC, id DESC);
        CREATE TABLE entries (
            session_id TEXT NOT NULL REFERENCES sessions(id),
            sequence INTEGER NOT NULL,
            timestamp REAL NOT NULL,
            payload BLOB NOT NULL,
            PRIMARY KEY (session_id, sequence)
        );
        CREATE TABLE pending_inputs (
            position INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL REFERENCES sessions(id),
            input_id TEXT NOT NULL UNIQUE,
            payload BLOB NOT NULL
        );
        CREATE INDEX pending_session ON pending_inputs(session_id, position);
        CREATE TABLE workspace_state (
            workspace TEXT PRIMARY KEY NOT NULL,
            session_id TEXT NOT NULL REFERENCES sessions(id)
        );
        CREATE TABLE session_drafts (
            session_id TEXT PRIMARY KEY NOT NULL REFERENCES sessions(id),
            payload BLOB NOT NULL
        );
        PRAGMA user_version = 1;
        """
}
