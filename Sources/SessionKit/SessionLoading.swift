public import Foundation
import GRDB

extension SQLiteSessionStore {
    /// Reads a consistent snapshot, including corrupt/version checks.
    public func load(_ id: UUID) async throws -> SessionSnapshot {
        try await database.read { try Self.snapshot(id, database: $0) }
    }

    /// Resolves interrupted operations without invoking a model or executing a tool.
    /// The caller must own this session before allowing continuation.
    public func recover(_ id: UUID) async throws -> SessionSnapshot {
        try await database.write { database in
            let snapshot = try Self.snapshot(id, database: database)
            let events = try SessionRecovery.events(for: snapshot.entries)
            for event in events { try Self.append(id, event: event, database: database) }
            return events.isEmpty ? snapshot : try Self.snapshot(id, database: database)
        }
    }

    static func snapshot(_ id: UUID, database: Database) throws -> SessionSnapshot {
        let summary = try summary(id, database: database)
        let entries = try readEntries(id, after: nil, limit: nil, database: database)
        guard summary.nextSequence == Int64(entries.count),
            entries.enumerated().allSatisfy({ Int64($0.offset) == $0.element.sequence })
        else { throw SessionError.invalidEvent }
        let latest = entries.last {
            if case .contextProjection = $0.event { return true }
            return false
        }
        if let latest, case .contextProjection(let projection) = latest.event {
            guard summary.contextProjection == (projection.archiveID == nil ? nil : projection) else {
                throw SessionError.invalidEvent
            }
            try ContextProjectionValidation.validate(
                projection, session: id, at: latest.sequence, entries: entries, database: database)
        } else if summary.contextProjection != nil {
            throw SessionError.invalidEvent
        }
        return SessionSnapshot(summary: summary, entries: entries)
    }

    static func readEntries(_ id: UUID, after: Int64?, limit: Int?, database: Database) throws -> [SessionEntry] {
        let rows = try Row.fetchAll(
            database,
            sql: "SELECT sequence, timestamp, payload FROM entries WHERE session_id = ? AND sequence > ? "
                + "ORDER BY sequence LIMIT ?",
            arguments: [key(id), after ?? -1, limit.map { max(0, $0) } ?? -1])
        return try rows.map { row in
            SessionEntry(
                sessionID: id, sequence: row["sequence"],
                timestamp: Date(timeIntervalSinceReferenceDate: row["timestamp"]),
                event: try SessionCodec.decode(row["payload"]))
        }
    }
}
