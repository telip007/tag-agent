import Foundation
import SessionKit

extension SessionController {
    /// Changes only the model's request view at an explicit ready boundary.
    public func setCompaction(_ enabled: Bool) async throws {
        guard !isClosed, pauseReason == nil else { throw SessionControlError.paused }
        guard !isBusy else { throw SessionControlError.busy }
        guard !isReadOnly, ownership != nil, let active else {
            throw SessionControlError.readOnly(readOnlyReason ?? "Open a writable session before changing context.")
        }
        isTransitioning = true
        defer { isTransitioning = false }
        do {
            try await saveDraft()
            await stopAgent()
            if enabled {
                _ = try await store.compactContext(active.id)
            } else {
                try await store.restoreFullContext(active.id)
            }
            try await reloadForContinuation()
        } catch {
            pauseReason = "Could not change the context view: \(error.localizedDescription)"
            session.handle(
                .failure(
                    message: pauseReason ?? "Context change failed.",
                    recovery: "Your full history was kept. Use /retry to reload the saved state."))
            throw error
        }
    }
}
