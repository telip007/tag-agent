import Foundation
import GRDB
import ModelKit

extension SQLiteSessionStore {
    static func append(_ id: UUID, event: SessionEvent, database: Database) throws {
        var summary = try summary(id, database: database)
        if case .contextProjection(let projection) = event {
            try ContextProjectionValidation.validate(
                projection, session: id, at: summary.nextSequence,
                entries: readEntries(id, after: nil, limit: nil, database: database), database: database)
        }
        let now = Date()
        try database.execute(
            sql: "INSERT INTO entries(session_id, sequence, timestamp, payload) VALUES (?, ?, ?, ?)",
            arguments: [
                key(id), summary.nextSequence, now.timeIntervalSinceReferenceDate, try SessionCodec.encode(event),
            ])
        try SessionSearchIndex.insert(
            session: key(id), sequence: summary.nextSequence, timestamp: now.timeIntervalSinceReferenceDate,
            event: event, database: database)
        summary.nextSequence += 1
        summary.updatedAt = now
        project(event, into: &summary)
        try update(summary, database: database)
    }

    private static func project(_ event: SessionEvent, into summary: inout SessionSummary) {
        switch event {
        case .context(let context):
            summary.context = context
            summary.contextRevision += 1
            summary.latestUsage = nil
        case .contextProjection(let projection):
            summary.contextProjection = projection.archiveID == nil ? nil : projection
            summary.latestUsage = nil
        case .user(let user):
            summary.preview = preview(user.raw)
            summary.lastDate = user.date
            if !summary.hasUserInput {
                summary.title = String(user.raw.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(80))
            }
            summary.hasUserInput = true
        case .assistant(let reply):
            if let text = reply.message.text, !text.isEmpty { summary.preview = preview(text) }
            summary.latestUsage = reply.usage
            if let usage = reply.usage {
                summary.contextTokens = usage.totalTokens
                summary.cost += usage.cost ?? 0
            }
        default: break
        }
    }

    private static func preview(_ text: String) -> String {
        String(text.prefix(240).split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(160))
    }
}
