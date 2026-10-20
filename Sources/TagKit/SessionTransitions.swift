public import Foundation
import ModelKit
import SessionKit

extension SessionController {
    /// Creates a separate empty conversation; the old history and draft remain saved.
    public func newSession() async throws {
        guard !isClosed else { throw SessionControlError.paused }
        guard !isBusy else { throw SessionControlError.busy }
        guard let current = selection.current else { throw SessionControlError.chooseModel }
        isTransitioning = true
        defer { isTransitioning = false }
        let context = SessionContext(
            prompt: SystemPrompt.render(tools: tools, environment: environment, model: current.description.name),
            model: current.entry.ref, effort: current.effort)
        let summary = try await store.create(workspace: workspace, context: context)
        isTransitioning = false
        try await switchTo(summary.id)
    }

    /// Stages the target before ending the old loop. No two loops share the input surface.
    public func switchTo(_ id: UUID) async throws {
        guard !isClosed else { throw SessionControlError.paused }
        guard !isBusy else { throw SessionControlError.busy }
        if active?.id == id { return }
        isTransitioning = true
        defer { isTransitioning = false }
        let summary = try await store.summary(id)
        let staged = try await stage(summary)
        let savedDraft = try await store.draft(id)
        let pending = try await store.pending(id)
        try await saveDraft()
        await stopAgent()
        try await saveModelChoice()
        ownership?.release()
        ownership = staged.owner
        snapshot = staged.snapshot
        active = staged.snapshot.summary
        contextReport = nil
        draft = savedDraft
        pendingForReview = pending
        readOnlyReason = staged.reason
        pauseReason = nil
        session.restore(SessionHydration.project(staged.snapshot), pending: pending)
        try await finishSwitch(summary)
    }

    private func finishSwitch(_ summary: SessionSummary) async throws {
        guard ownership != nil else { return }
        do {
            environment = await probe(environment.workingDirectory)
            _ = await selection.restoreSessionModel(summary.context.model, effort: summary.context.effort)
            try await store.markOpened(summary.id)
        } catch {
            pauseReason = "Could not save the session selection: \(error.localizedDescription)"
            session.handle(
                .failure(
                    message: pauseReason ?? "Session selection failed.", recovery: "Use /retry after fixing storage."))
            throw error
        }
        startAgent()
    }

    struct StagedSession {
        var snapshot: SessionSnapshot
        var owner: SessionOwnership?
        var reason: String?
    }

    private func stage(_ summary: SessionSummary) async throws -> StagedSession {
        var owner: SessionOwnership?
        var reason: String?
        if summary.workspace != workspace || !FileManager.default.fileExists(atPath: workspace) {
            reason = "Read-only · Open Tag in \(summary.workspace) to continue."
        } else {
            do { owner = try SessionOwnership(directory: store.directory, sessionID: summary.id) } catch SessionError
                .sessionInUse
            {
                reason = "Read-only · This session is active in another Tag process."
            }
        }
        let snapshot = try await (owner == nil ? store.load(summary.id) : store.recover(summary.id))
        return StagedSession(snapshot: snapshot, owner: owner, reason: reason)
    }

    /// Saves only the writable session's unsent draft.
    public func saveDraft() async throws {
        guard let active, ownership != nil, !isReadOnly else { return }
        do { try await store.saveDraft(active.id, draft: draft) } catch {
            pauseReason = "Could not save the draft: \(error.localizedDescription)"
            await stopAgent()
            throw error
        }
    }

    /// Stops and awaits the real task before releasing ownership.
    public func close() async throws {
        while isTransitioning { try await Task.sleep(for: .milliseconds(5)) }
        guard !isClosed else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        do {
            try await saveDraft()
            await stopAgent()
            try await saveModelChoice()
        } catch {
            await stopAgent()
            throw error
        }
        finishRun()
    }

    /// A user's explicit storage retry reloads/recoveries history and leaves queued input for review.
    public func retry() async throws {
        guard !isClosed else { throw SessionControlError.paused }
        guard !isBusy else { throw SessionControlError.busy }
        isTransitioning = true
        defer { isTransitioning = false }
        do { try await reloadForContinuation() } catch {
            pauseReason = "Could not reload this session: \(error.localizedDescription)"
            throw error
        }
    }

    func reloadForContinuation() async throws {
        guard !isReadOnly, let active else { throw SessionControlError.paused }
        await stopAgent()
        let loaded = try await store.recover(active.id)
        snapshot = loaded
        self.active = loaded.summary
        pendingForReview = try await store.pending(active.id)
        session.restore(SessionHydration.project(loaded), pending: pendingForReview)
        try await store.markOpened(active.id)
        pauseReason = nil
        startAgent()
    }

    /// Persists input before acknowledging it to the transcript or dispatch queue.
    public func submit(_ text: String) async throws {
        guard !isClosed else { throw SessionControlError.paused }
        guard !isTransitioning else { throw SessionControlError.busy }
        guard !isReadOnly else { throw SessionControlError.readOnly(readOnlyReason ?? "Read-only session.") }
        guard pauseReason == nil else { throw SessionControlError.paused }
        guard selection.current != nil else { throw SessionControlError.chooseModel }
        guard let active, text.contains(where: { !$0.isWhitespace }) else { throw SessionControlError.emptyInput }
        isTransitioning = true
        defer { isTransitioning = false }
        var input = PendingInput(text: text, references: draft.references)
        if let pendingInputID = draft.pendingInputID { input.id = pendingInputID }
        try await store.acceptDraft(active.id, input: input, replacing: draft.pendingInputID != nil)
        pendingForReview.removeAll { $0.id == input.id }
        draft.text = Self.remainingText(draft.text, after: text)
        if draft.references == input.references { draft.references = [] }
        if draft.pendingInputID == input.id { draft.pendingInputID = nil }
        session.submitStored(input)
    }

    /// Acknowledgment consumes the submitted text, preserving edits made while saving.
    static func remainingText(_ current: String, after submitted: String) -> String {
        current.hasPrefix(submitted) ? String(current.dropFirst(submitted.count)) : current
    }

    /// Places the next restored item in the editor; Enter remains an explicit send.
    public func reviewPending() throws {
        guard draft.text.isEmpty, draft.references.isEmpty else {
            throw SessionControlError.readOnly("Clear or send this draft before reviewing a saved input.")
        }
        guard let pending = pendingForReview.first else {
            throw SessionControlError.readOnly("No saved inputs await review.")
        }
        draft = SessionDraft(text: pending.text, references: pending.references, pendingInputID: pending.id)
    }
}
