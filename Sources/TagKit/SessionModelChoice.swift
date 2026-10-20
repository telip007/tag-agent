import Foundation
import ModelKit
import SessionKit

extension SessionController {
    /// Persists a user choice at a ready boundary; active inference finishes with its recorded model.
    public func modelChosen() async throws {
        guard !isClosed else { return }
        guard !isReadOnly else { return }
        modelSavePending = true
        guard pauseReason == nil else { throw SessionControlError.paused }
        guard !isBusy else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        do {
            await stopAgent()
            try await saveModelChoice()
            try await reloadForContinuation()
        } catch {
            pauseReason = "Could not save the model choice: \(error.localizedDescription)"
            session.handle(
                .failure(message: pauseReason ?? "Model choice failed.", recovery: "Use /retry after fixing storage."))
            throw error
        }
    }

    /// Called only after the foreground task has really ended, while its lock is still held.
    func saveModelChoice() async throws {
        guard let active, ownership != nil, !isReadOnly, let model = selection.current else { return }
        do {
            let current = try await store.summary(active.id)
            let context = SessionContext(
                prompt: SystemPrompt.render(tools: tools, environment: environment, model: model.description.name),
                model: model.entry.ref, effort: model.effort)
            if current.context != context { try await store.append(active.id, event: .context(context)) }
            modelSavePending = false
        } catch {
            pauseReason = "Could not save the model choice: \(error.localizedDescription)"
            throw error
        }
    }
}
