import Foundation
import GRDB
import ModelKit
import SessionKit

enum ProbeJobs {
    @concurrent
    static func draftFault(_ store: SQLiteSessionStore) async throws {
        let connection = try DatabaseQueue(path: store.directory.appending(path: "sessions.sqlite").path)
        try await connection.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER fail_draft_save BEFORE INSERT ON session_drafts BEGIN
                        SELECT RAISE(ABORT, 'injected draft save failure');
                    END
                    """)
        }
    }

    @concurrent
    static func pointerFault(_ store: SQLiteSessionStore, enabled: Bool) async throws {
        var configuration = Configuration()
        configuration.busyMode = .timeout(2)
        configuration.prepareDatabase { try $0.execute(sql: "PRAGMA synchronous = FULL; PRAGMA fullfsync = ON") }
        let connection = try DatabaseQueue(
            path: store.directory.appending(path: "sessions.sqlite").path, configuration: configuration)
        try await connection.write { database in
            try database.execute(sql: "DROP TRIGGER IF EXISTS fail_workspace_open")
            if enabled {
                try database.execute(
                    sql: """
                        CREATE TRIGGER fail_workspace_open BEFORE INSERT ON workspace_state BEGIN
                            SELECT RAISE(ABORT, 'injected continuation pointer failure');
                        END
                        """)
            }
        }
    }

    @concurrent
    static func inputFault(_ store: SQLiteSessionStore, enabled: Bool) async throws {
        let connection = try DatabaseQueue(path: store.directory.appending(path: "sessions.sqlite").path)
        try await connection.write { database in
            try database.execute(sql: "DROP TRIGGER IF EXISTS fail_pending_accept")
            if enabled {
                try database.execute(
                    sql: """
                        CREATE TRIGGER fail_pending_accept BEFORE INSERT ON pending_inputs BEGIN
                            SELECT RAISE(ABORT, 'injected pending acceptance failure');
                        END
                        """)
            }
        }
    }

    /// Only this kill fixture deliberately suspends inside a raw write transaction.
    @concurrent
    static func holdTransaction(
        store: SQLiteSessionStore, id: UUID, boundary: ProbeBoundary, ownsSession: Bool
    ) async throws {
        let owner = try ownsSession ? SessionOwnership(directory: store.directory, sessionID: id) : nil
        defer { withExtendedLifetime(owner) {} }
        var summary = try await store.summary(id)
        summary.title = "uncommitted"
        let payload = try JSONEncoder().encode(summary)
        var configuration = Configuration()
        configuration.busyMode = .timeout(2)
        configuration.prepareDatabase {
            try $0.execute(
                sql: "PRAGMA synchronous = FULL; PRAGMA fullfsync = ON; PRAGMA cache_size = 1; PRAGMA cache_spill = ON")
        }
        let connection = try DatabaseQueue(
            path: store.directory.appending(path: "sessions.sqlite").path, configuration: configuration)
        try await connection.write { database in
            try database.execute(
                sql: "UPDATE sessions SET title = ?, metadata = ? WHERE id = ?",
                arguments: ["uncommitted", payload, id.uuidString.lowercased()])
            try boundary.signal()
            Thread.sleep(forTimeInterval: 30)
        }
    }

    /// Recreates a recognized previous schema only inside the marked generated fixture.
    @concurrent
    static func prepareV1(_ store: SQLiteSessionStore) async throws {
        var configuration = Configuration()
        configuration.busyMode = .timeout(2)
        configuration.prepareDatabase { try $0.execute(sql: "PRAGMA synchronous = FULL; PRAGMA fullfsync = ON") }
        let connection = try DatabaseQueue(
            path: store.directory.appending(path: "sessions.sqlite").path, configuration: configuration)
        try await connection.write { database in
            try database.execute(
                sql: """
                    DROP TRIGGER IF EXISTS entry_search_insert;
                    DROP TABLE IF EXISTS entry_search_fts;
                    DROP TABLE entry_search;
                    DELETE FROM grdb_migrations WHERE identifier IN ('sessions-v2-search', 'sessions-v3-literal');
                    PRAGMA user_version = 1;
                    """)
        }
    }

    @concurrent
    static func write(store: SQLiteSessionStore, id: UUID, boundary: ProbeBoundary, root: URL) async throws {
        let count = try iterations(boundary)
        let owner = try SessionOwnership(directory: store.directory, sessionID: id)
        defer { withExtendedLifetime(owner) {} }
        try boundary.signal()
        try await boundary.waitForStart(in: root)
        for index in 0..<count {
            let text = "entry \(index) " + String(repeating: "durable fixture ", count: 260)
            try await store.append(
                id, event: .assistant(SessionAssistant(message: AssistantMessage(text: text), usage: nil)))
        }
    }

    @concurrent
    static func read(store: SQLiteSessionStore, boundary: ProbeBoundary, root: URL) async throws {
        let count = try iterations(boundary)
        try boundary.signal()
        try await boundary.waitForStart(in: root)
        for _ in 0..<count {
            _ = try await store.list(workspace: nil)
        }
    }

    private static func iterations(_ boundary: ProbeBoundary) throws -> Int {
        guard let count = Int(boundary.phase), (1...10_000).contains(count) else { throw ProbeFailure.usage }
        return count
    }
}
