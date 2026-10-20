import Foundation
import SessionKit

/// Durable execution manifest coordinates, not a summary of the output text.
struct ContextBatchEntry: Encodable {
    let index: Int
    let label: String?
    let status: String
    let outputID: String?
    let bytes: Int
    let failed: Bool
    let complete: Bool
    let exitCode: Int32?
    let timedOut: Bool
    var error: String?

    enum CodingKeys: String, CodingKey {
        case outputID = "output_id"
        case exitCode = "exit_code"
        case timedOut = "timed_out"
        case index, label, status, bytes, failed, complete, error
    }

    static func skipped(index: Int, label: String?) -> Self {
        Self(
            index: index, label: label, status: "not_started", outputID: nil, bytes: 0,
            failed: true, complete: false, exitCode: nil, timedOut: false,
            error: "prior capture was incomplete or batch deadline expired")
    }

    static func execute(
        _ context: NativeContext, command: ContextBatch.Command, index: Int, batch: String,
        callID: String?, timeout: Duration
    ) async throws -> Self {
        do {
            let executor = try context.requireExecutor()
            let outcome = try await executor.run(
                command.command,
                byteLimit: min(context.limits.perOutput, 32 * 1024 * 1024), timeout: timeout)
            let reference = try await context.retain(
                outcome, source: "batch:\(batch):\(index)", callID: callID)
            return Self(
                index: index, label: command.label, status: outcome.complete ? "completed" : "incomplete",
                outputID: reference.id, bytes: reference.byteCount, failed: outcome.failed, complete: outcome.complete,
                exitCode: outcome.exitCode, timedOut: outcome.timedOut)
        } catch {
            if Task.isCancelled || error is CancellationError || error is ContextStorageFailure { throw error }
            return Self(
                index: index, label: command.label, status: "capture_unavailable", outputID: nil, bytes: 0,
                failed: true, complete: false, exitCode: nil, timedOut: false,
                error: ContextText.prefix(error.localizedDescription, bytes: 256))
        }
    }
}
