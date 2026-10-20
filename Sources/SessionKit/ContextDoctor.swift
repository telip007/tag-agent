import CryptoKit
public import Foundation
import GRDB

/// Read-only checks on the actual linked engine and this session's evidence.
public struct ContextDoctor: Sendable, Equatable, Codable {
    /// SQLite quick_check result, not a simulated engine claim.
    public let databaseOK: Bool
    /// Canonical events and the current projection validate.
    public let journalOK: Bool
    /// Interrupted boundaries need explicit recovery; this call never repairs them.
    public let needsRecovery: Bool
    /// Artifact identity, length, UTF-8 and hashes validate.
    public let evidenceOK: Bool
    /// Derived chunks and available FTS rows agree with canonical evidence.
    public let indexOK: Bool
    /// Available retrieval route; literal matching remains available without FTS5.
    public let retrieval: String
    /// Engine actually linked into this process.
    public let sqliteVersion: String
    enum CodingKeys: String, CodingKey {
        case databaseOK = "database_ok"
        case journalOK = "journal_ok"
        case needsRecovery = "needs_recovery"
        case evidenceOK = "evidence_ok"
        case indexOK = "index_ok"
        case retrieval
        case sqliteVersion = "sqlite_version"
    }
}

extension SQLiteSessionStore {
    /// Reports corruption and pending work without mutating or replaying either.
    @concurrent public func contextDoctor(_ id: UUID) async throws -> ContextDoctor {
        try await database.read { database in
            _ = try Self.summary(id, database: database)
            var journalOK = true
            var needsRecovery = false
            do {
                let snapshot = try Self.snapshot(id, database: database)
                needsRecovery = try !SessionRecovery.events(for: snapshot.entries).isEmpty
            } catch { journalOK = false }
            let fts = try database.tableExists("context_output_fts")
            return ContextDoctor(
                databaseOK: try String.fetchOne(database, sql: "PRAGMA quick_check(1)") == "ok",
                journalOK: journalOK, needsRecovery: needsRecovery,
                evidenceOK: try ContextEvidenceCheck.valid(id, database: database),
                indexOK: try ContextEvidenceCheck.indexValid(id, fts: fts, database: database),
                retrieval: fts ? "fts5_and_literal" : "literal_only",
                sqliteVersion: try String.fetchOne(database, sql: "SELECT sqlite_version()") ?? "unknown")
        }
    }
}

enum ContextEvidenceCheck {
    static func valid(_ id: UUID, database: Database) throws -> Bool {
        let cursor = try Row.fetchCursor(
            database,
            sql: "SELECT id, metadata, content FROM context_outputs WHERE session_id = ?",
            arguments: [SQLiteSessionStore.key(id)])
        while let row = try cursor.next() {
            guard let reference = try? JSONDecoder().decode(OutputReference.self, from: row["metadata"]) else {
                return false
            }
            let bytes: Data = row["content"]
            let digest = SHA256.hash(data: bytes).map { byte in
                let hex = String(byte, radix: 16)
                return hex.count == 1 ? "0" + hex : hex
            }.joined()
            guard reference.id == row["id"], reference.byteCount == bytes.count, reference.sha256 == digest,
                String(validating: bytes, as: UTF8.self) != nil
            else { return false }
        }
        return true
    }

    static func indexValid(_ id: UUID, fts: Bool, database: Database) throws -> Bool {
        let key = SQLiteSessionStore.key(id)
        let outputs = try Row.fetchCursor(
            database, sql: "SELECT id, content FROM context_outputs WHERE session_id = ?", arguments: [key])
        while let output = try outputs.next() {
            guard try OutputIndex.matches(output["content"], id: output["id"], database: database) else { return false }
        }
        guard fts else { return true }
        let unmatched =
            try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*) FROM context_output_chunks c JOIN context_outputs o ON o.id = c.output_id
                    LEFT JOIN context_output_fts f ON f.rowid = c.rowid
                    WHERE o.session_id = ? AND (f.rowid IS NULL OR CAST(f.text AS BLOB) != CAST(c.text AS BLOB))
                    """, arguments: [key]) ?? 0
        return unmatched == 0
    }
}
