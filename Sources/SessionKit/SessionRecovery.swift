import ModelKit

/// Tracks protocol completeness, independently of UI state or external effects.
private struct RecoveryState {
    var pending: [ToolCall] = []
    var started: Set<String> = []
    var requestPending = false
    var turnPending = false

    mutating func apply(_ event: SessionEvent) throws {
        switch event {
        case .context: break
        case .contextProjection:
            guard pending.isEmpty, !requestPending, !turnPending else { throw SessionError.invalidEvent }
        case .user:
            guard pending.isEmpty else { throw SessionError.invalidEvent }
            turnPending = true
        case .inferenceStarted:
            guard pending.isEmpty else { throw SessionError.invalidEvent }
            requestPending = true
        case .assistant(let reply):
            guard pending.isEmpty else { throw SessionError.invalidEvent }
            let calls = reply.message.toolCalls
            guard Set(calls.map(\.id)).count == calls.count else { throw SessionError.invalidEvent }
            pending = calls
            started = []
            requestPending = false
            turnPending = !calls.isEmpty
        case .toolStarted(let call):
            guard pending.contains(call), !started.contains(call.id) else { throw SessionError.invalidEvent }
            started.insert(call.id)
        case .toolFinished(let result):
            guard let index = pending.firstIndex(of: result.call) else { throw SessionError.invalidEvent }
            pending.remove(at: index)
            started.remove(result.call.id)
        case .failure:
            requestPending = false
            turnPending = false
        }
    }
}

enum SessionRecovery {
    static func events(for entries: [SessionEntry]) throws -> [SessionEvent] {
        var state = RecoveryState()
        for entry in entries { try state.apply(entry.event) }
        guard state.requestPending || state.turnPending || !state.pending.isEmpty else { return [] }
        var events = state.pending.map { call -> SessionEvent in
            let output =
                state.started.contains(call.id)
                ? "error: interrupted; this tool's side effects are unknown. Inspect the workspace before acting."
                : "error: not executed; the session was interrupted before this tool started. Do not rerun automatically."
            return .toolFinished(SessionToolResult(call: call, output: output, failed: true, durationMilliseconds: nil))
        }
        events.append(
            .failure(
                SessionFailure(
                    message: "The previous turn was interrupted. Saved messages were restored.",
                    recovery: "No pending tool was rerun. Review the workspace and send a message when ready.")))
        return events
    }
}
