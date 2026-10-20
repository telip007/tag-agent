public import Foundation
import GRDB

extension SQLiteSessionStore {
    /// Searches only one explicitly selected session; defaults to its latest completed exchange.
    /// Results are copied, attributable and bounded to five excerpts and 16 KiB including labels.
    public func search(_ id: UUID, query: String = "") async throws -> [SessionReference] {
        try await database.read { try Self.search(id, query: query, database: $0) }
    }

    static func search(_ id: UUID, query: String, database: Database) throws -> [SessionReference] {
        let summary = try summary(id, database: database)
        let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
        let condition: String
        let position = SessionSearchIndex.position("text", foldedColumn: "folded")
        if query.isEmpty {
            condition = """
                sequence = (SELECT MAX(sequence) FROM entry_search WHERE session_id = :id AND is_final = 1)
                OR sequence = (SELECT MAX(sequence) FROM entry_search WHERE session_id = :id AND role = 'user'
                    AND sequence < (SELECT MAX(sequence) FROM entry_search WHERE session_id = :id AND is_final = 1))
                """
        } else {
            condition = "(\(position)) > 0"
        }
        let rows = try Row.fetchAll(
            database,
            sql:
                "SELECT sequence, (SELECT timestamp FROM entries WHERE entries.session_id = entry_search.session_id "
                + "AND entries.sequence = entry_search.sequence) AS timestamp, role, is_final, CAST(text AS BLOB) AS projection, folded "
                + ", (SELECT payload FROM entries WHERE entries.session_id = entry_search.session_id "
                + "AND entries.sequence = entry_search.sequence) AS payload "
                + "FROM entry_search WHERE session_id = :id AND (\(condition)) ORDER BY sequence DESC LIMIT 5",
            arguments: ["query": Data(query.utf8), "foldedQuery": SessionSearchIndex.folded(query), "id": key(id)])
        let references = try rows.reversed().map { try reference($0, summary: summary, query: query) }
        return SessionReferences.bounded(references)
    }

    private static func reference(_ row: Row, summary: SessionSummary, query: String) throws -> SessionReference {
        guard let payload = row["payload"] as Data? else { throw SessionError.invalidEvent }
        guard let canonical = SessionSearchIndex.readable(try SessionCodec.decode(payload)) else {
            throw SessionError.invalidEvent
        }
        let scalars = canonical.text.unicodeScalars
        guard let projection = row["projection"] as Data?, canonical.text.utf8.elementsEqual(projection),
            canonical.role == row["role"], canonical.isFinal == row["is_final"],
            SessionSearchIndex.folded(canonical.text) == row["folded"] as Data?
        else { throw SessionError.invalidEvent }
        let match = canonical.text.range(of: query, options: .caseInsensitive)?.lowerBound ?? scalars.startIndex
        let offset = max(0, scalars.distance(from: scalars.startIndex, to: match) - 512)
        let begin = scalars.index(scalars.startIndex, offsetBy: offset)
        let end = scalars.index(begin, offsetBy: 4096, limitedBy: scalars.endIndex) ?? scalars.endIndex
        return SessionReference(
            source: SessionCitation(
                sessionID: summary.id, title: summary.title, sequence: row["sequence"], role: row["role"],
                timestamp: Date(timeIntervalSinceReferenceDate: row["timestamp"])),
            text: (offset > 0 ? "[truncated]\n" : "") + String(scalars[begin..<end])
                + (end != scalars.endIndex ? "\n[truncated]" : ""))
    }
}
