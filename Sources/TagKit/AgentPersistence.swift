import Foundation
import ModelKit
import SessionKit

extension Agent {
    /// Historical content stays byte-for-byte; only the current trusted prefix changes.
    func synchronize(_ active: ActiveModel, state: inout ConversationState, saved: inout SessionContext?) async throws {
        state.follow(active)
        guard journal != nil else { return }
        guard case .system(let prompt) = state.conversation.first else { throw SessionError.invalidEvent }
        let context = SessionContext(prompt: prompt, model: active.entry.ref, effort: active.effort)
        if context != saved {
            try await journal?.append(.context(context))
            state.clearLatestUsage()
            saved = context
        }
    }

    /// Returns false for a legacy in-memory reset; durable clears are handled by the controller.
    func take(_ input: AgentInput, state: inout ConversationState) async throws -> Bool {
        switch input {
        case .clear:
            guard journal == nil else { throw SessionError.invalidEvent }
            state.reset()
            return false
        case .message(let text):
            if let journal {
                let input = PendingInput(text: text, references: [])
                try await journal.accept(input)
                try await consume(input, state: &state)
            } else {
                state.conversation.append(.user(state.dater.message(text, at: now())))
            }
        case .stored(let input):
            guard journal != nil else { throw SessionError.invalidEvent }
            try await consume(input, state: &state)
        }
        return true
    }

    private func consume(_ input: PendingInput, state: inout ConversationState) async throws {
        let attachment = SessionReferences.render(input.references)
        guard input.references.count <= SessionReferences.countLimit,
            attachment.utf8.count <= SessionReferences.byteLimit
        else { throw SessionError.invalidEvent }
        let text = input.text + (attachment.isEmpty ? "" : "\n\n" + attachment)
        var dater = state.dater
        let message = dater.message(text, at: now())
        guard let date = dater.lastDate else { throw SessionError.invalidEvent }
        try await journal?.consume(
            input,
            user: SessionUser(
                raw: input.text, message: message, date: date, references: input.references))
        state.dater = dater
        state.conversation.append(.user(message))
    }
}
