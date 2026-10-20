import Foundation
import SessionKit

extension SessionController {
    func receive(_ event: AgentEvent, sessionID: UUID) {
        guard active?.id == sessionID else { return }
        session.handle(event)
        if case .status = event {
            Task { [weak self] in
                guard let self, let summary = try? await self.store.summary(sessionID), self.active?.id == sessionID
                else { return }
                self.active = summary
                if self.modelSavePending, self.session.isWaitingForInput { try? await self.modelChosen() }
            }
        }
    }

    func handleFailure(_ error: any Error, sessionID: UUID) {
        guard active?.id == sessionID, !Task.isCancelled else { return }
        pauseReason = "Could not save this session: \(error.localizedDescription)"
        session.stopDispatching()
        session.handle(
            .failure(
                message: pauseReason ?? "Save failed.",
                recovery: "Use /retry after fixing storage. Accepted inputs remain saved."))
    }
}
