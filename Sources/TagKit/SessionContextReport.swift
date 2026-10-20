import Foundation
import SessionKit

extension SessionController {
    /// Local read-only reports; no user message or model request is created.
    public func showContext(doctor: Bool = false) async throws {
        guard !isClosed, let id = active?.id else { throw SessionControlError.paused }
        let stats = try await store.contextStatistics(id)
        var lines = [
            "Retained: \(stats.retainedCount) · \(stats.retainedBytes) bytes",
            "Tool results: \(stats.toolResultCount) · \(stats.toolResultBytes) bytes presented",
            "Partial artifacts: \(stats.incompleteCount) · view: \(stats.compacted ? "compacted" : "full")",
        ]
        if doctor {
            let check = try await store.contextDoctor(id)
            lines.append(
                "Database \(check.databaseOK ? "OK" : "needs attention") · Journal \(check.journalOK ? "OK" : "needs attention")"
            )
            lines.append(
                "Evidence \(check.evidenceOK ? "OK" : "needs attention") · Index \(check.indexOK ? "OK" : "needs attention")"
            )
            if check.needsRecovery { lines.append("Interrupted work awaits recovery; no action was replayed.") }
        } else if let tokens = stats.lastInputTokens {
            lines.append(
                "Last provider input: \(tokens) tokens · cache read: \(stats.lastCacheReadTokens.map(String.init) ?? "unknown")"
            )
        }
        lines.append("/context off hides this report")
        guard active?.id == id else { throw SessionControlError.busy }
        contextReport = lines.joined(separator: "\n")
    }
}
