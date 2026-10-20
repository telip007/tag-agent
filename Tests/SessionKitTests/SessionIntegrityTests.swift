import Foundation
import GRDB
import ModelKit
import Testing

@testable import SessionKit

struct SessionIntegrityTests {
    @Test func anExistingWalModeIsRefusedWithoutChangingItOrItsHistory() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        // Nonconcurrent legacy-mode fixture only; no application writes/checkpoints in WAL.
        try await store.database.writeWithoutTransaction { database in
            _ = try String.fetchOne(database, sql: "PRAGMA journal_mode = WAL")
        }
        await #expect(throws: SessionError.unsupportedJournal("wal")) { try await fixture.open() }
        #expect(try await store.database.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") } == "wal")
        #expect(try await store.entries(session.id).map(\.event) == [.context(fixture.context)])
    }

    @Test func initialMigrationResumesAfterMetadataTableCreation() async throws {
        let fixture = SessionStoreFixture()
        try SessionFiles.prepare(fixture.directory)
        let path = fixture.directory.appending(path: "sessions.sqlite").path
        let connection = try DatabaseQueue(path: path)
        try await connection.write { database in
            try database.execute(sql: "CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY)")
        }
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        #expect(try await store.entries(session.id).count == 1)
    }

    @Test func pendingConsumptionCannotSubstituteAnotherMessage() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let input = PendingInput(text: "accepted", references: [])
        try await store.accept(session.id, input: input)
        await #expect(throws: SessionError.invalidEvent) {
            try await store.consume(
                session.id, inputID: input.id,
                user: SessionUser(raw: "different", message: "different", date: "2026-10-20", references: []))
        }
        #expect(try await store.pending(session.id) == [input])
    }

    @Test func aMissingSessionIsNotAnEmptyPendingQueue() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        await #expect(throws: SessionError.notFound) { try await store.pending(UUID()) }
    }

    @Test func futureSchemaAndCorruptPayloadsArePreservedAndRejected() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.database.write { database in
            try database.execute(
                sql: "UPDATE entries SET payload = ? WHERE session_id = ? AND sequence = 0",
                arguments: [Data("{\"version\":7}".utf8), session.id.uuidString.lowercased()])
        }
        await #expect(throws: SessionError.unsupportedVersion(7)) { try await store.entries(session.id) }
        #expect(try await store.summary(session.id).id == session.id)
        try await store.database.write { try $0.execute(sql: "PRAGMA user_version = 8") }
        await #expect(throws: SessionError.unsupportedVersion(8)) { try await fixture.open() }
        #expect(try await store.summary(session.id).id == session.id)
    }

    @Test func interruptedPromotionRollsBackBothDeleteAndAppend() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let input = PendingInput(text: "recover me", references: [])
        try await store.accept(session.id, input: input)
        try await store.database.write { database in
            try database.execute(
                sql: """
                    CREATE TRIGGER refuse_entry BEFORE INSERT ON entries BEGIN
                        SELECT RAISE(ABORT, 'injected append failure');
                    END
                    """)
        }
        await #expect(throws: DatabaseError.self) {
            try await store.consume(
                session.id, inputID: input.id,
                user: SessionUser(raw: input.text, message: input.text, date: "2026-10-20", references: []))
        }
        #expect(try await store.pending(session.id) == [input])
        #expect(try await store.entries(session.id).count == 1)
    }

    @Test func onlineBackupIncludesCommittedEntriesAndCanReopen() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.append(session.id, event: .inferenceStarted)
        let backupDirectory = fixture.directory.appending(path: "backup")
        try await store.backup(to: backupDirectory)
        let copy = try await SQLiteSessionStore.open(directory: backupDirectory)
        #expect(try await copy.entries(session.id).map(\.event) == [.context(fixture.context), .inferenceStarted])
    }

    @Test func titleStillComesFromFirstInputAfterAContextRevision() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.append(session.id, event: .context(fixture.context))
        try await store.append(
            session.id,
            event: .user(
                SessionUser(raw: "  first\n topic  ", message: "first", date: "2026-10-20", references: [])))
        #expect(try await store.summary(session.id).title == "first topic")
    }
}
