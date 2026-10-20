import Foundation
import GRDB
import ModelKit

enum SessionSearchIndex {
    static func migrate(_ database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE entry_search (
                    session_id TEXT NOT NULL REFERENCES sessions(id), sequence INTEGER NOT NULL,
                    timestamp REAL NOT NULL, role TEXT NOT NULL, text TEXT NOT NULL, is_final INTEGER NOT NULL,
                    folded BLOB NOT NULL DEFAULT X'',
                    UNIQUE(session_id, sequence)
                );
                CREATE INDEX entry_search_recent ON entry_search(session_id, sequence DESC);
                """)
        try rebuild(database)
        try database.execute(sql: "PRAGMA user_version = 2")
    }

    static func rebuild(_ database: Database) throws {
        try database.execute(sql: "DELETE FROM entry_search")
        let cursor = try Row.fetchCursor(database, sql: "SELECT session_id, sequence, timestamp, payload FROM entries")
        while let row = try cursor.next() {
            try insert(
                session: row["session_id"], sequence: row["sequence"], timestamp: row["timestamp"],
                event: SessionCodec.decode(row["payload"]), database: database)
        }
    }

    static func insert(
        session: String, sequence: Int64, timestamp: Double, event: SessionEvent, database: Database
    ) throws {
        guard let value = readable(event), !value.text.isEmpty else { return }
        try database.execute(
            sql:
                "INSERT INTO entry_search(session_id, sequence, timestamp, role, text, is_final, folded) VALUES (?, ?, ?, ?, CAST(? AS TEXT), ?, ?)",
            arguments: [
                session, sequence, timestamp, value.role, Data(value.text.utf8), value.isFinal, folded(value.text),
            ])
    }

    struct Readable {
        var role: String
        var text: String
        var isFinal: Bool
    }

    static func readable(_ event: SessionEvent) -> Readable? {
        switch event {
        case .user(let user): return Readable(role: "user", text: user.raw, isFinal: false)
        case .assistant(let reply):
            let names = reply.message.toolCalls.map(\.name)
            return Readable(
                role: "assistant",
                text: ([reply.message.text ?? ""] + names).filter { !$0.isEmpty }.joined(separator: "\n"),
                isFinal: names.isEmpty
            )
        case .toolFinished(let result):
            return Readable(role: "tool", text: result.call.name + "\n" + result.output, isFinal: false)
        default: return nil
        }
    }

    /// Canonically decomposed case folds supply candidates, never the final match decision.
    static func folded(_ text: String) -> Data {
        Data(text.folding(options: .caseInsensitive, locale: nil).decomposedStringWithCanonicalMapping.utf8)
    }

    /// Word-token FTS cannot supply complete candidates for literal substring search.
    static func position(_ column: String, foldedColumn: String? = nil) -> String {
        let literal =
            "CASE WHEN length(\(column)) = length(CAST(\(column) AS BLOB)) "
            + "AND length(CAST(:query AS TEXT)) = length(:query) "
            + "THEN instr(lower(\(column)), lower(CAST(:query AS TEXT))) "
            + "ELSE tag_literal_position(CAST(\(column) AS BLOB), :query) END"
        guard let foldedColumn else { return literal }
        return "CASE WHEN instr(\(foldedColumn), :foldedQuery) > 0 THEN (\(literal)) ELSE 0 END"
    }

    static func prepare(_ database: Database) {
        database.add(
            function: DatabaseFunction("tag_literal_position", argumentCount: 2, pure: true) { values in
                guard let text = String.fromDatabaseValue(values[0]), let query = String.fromDatabaseValue(values[1]),
                    let range = text.range(of: query, options: .caseInsensitive)
                else { return 0 }
                return text.unicodeScalars.distance(from: text.startIndex, to: range.lowerBound) + 1
            })
    }
}
