public import Foundation
import GRDB

/// Exact text from a ranked chunk, with coordinates for independent verification.
public struct OutputMatch: Sendable, Equatable {
    /// Immutable source evidence and provenance.
    public let reference: OutputReference
    /// Beginning UTF-8 byte offset in the original artifact.
    public let offset: Int
    /// Exact bounded excerpt; a match is not a whole-input analysis.
    public let text: String
}

extension SQLiteSessionStore {
    /// Searches only this session's artifacts, with a shared text-byte budget.
    public func searchOutputs(
        _ session: UUID, query: String, outputID: String? = nil, limit: Int = 5, byteLimit: Int = 8192
    ) async throws -> [OutputMatch] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            query.utf8.count <= 1024, (1...20).contains(limit), (4...16_384).contains(byteLimit)
        else { throw OutputError.invalidQuery }
        return try await database.read { database in
            _ = try Self.summary(session, database: database)
            let candidates = try OutputSearch.candidates(
                session: Self.key(session), query: query, outputID: outputID, limit: limit, database: database)
            return try OutputSearch.matches(candidates, query: query, limit: limit, byteLimit: byteLimit)
        }
    }
}

enum OutputSearch {
    private static let projection = "SELECT c.rowid, c.byte_offset, CAST(c.text AS BLOB) AS text, o.metadata "
    private static let scope = "o.session_id = :session AND (:output IS NULL OR o.id = :output)"

    static func candidates(
        session: String, query: String, outputID: String?, limit: Int, database: Database
    ) throws -> [Row] {
        let arguments: StatementArguments = [
            "session": session, "query": Data(query.utf8), "output": outputID, "limit": limit,
        ]
        let literal = try Row.fetchAll(
            database,
            sql: projection + "FROM context_output_chunks c JOIN context_outputs o ON o.id = c.output_id WHERE "
                + scope
                + " AND tag_literal_position(CAST(c.text AS BLOB), :query) > 0 ORDER BY c.rowid DESC LIMIT :limit",
            arguments: arguments)
        let terms = query.split { !$0.isLetter && !$0.isNumber && $0 != "_" }.map { "\"" + $0 + "\"" }
        guard literal.count < limit, !terms.isEmpty, try database.tableExists("context_output_fts") else {
            return literal
        }
        let ftsArguments: StatementArguments = [
            "session": session, "output": outputID, "limit": limit, "match": terms.joined(separator: " OR "),
        ]
        let ranked = try Row.fetchAll(
            database,
            sql: projection
                + "FROM context_output_fts JOIN context_output_chunks c ON c.rowid = context_output_fts.rowid "
                + "JOIN context_outputs o ON o.id = c.output_id WHERE " + scope
                + " AND context_output_fts MATCH :match ORDER BY bm25(context_output_fts), c.rowid DESC LIMIT :limit",
            arguments: ftsArguments)
        let seen = Set(literal.map { (row: Row) -> Int64 in row["rowid"] })
        return literal + ranked.filter { !seen.contains($0["rowid"] as Int64) }
    }

    static func matches(_ rows: [Row], query: String, limit: Int, byteLimit: Int) throws -> [OutputMatch] {
        var remaining = byteLimit
        var matches: [OutputMatch] = []
        for row in rows.prefix(limit) {
            guard remaining >= 4 else { break }
            let bytes: Data = row["text"]
            let reference = try JSONDecoder().decode(OutputReference.self, from: row["metadata"])
            let offset: Int = row["byte_offset"]
            let start = windowStart(bytes, query: query, budget: remaining)
            let page = try OutputRanges.page(
                reference: reference, bytes: Data(bytes.dropFirst(start).prefix(remaining)), offset: offset + start)
            matches.append(OutputMatch(reference: reference, offset: page.offset, text: page.text))
            remaining -= page.text.utf8.count
        }
        return matches
    }

    private static func windowStart(_ bytes: Data, query: String, budget: Int) -> Int {
        guard bytes.count > budget, let text = String(validating: bytes, as: UTF8.self),
            let range = text.range(of: query, options: .caseInsensitive)
        else { return 0 }
        let position = text.utf8.distance(from: text.utf8.startIndex, to: range.lowerBound)
        var start = max(0, position - budget / 4)
        while start > 0, bytes[start] & 0xC0 == 0x80 { start -= 1 }
        return start
    }
}
