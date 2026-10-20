import Foundation
import ModelKit
import SessionKit

struct ProbeStore: SessionStore {
    let base: SQLiteSessionStore
    let boundary: ProbeBoundary

    func load(_ id: UUID) async throws -> SessionSnapshot { try await base.load(id) }
    func accept(_ id: UUID, input: PendingInput) async throws {
        try await boundary.pauseIf("before-accept")
        try await base.accept(id, input: input)
        try await boundary.pauseIf("accept")
    }
    func consume(_ id: UUID, inputID: UUID, user: SessionUser) async throws {
        try await base.consume(id, inputID: inputID, user: user)
        try await boundary.pauseIf("input")
    }
    func append(_ id: UUID, event: SessionEvent) async throws {
        try await base.append(id, event: event)
        switch event {
        case .inferenceStarted: try await boundary.pauseIf("request")
        case .assistant(let reply): try await boundary.pauseIf(reply.message.toolCalls.isEmpty ? "final" : "reply")
        case .toolStarted(let call): try await boundary.pauseIf(call.id == "first" ? "start" : "second")
        case .toolFinished(let result) where result.call.id == "first": try await boundary.pauseIf("result")
        default: break
        }
    }
}
