import CryptoKit
public import Foundation
import GRDB

extension SQLiteSessionStore {
    /// Atomically retains exact evidence; failed writes leave earlier evidence intact.
    @concurrent
    public func saveOutput(
        _ session: UUID, text: String, source: String, callID: String? = nil,
        complete: Bool = true, limits: OutputLimits = OutputLimits()
    ) async throws -> OutputReference {
        let content = Data(text.utf8)
        guard limits.perOutput >= 0, limits.perSession >= 0,
            content.count <= limits.perOutput
        else { throw OutputError.quotaExceeded }
        guard source.utf8.count <= 2048, (callID?.utf8.count ?? 0) <= 1024 else {
            throw OutputError.invalidEvidence
        }
        let digest = SHA256.hash(data: content).map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
        let reference = OutputReference(
            id: UUID().uuidString.lowercased(), source: source, callID: callID,
            byteCount: content.count, sha256: digest, complete: complete, createdAt: Date())
        return try await database.write { database in
            _ = try Self.summary(session, database: database)
            let stored = try Self.outputStatistics(session, database: database).storedBytes
            guard content.count <= limits.perSession, stored <= limits.perSession - content.count else {
                throw OutputError.quotaExceeded
            }
            try database.execute(
                sql:
                    "INSERT INTO context_outputs(id, session_id, metadata, content, byte_count) VALUES (?, ?, ?, ?, ?)",
                arguments: [
                    reference.id, Self.key(session), try JSONEncoder().encode(reference), content, content.count,
                ])
            try OutputIndex.insert(content, id: reference.id, database: database)
            return reference
        }
    }

    /// Reads only the requested bounded byte range, scoped before accessing its blob.
    public func readOutput(_ session: UUID, id: String, offset: Int, limit: Int) async throws -> OutputPage {
        guard UUID(uuidString: id) != nil else { throw OutputError.notFound }
        guard offset >= 0, offset < Int.max, (1...16_384).contains(limit) else { throw OutputError.invalidRange }
        return try await database.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql:
                        "SELECT metadata, substr(content, ?, ?) AS page FROM context_outputs WHERE session_id = ? AND id = ?",
                    arguments: [offset + 1, limit, Self.key(session), id])
            else { throw OutputError.notFound }
            let reference = try JSONDecoder().decode(OutputReference.self, from: row["metadata"])
            let bytes: Data = row["page"]
            return try OutputRanges.page(reference: reference, bytes: bytes, offset: offset)
        }
    }

    /// Counts canonical retained bytes separately from search or prompt accounting.
    public func outputStatistics(_ session: UUID) async throws -> OutputStatistics {
        try await database.read { database in
            _ = try Self.summary(session, database: database)
            return try Self.outputStatistics(session, database: database)
        }
    }

    static func outputStatistics(_ session: UUID, database: Database) throws -> OutputStatistics {
        let count =
            try Int.fetchOne(
                database, sql: "SELECT COUNT(*) FROM context_outputs WHERE session_id = ?", arguments: [key(session)])
            ?? 0
        let bytes =
            try Int.fetchOne(
                database, sql: "SELECT COALESCE(SUM(byte_count), 0) FROM context_outputs WHERE session_id = ?",
                arguments: [key(session)]) ?? 0
        return OutputStatistics(outputCount: count, storedBytes: bytes)
    }
}

enum OutputRanges {
    static func page(reference: OutputReference, bytes: Data, offset: Int) throws -> OutputPage {
        guard offset <= reference.byteCount else { throw OutputError.invalidRange }
        var slice = bytes
        // The first byte must start a scalar; only a trailing partial scalar may be trimmed.
        if let first = slice.first, first & 0xC0 == 0x80 { throw OutputError.invalidRange }
        while !slice.isEmpty, String(validating: slice, as: UTF8.self) == nil {
            guard slice.count > 1 else { throw OutputError.invalidRange }
            slice.removeLast()
        }
        guard let text = String(validating: slice, as: UTF8.self), !slice.isEmpty || offset == reference.byteCount
        else {
            throw OutputError.invalidRange
        }
        let end = offset + slice.count
        guard end <= reference.byteCount else { throw OutputError.invalidEvidence }
        return OutputPage(
            reference: reference, offset: offset, text: text, nextOffset: end < reference.byteCount ? end : nil)
    }
}
