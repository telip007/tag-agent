public import Foundation
import GRDB

/// Keyset cursor, unaffected by inserting newer sessions between pages.
public struct SessionCursor: Sendable {
    let date: Date
    let id: UUID

    /// Continues after this row in descending recent-session order.
    public init(_ summary: SessionSummary) {
        date = summary.lastOpenedAt
        id = summary.id
    }
}

extension SQLiteSessionStore {
    /// Resolves a full UUID or an unambiguous hexadecimal/hyphen prefix.
    public func resolve(_ prefix: String) async throws -> SessionSummary {
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isHexDigit || $0 == "-" }) else {
            throw SessionError.notFound
        }
        return try await database.read { database in
            let values = try Data.fetchAll(
                database, sql: "SELECT metadata FROM sessions WHERE id LIKE ? LIMIT 2",
                arguments: [prefix.lowercased() + "%"])
            guard let data = values.first else { throw SessionError.notFound }
            guard values.count == 1 else { throw SessionError.ambiguousID }
            return try JSONDecoder().decode(SessionSummary.self, from: data)
        }
    }

    /// Lists at most 50 rows, with title and readable-history matching and keyset pagination.
    public func list(
        workspace: String?, query: String = "", after: SessionCursor? = nil, limit: Int = 50
    ) async throws -> [SessionSummary] {
        try await database.read { database in
            let date = after?.date.timeIntervalSinceReferenceDate
            let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
            let matching =
                "SELECT 1 FROM entry_search WHERE session_id = sessions.id AND (\(SessionSearchIndex.position("text", foldedColumn: "folded"))) > 0"
            let values = try Data.fetchAll(
                database,
                sql: """
                    SELECT metadata FROM sessions
                    WHERE (:workspace IS NULL OR workspace = :workspace)
                    AND (length(:query) = 0 OR (\(SessionSearchIndex.position("title"))) > 0 OR EXISTS (\(matching)))
                    AND (:date IS NULL OR last_opened < :date OR (last_opened = :date AND id < :id))
                    ORDER BY last_opened DESC, id DESC LIMIT :limit
                    """,
                arguments: [
                    "workspace": workspace, "query": Data(query.utf8), "foldedQuery": SessionSearchIndex.folded(query),
                    "date": date,
                    "id": after.map { Self.key($0.id) }, "limit": min(50, max(0, limit)),
                ])
            return try values.map { try JSONDecoder().decode(SessionSummary.self, from: $0) }
        }
    }

    /// Reads the explicit workspace pointer, falling back to deterministic recency.
    public func lastSession(workspace: String) async throws -> SessionSummary? {
        if let selected = try await database.read({ database -> SessionSummary? in
            guard
                let data = try Data.fetchOne(
                    database,
                    sql: """
                        SELECT metadata FROM sessions JOIN workspace_state ON sessions.id = workspace_state.session_id
                        WHERE workspace_state.workspace = ? AND sessions.workspace = ?
                        """, arguments: [workspace, workspace])
            else { return nil }
            return try JSONDecoder().decode(SessionSummary.self, from: data)
        }) {
            return selected
        }
        return try await list(workspace: workspace, limit: 1).first
    }

    /// Updates recency and the workspace's last-opened pointer atomically.
    public func markOpened(_ id: UUID) async throws {
        try await database.write { database in
            var summary = try Self.summary(id, database: database)
            summary.lastOpenedAt = Date()
            try Self.update(summary, database: database)
            try database.execute(
                sql: """
                    INSERT INTO workspace_state(workspace, session_id) VALUES (?, ?)
                    ON CONFLICT(workspace) DO UPDATE SET session_id = excluded.session_id
                    """, arguments: [summary.workspace, Self.key(id)])
        }
    }

    /// Changes only this session's display title, without a model request.
    public func rename(_ id: UUID, title: String) async throws {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty else { throw SessionError.invalidEvent }
        try await database.write { database in
            var summary = try Self.summary(id, database: database)
            summary.title = title
            summary.hasUserInput = true
            try Self.update(summary, database: database)
        }
    }

    /// Saves unsent text and reference previews on explicit clean boundaries.
    public func saveDraft(_ id: UUID, draft: SessionDraft) async throws {
        try await database.write { database in
            _ = try Self.summary(id, database: database)
            try database.execute(
                sql: """
                    INSERT INTO session_drafts(session_id, payload) VALUES (?, ?)
                    ON CONFLICT(session_id) DO UPDATE SET payload = excluded.payload
                    """, arguments: [Self.key(id), try JSONEncoder().encode(draft)])
        }
    }

    /// Returns a clean draft only when the session exists.
    public func draft(_ id: UUID) async throws -> SessionDraft {
        try await database.read { database in
            _ = try Self.summary(id, database: database)
            guard
                let data = try Data.fetchOne(
                    database, sql: "SELECT payload FROM session_drafts WHERE session_id = ?",
                    arguments: [Self.key(id)])
            else { return SessionDraft() }
            return try JSONDecoder().decode(SessionDraft.self, from: data)
        }
    }
}
