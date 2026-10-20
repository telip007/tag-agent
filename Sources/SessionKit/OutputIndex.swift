import Foundation
import GRDB

/// Derived lexical search data; canonical blobs never depend on FTS availability.
enum OutputIndex {
    static func migrate(_ database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE context_output_chunks (
                    rowid INTEGER PRIMARY KEY,
                    output_id TEXT NOT NULL REFERENCES context_outputs(id) ON DELETE CASCADE,
                    byte_offset INTEGER NOT NULL,
                    text TEXT NOT NULL
                );
                CREATE INDEX context_chunks_output ON context_output_chunks(output_id, byte_offset);
                """)
        do {
            try database.execute(
                sql: "CREATE VIRTUAL TABLE context_output_fts USING fts5(text, tokenize='porter unicode61')")
        } catch let error as DatabaseError where error.message?.contains("no such module: fts5") == true {
            // Exact literal search remains available on builds without FTS5.
        }
        let cursor = try Row.fetchCursor(database, sql: "SELECT id, content FROM context_outputs ORDER BY rowid")
        while let row = try cursor.next() {
            try insert(row["content"], id: row["id"], database: database)
        }
        try database.execute(sql: "PRAGMA user_version = 5")
    }

    static func insert(_ content: Data, id: String, database: Database) throws {
        let hasFTS = try database.tableExists("context_output_fts")
        try forEachChunk(content) { offset, data in
            try database.execute(
                sql: "INSERT INTO context_output_chunks(output_id, byte_offset, text) VALUES (?, ?, CAST(? AS TEXT))",
                arguments: [id, offset, data])
            if hasFTS {
                try database.execute(
                    sql: "INSERT INTO context_output_fts(rowid, text) VALUES (?, CAST(? AS TEXT))",
                    arguments: [database.lastInsertedRowID, data])
            }
        }
    }

    /// Checks the exact deterministic layout, including overlap needed for boundary queries.
    static func matches(_ content: Data, id: String, database: Database) throws -> Bool {
        let rows = try Row.fetchCursor(
            database,
            sql:
                "SELECT byte_offset, CAST(text AS BLOB) AS bytes FROM context_output_chunks WHERE output_id = ? ORDER BY byte_offset, rowid",
            arguments: [id])
        var valid = true
        try forEachChunk(content) { offset, data in
            guard valid else { return }
            guard let row = try rows.next(), row["byte_offset"] as Int == offset, row["bytes"] as Data == data else {
                valid = false
                return
            }
        }
        guard valid else { return false }
        return try rows.next() == nil
    }

    private static func forEachChunk(_ content: Data, body: (Int, Data) throws -> Void) throws {
        var offset = 0
        while offset < content.count {
            let end = boundary(in: content, from: offset)
            try body(offset, content.subdata(in: offset..<end))
            guard end < content.count else { break }
            // A query may be up to 1024 UTF-8 bytes. Retain that overlap so
            // identifiers straddling a chunk boundary remain exact matches.
            var next = end - 1024
            while next > 0, content[next] & 0xC0 == 0x80 { next -= 1 }
            guard next > offset else { throw OutputError.invalidEvidence }
            offset = next
        }
    }

    private static func boundary(in content: Data, from start: Int) -> Int {
        var end = min(start + 4096, content.count)
        // The final window must consume the tail even without a final newline.
        // Otherwise choosing the same last newline makes overlap stop advancing.
        guard end < content.count else { return end }
        while end < content.count, content[end] & 0xC0 == 0x80 { end -= 1 }
        if let newline = content[start..<end].lastIndex(of: 10), newline >= start + (end - start) / 2 {
            end = newline + 1
        }
        return end
    }
}
