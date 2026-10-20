import Foundation
import Observation
import SessionKit

/// The editor owns unsent typing across async command and save acknowledgments.
@MainActor
@Observable
final class WorkspaceEditor {
    var text: String {
        didSet {
            guard !isSwitching else { return }
            controller?.draft.text = text
            if text.isEmpty, controller?.draft.pendingInputID != nil {
                controller?.draft.pendingInputID = nil
                controller?.draft.references = []
            }
        }
    }
    var error: String?
    var history = InputHistory()
    private(set) var isSubmitting = false
    @ObservationIgnored private var isSwitching = false
    @ObservationIgnored private let controller: SessionController?
    @ObservationIgnored private let session: ChatSession

    init(session: ChatSession, controller: SessionController? = nil) {
        self.session = session
        self.controller = controller
        text = controller?.draft.text ?? ""
    }

    func sessionChanged() {
        if !isSwitching { text = controller?.draft.text ?? "" }
        history.reset()
        error = nil
    }

    func pendingChanged() {
        if !isSubmitting, !isSwitching { text = controller?.draft.text ?? text }
    }

    func submit(models: ModelFlow, sessions: SessionFlow?) async {
        guard !isSubmitting, !isSwitching else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        error = nil
        let submitted = text
        if let command = ModelCommand(submitted) {
            text = ""
            history.reset()
            await models.run(command)
        } else if let command = SessionCommand(submitted), let controller {
            await submit(command, controller: controller, sessions: sessions)
        } else if let controller {
            do {
                try await controller.submit(submitted)
                text = SessionController.remainingText(text, after: submitted)
                history.reset()
            } catch { self.error = error.localizedDescription }
        } else if session.submit(submitted) {
            text = ""
            history.reset()
        }
    }

    private func submit(_ command: SessionCommand, controller: SessionController, sessions: SessionFlow?) async {
        let switchesSession =
            switch command {
            case .new, .resume: true
            default: false
            }
        let submitted = text
        let source = controller.active?.id
        text = ""
        controller.draft.text = ""
        do {
            if switchesSession {
                try await transition { try await run(command, controller: controller, sessions: sessions) }
            } else {
                try await run(command, controller: controller, sessions: sessions)
            }
            if case .pending = command { text = controller.draft.text }
            history.reset()
        } catch {
            if text.isEmpty, controller.active?.id == source { text = submitted }
            self.error = error.localizedDescription
        }
        controller.draft.text = text
    }

    /// Every navigation entry point buffers new typing until its destination is known.
    func transition(_ action: () async throws -> Void) async throws {
        guard !isSwitching, let controller else { throw SessionControlError.busy }
        let source = controller.active?.id
        let sourceText = text
        isSwitching = true
        text = ""
        defer {
            isSwitching = false
            controller.draft.text = text
        }
        do {
            try await action()
            text = controller.draft.text + text
        } catch {
            text = (controller.active?.id == source ? sourceText : controller.draft.text) + text
            throw error
        }
    }

    private func run(_ command: SessionCommand, controller: SessionController, sessions: SessionFlow?) async throws {
        switch command {
        case .browse: await sessions?.open()
        case .new: try await controller.newSession()
        case .resume(let prefix): try await controller.switchTo(controller.store.resolve(prefix).id)
        case .rename(let title):
            guard let active = controller.active, !controller.isReadOnly else { throw SessionControlError.paused }
            try await controller.store.rename(active.id, title: title)
            controller.active = try await controller.store.summary(active.id)
        case .reference(let prefix, let query):
            if let prefix {
                let source = try await controller.store.resolve(prefix)
                try await sessions?.reference(source.id, query: query)
            } else {
                await sessions?.open(purpose: .reference)
            }
        case .unreference: controller.draft.references = []
        case .pending: try controller.reviewPending()
        case .retry: try await controller.retry()
        case .invalid(let usage): throw SessionControlError.readOnly(usage)
        }
    }
}
