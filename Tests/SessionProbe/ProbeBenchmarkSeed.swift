import Foundation
import GRDB
import ModelKit
import SessionKit

/// Bulk setup is excluded from measured operations; records match the public store format.
enum ProbeBenchmarkSeed {
    struct Fixture: Codable {
        var small: UUID
        var large: UUID
        var source: UUID
        var sessions: Int
        var searchableEntries: Int
        var databaseBytes: Int64
        var indexBytes: Int64?
        var sqlite: String
        var sourceID: String
        var fts5: Bool
    }

    @concurrent
    static func run(store: SQLiteSessionStore, root: URL) async throws {
        let context = SessionContext(
            prompt: "Generated benchmark context", model: ModelRef(provider: .codex, model: "fixture"), effort: nil)
        let template = try await store.create(
            workspace: root.standardizedFileURL.resolvingSymlinksInPath().path, context: context)
        let queue = try DatabaseQueue(path: store.directory.appending(path: "sessions.sqlite").path)
        try await queue.write { database in
            try populate(database, template: template, root: root)
        }
        let diagnostics = try await store.diagnostics()
        let sizes = try await queue.read { database in
            guard try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM sessions") == 10_000,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM entry_search") == 100_000
            else { throw ProbeFailure.usage }
            let bytes =
                (try Int64.fetchOne(database, sql: "PRAGMA page_count") ?? 0)
                * (try Int64.fetchOne(database, sql: "PRAGMA page_size") ?? 0)
            let indexes = try? Int64.fetchOne(
                database,
                sql:
                    "SELECT SUM(pgsize) FROM dbstat WHERE name IN (SELECT name FROM sqlite_master WHERE type = 'index' OR name LIKE 'entry_search_fts%')"
            )
            return (bytes, indexes)
        }
        let fixture = Fixture(
            small: try identifier(9998), large: try identifier(9999), source: try identifier(0), sessions: 10_000,
            searchableEntries: 100_000, databaseBytes: sizes.0, indexBytes: sizes.1,
            sqlite: diagnostics.version, sourceID: diagnostics.sourceID, fts5: diagnostics.fts5)
        try JSONEncoder().encode(fixture).write(to: root.appending(path: "benchmark-fixture.json"), options: .atomic)
    }

    private static func populate(_ database: Database, template: SessionSummary, root: URL) throws {
        try database.execute(sql: "DELETE FROM entries; DELETE FROM sessions")
        let context = template.context
        for index in 0..<10_000 {
            let count = index == 9999 ? 10_000 : index == 9998 ? 1000 : index < 982 ? 8 : 9
            let size = index >= 9998 ? 4096 : 256
            var summary = template
            summary.id = try identifier(index)
            summary.providerSessionID = summary.id.uuidString
            summary.title = "Generated task \(index)"
            summary.lastOpenedAt = Date(timeIntervalSinceReferenceDate: Double(index))
            summary.nextSequence = Int64(count + 1)
            try database.execute(
                sql: "INSERT INTO sessions(id, workspace, title, last_opened, metadata) VALUES (?, ?, ?, ?, ?)",
                arguments: [
                    summary.id.uuidString.lowercased(), summary.workspace, summary.title, Double(index),
                    try JSONEncoder().encode(summary),
                ])
            try insert(.context(context), text: nil, sequence: 0, session: summary.id, database: database)
            let text = "needle evidence \(index)\nUnicode 🌳\t" + String(repeating: "x", count: size - 40)
            let event = SessionEvent.assistant(SessionAssistant(message: AssistantMessage(text: text), usage: nil))
            for sequence in 1...count {
                try insert(event, text: text, sequence: sequence, session: summary.id, database: database)
            }
            if index >= 9998 {
                try seedJSONL(root: root, id: summary.id, count: count, context: context, event: event)
            }
        }
    }

    private static func identifier(_ index: Int) throws -> UUID {
        let hex = String(index + 1, radix: 16)
        let suffix = String(repeating: "0", count: max(0, 12 - hex.count)) + hex
        guard let id = UUID(uuidString: "00000000-0000-4000-8000-" + suffix) else {
            throw ProbeFailure.usage
        }
        return id
    }

    private static func insert(
        _ event: SessionEvent, text: String?, sequence: Int, session: UUID, database: Database
    ) throws {
        let id = session.uuidString.lowercased()
        try database.execute(
            sql: "INSERT INTO entries(session_id, sequence, timestamp, payload) VALUES (?, ?, 0, ?)",
            arguments: [id, sequence, try SessionCodec.encode(event)])
        if let text {
            try database.execute(
                sql:
                    "INSERT INTO entry_search(session_id, sequence, timestamp, role, text, is_final, folded) VALUES (?, ?, 0, 'assistant', ?, 1, ?)",
                arguments: [
                    id, sequence, text,
                    Data(
                        text.folding(options: .caseInsensitive, locale: nil).decomposedStringWithCanonicalMapping.utf8),
                ])
        }
    }

    private static func seedJSONL(
        root: URL, id: UUID, count: Int, context: SessionContext, event: SessionEvent
    ) throws {
        let url = root.appending(path: id.uuidString.lowercased() + ".jsonl")
        try Data().write(to: url, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        for sequence in 0...count {
            try ProbeBenchmark.writeJSONL(
                sequence == 0 ? .context(context) : event, sequence: sequence, id: id, file: file)
        }
        try ProbeBenchmark.flush(file)
    }
}
