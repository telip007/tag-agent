import CryptoKit
public import Foundation
import GRDB

extension SQLiteSessionStore {
    /// Loads a bounded whole artifact for off-prompt computation, verifying its hash before use.
    @concurrent public func loadOutput(
        _ session: UUID, id: String, byteLimit: Int = 32 * 1024 * 1024
    ) async throws -> OutputPage {
        guard UUID(uuidString: id) != nil else { throw OutputError.notFound }
        guard (1...32 * 1024 * 1024).contains(byteLimit) else { throw OutputError.analysisInputTooLarge }
        return try await database.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: """
                        SELECT metadata, length(content) AS size,
                        CASE WHEN length(content) <= ? THEN content ELSE NULL END AS input
                        FROM context_outputs WHERE session_id = ? AND id = ?
                        """,
                    arguments: [byteLimit, Self.key(session), id])
            else { throw OutputError.notFound }
            let size: Int = row["size"]
            guard size <= byteLimit else { throw OutputError.analysisInputTooLarge }
            let reference = try JSONDecoder().decode(OutputReference.self, from: row["metadata"])
            let bytes: Data = row["input"]
            let digest = SHA256.hash(data: bytes).map { byte in
                let hex = String(byte, radix: 16)
                return hex.count == 1 ? "0" + hex : hex
            }.joined()
            guard reference.id == id, reference.byteCount == size, bytes.count == size, reference.sha256 == digest,
                let text = String(validating: bytes, as: UTF8.self)
            else { throw OutputError.invalidEvidence }
            return OutputPage(reference: reference, offset: 0, text: text, nextOffset: nil)
        }
    }
}
