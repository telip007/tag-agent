import Foundation
import GRDB
import ModelKit
import Testing

@testable import SessionKit

struct SessionMigrationTests {
    @Test func failedMigrationRetriesRefreshOneBoundedBackup() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.database.write { database in
            try database.execute(
                sql: """
                    DELETE FROM grdb_migrations WHERE identifier = 'sessions-v3-literal';
                    PRAGMA user_version = 2;
                    UPDATE entries SET payload = X'00';
                    UPDATE sessions SET title = 'retry 0';
                    """)
        }
        for attempt in 0..<3 {
            await #expect(throws: (any Error).self) { try await fixture.open() }
            let backups = fixture.directory.appending(path: "backups")
            let copies = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            #expect(copies.count == 1)
            let copy = try #require(copies.first)
            let database = try DatabaseQueue(path: copy.appending(path: "sessions.sqlite").path)
            #expect(try await database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 2)
            #expect(
                try await database.read { try String.fetchOne($0, sql: "SELECT title FROM sessions") }
                    == "retry \(attempt)")
            try await store.database.write { database in
                try database.execute(sql: "UPDATE sessions SET title = ?", arguments: ["retry \(attempt + 1)"])
            }
        }
        #expect(
            try await store.database.read { try Data.fetchOne($0, sql: "SELECT payload FROM entries") } == Data([0]))
        #expect(
            try await store.database.read { try String.fetchOne($0, sql: "SELECT id FROM sessions") }
                == session.id.uuidString.lowercased())
    }

    @Test func literalSearchMigrationDropsUnusedFTSWithoutLosingHistory() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.append(
            session.id,
            event: .user(
                SessionUser(raw: "old literal\0after", message: "old literal\0after", date: "today", references: [])))
        let before = try await store.entries(session.id)
        try await store.database.write { database in
            try database.execute(
                sql: """
                    CREATE VIRTUAL TABLE IF NOT EXISTS entry_search_fts USING fts5(text, content='entry_search', content_rowid='rowid');
                    CREATE TRIGGER IF NOT EXISTS entry_search_insert AFTER INSERT ON entry_search BEGIN
                        INSERT INTO entry_search_fts(rowid, text) VALUES (new.rowid, new.text);
                    END;
                    DELETE FROM grdb_migrations WHERE identifier = 'sessions-v3-literal';
                    PRAGMA user_version = 2;
                    ALTER TABLE entry_search DROP COLUMN folded;
                    UPDATE entry_search SET text = 'old literal';
                    """)
        }
        let reopened = try await fixture.open()
        #expect(try await reopened.database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 3)
        #expect(try await reopened.database.read { try !$0.tableExists("entry_search_fts") })
        #expect(try await reopened.entries(session.id) == before)
        #expect(try await reopened.search(session.id, query: "literal").count == 1)
        #expect(try await reopened.search(session.id, query: "after").count == 1)
        let backups = fixture.directory.appending(path: "backups")
        #expect(FileManager.default.fileExists(atPath: backups.path))
        guard FileManager.default.fileExists(atPath: backups.path) else { return }
        let copies = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        #expect(copies.count == 1)
        let copy = try #require(copies.first)
        let database = try DatabaseQueue(path: copy.appending(path: "sessions.sqlite").path)
        #expect(try await database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 2)
    }

    @Test func recognizedOlderSchemaIsBackedUpBeforeSearchBackfill() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "old history"), usage: nil)))
        try await store.database.write { database in
            try database.execute(
                sql: """
                    DROP TRIGGER IF EXISTS entry_search_insert;
                    DROP TABLE IF EXISTS entry_search_fts;
                    DROP TABLE entry_search;
                    DELETE FROM grdb_migrations WHERE identifier IN ('sessions-v2-search', 'sessions-v3-literal');
                    PRAGMA user_version = 1;
                    """)
        }
        let reopened = try await fixture.open()
        #expect(try await reopened.search(session.id, query: "old history").count == 1)
        let backups = fixture.directory.appending(path: "backups")
        let copies = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        #expect(copies.count == 1)
        let copy = try #require(copies.first)
        let database = try DatabaseQueue(path: copy.appending(path: "sessions.sqlite").path)
        let version = try await database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") }
        #expect(version == 1)
        #expect(try await database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM entries") } == 2)
    }
}
