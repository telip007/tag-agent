import Foundation
import SessionKit

extension NativeContext {
    /// One persistence boundary shared by native acquisition, analysis and batches.
    func retain(_ outcome: ToolOutcome, source: String, callID: String?) async throws -> OutputReference {
        guard source.utf8.count <= 2048 else { throw ToolError("source label exceeds the 2048-byte limit") }
        do {
            return try await store.saveOutput(
                sessionID, text: outcome.content, source: source, callID: callID,
                complete: outcome.complete, limits: limits)
        } catch { throw ContextStorageFailure(cause: error) }
    }
}
