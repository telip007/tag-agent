public import Foundation
import GRDB

/// Exact bytes from one canonical event envelope, not a decoded display excerpt.
public struct HistoryPage: Sendable {
    /// Stable canonical event sequence in the active session.
    public let sequence: Int64
    /// Beginning UTF-8 byte offset in the stored JSON envelope.
    public let offset: Int
    /// Total persisted envelope bytes.
    public let bytes: Int
    /// Exact text, ending on a scalar boundary.
    public let text: String
    /// Next exact byte offset, or nil at the end.
    public let nextOffset: Int?
}

extension SQLiteSessionStore {
    /// Reads one bounded JSON range, scoped before touching canonical bytes.
    public func readHistory(
        _ id: UUID, sequence: Int64, offset: Int = 0, limit: Int = 8192
    ) async throws -> HistoryPage {
        guard sequence >= 0, offset >= 0, offset < Int.max, (1...16_384).contains(limit) else {
            throw OutputError.invalidRange
        }
        return try await database.read { database in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql:
                        "SELECT length(payload) AS size, substr(payload, ?, ?) AS page FROM entries WHERE session_id = ? AND sequence = ?",
                    arguments: [offset + 1, limit, Self.key(id), sequence])
            else { throw SessionError.notFound }
            let size: Int = row["size"]
            guard offset <= size else { throw OutputError.invalidRange }
            var data: Data = row["page"]
            if let first = data.first, first & 0xC0 == 0x80 { throw OutputError.invalidRange }
            while !data.isEmpty, String(validating: data, as: UTF8.self) == nil { data.removeLast() }
            guard let text = String(validating: data, as: UTF8.self), !text.isEmpty || offset == size else {
                throw OutputError.invalidRange
            }
            let end = offset + data.count
            return HistoryPage(
                sequence: sequence, offset: offset, bytes: size, text: text, nextOffset: end < size ? end : nil)
        }
    }
}
