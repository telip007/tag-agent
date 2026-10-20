public import Foundation
import GRDB
import ModelKit

/// Measured local volumes and the last provider report, deliberately not a savings estimate.
public struct ContextStatistics: Sendable, Equatable, Codable {
    /// Retained artifacts, including source and history manifests.
    public let retainedCount: Int
    /// Canonical artifact bytes on disk.
    public let retainedBytes: Int
    /// Artifacts explicitly marked incomplete.
    public let incompleteCount: Int
    /// Committed model-facing tool results.
    public let toolResultCount: Int
    /// Exact UTF-8 bytes in those results, including retrieval responses.
    public let toolResultBytes: Int
    /// Results recorded as failed; not inferred from arbitrary output text.
    public let failedToolResults: Int
    /// Whether the explicit compact request view is enabled.
    public let compacted: Bool
    /// Last reported input tokens; nil remains unknown.
    public let lastInputTokens: Int?
    /// Last reported cache-read tokens; nil remains unknown.
    public let lastCacheReadTokens: Int?
    /// Last reported cache-write tokens; nil remains unknown.
    public let lastCacheWriteTokens: Int?

    enum CodingKeys: String, CodingKey {
        case retainedCount = "retained_count"
        case retainedBytes = "retained_bytes"
        case incompleteCount = "incomplete_count"
        case toolResultCount = "tool_result_count"
        case toolResultBytes = "tool_result_bytes"
        case failedToolResults = "failed_tool_results"
        case compacted
        case lastInputTokens = "last_input_tokens"
        case lastCacheReadTokens = "last_cache_read_tokens"
        case lastCacheWriteTokens = "last_cache_write_tokens"
    }
}

extension SQLiteSessionStore {
    /// Reads one session's statistics without interpreting stored bytes as provider tokens.
    @concurrent public func contextStatistics(_ id: UUID) async throws -> ContextStatistics {
        try await database.read { database in
            let summary = try Self.summary(id, database: database)
            let retained = try Self.outputStatistics(id, database: database)
            let outputs = try Row.fetchCursor(
                database, sql: "SELECT metadata FROM context_outputs WHERE session_id = ?", arguments: [Self.key(id)])
            var incomplete = 0
            while let row = try outputs.next() {
                if try !JSONDecoder().decode(OutputReference.self, from: row["metadata"]).complete { incomplete += 1 }
            }
            let entries = try Row.fetchCursor(
                database, sql: "SELECT payload FROM entries WHERE session_id = ?", arguments: [Self.key(id)])
            var count = 0
            var bytes = 0
            var failed = 0
            while let row = try entries.next() {
                if case .toolFinished(let result) = try SessionCodec.decode(row["payload"]) {
                    count += 1
                    bytes += result.output.utf8.count
                    if result.failed { failed += 1 }
                }
            }
            return ContextStatistics(
                retainedCount: retained.outputCount, retainedBytes: retained.storedBytes, incompleteCount: incomplete,
                toolResultCount: count, toolResultBytes: bytes, failedToolResults: failed,
                compacted: summary.contextProjection != nil, lastInputTokens: summary.latestUsage?.inputTokens,
                lastCacheReadTokens: summary.latestUsage?.cachedInputTokens,
                lastCacheWriteTokens: summary.latestUsage?.cacheWriteInputTokens)
        }
    }
}
