import CryptoKit
public import Foundation
import GRDB

extension SQLiteSessionStore {
    /// Explicit deterministic compaction, with no model call and no history deletion.
    public func compactContext(
        _ id: UUID, keepRecentGroups: Int = 8, limits: OutputLimits = OutputLimits()
    ) async throws -> SessionContextProjection {
        guard (1...32).contains(keepRecentGroups) else { throw SessionError.invalidEvent }
        let snapshot = try await load(id)
        guard try SessionRecovery.events(for: snapshot.entries).isEmpty else { throw SessionError.invalidEvent }
        let manifest = ContextProjectionManifest(
            throughSequence: snapshot.summary.nextSequence - 1, keepRecentGroups: keepRecentGroups,
            groups: ContextProjectionLayout.omitted(snapshot.entries, keeping: keepRecentGroups))
        let candidate = SessionContextProjection(
            throughSequence: manifest.throughSequence, keepRecentGroups: keepRecentGroups,
            archiveID: "00000000-0000-0000-0000-000000000000")
        let removed = ContextProjectionLayout.omittedBytes(snapshot.entries, groups: manifest.groups)
        let archive: OutputReference?
        if manifest.groups.isEmpty || removed <= candidate.notice.utf8.count + 256 {
            archive = nil
        } else {
            let data = try JSONEncoder().encode(manifest)
            guard let text = String(validating: data, as: UTF8.self) else { throw SessionError.invalidEvent }
            archive = try await saveOutput(id, text: text, source: "context-history", limits: limits)
        }
        try Task.checkCancellation()
        let projection = SessionContextProjection(
            throughSequence: manifest.throughSequence, keepRecentGroups: keepRecentGroups, archiveID: archive?.id)
        try await append(id, event: .contextProjection(projection))
        return projection
    }

    /// Restores original request history; retained evidence is not purged.
    public func restoreFullContext(_ id: UUID) async throws {
        let summary = try await summary(id)
        try await append(
            id,
            event: .contextProjection(
                SessionContextProjection(
                    throughSequence: summary.nextSequence - 1, keepRecentGroups: 8, archiveID: nil)))
    }
}

struct ContextProjectionManifest: Codable, Equatable {
    var version = 1
    let throughSequence: Int64
    let keepRecentGroups: Int
    let groups: [ContextProjectionGroup]
    var readTool = "read_history"
}

enum ContextProjectionValidation {
    static func validate(
        _ projection: SessionContextProjection, session: UUID, at sequence: Int64, entries: [SessionEntry],
        database: Database
    ) throws {
        try projection.validate()
        guard projection.throughSequence == sequence - 1 else { throw SessionError.invalidEvent }
        let prefix = entries.filter { $0.sequence <= projection.throughSequence }
        guard try SessionRecovery.events(for: prefix).isEmpty else { throw SessionError.invalidEvent }
        guard let id = projection.archiveID else { return }
        let manifest = try manifest(id, session: session, database: database)
        guard manifest.version == 1, manifest.readTool == "read_history",
            manifest.throughSequence == projection.throughSequence,
            manifest.keepRecentGroups == projection.keepRecentGroups,
            manifest.groups == ContextProjectionLayout.omitted(prefix, keeping: projection.keepRecentGroups)
        else { throw SessionError.invalidEvent }
    }

    private static func manifest(_ id: String, session: UUID, database: Database) throws -> ContextProjectionManifest {
        guard
            let row = try Row.fetchOne(
                database,
                sql: "SELECT metadata, CASE WHEN length(content) <= 33554432 THEN content ELSE NULL END AS content "
                    + "FROM context_outputs WHERE id = ? AND session_id = ?",
                arguments: [id, SQLiteSessionStore.key(session)]), let data = row["content"] as Data?
        else { throw SessionError.invalidEvent }
        let reference = try JSONDecoder().decode(OutputReference.self, from: row["metadata"])
        let digest = SHA256.hash(data: data).map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0" + hex : hex
        }.joined()
        guard reference.id == id, reference.source == "context-history", reference.complete,
            reference.byteCount == data.count, reference.sha256 == digest
        else { throw SessionError.invalidEvent }
        return try JSONDecoder().decode(ContextProjectionManifest.self, from: data)
    }
}
