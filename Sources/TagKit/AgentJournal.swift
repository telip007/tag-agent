public import SessionKit

/// Durable boundaries for an agent resuming a recovered, owned session.
@MainActor
public struct AgentJournal {
    /// Consistent recovered history to restore before waiting for user input.
    public let snapshot: SessionSnapshot
    let store: any SessionStore

    /// Connects the loop to its storage backend and recovered snapshot.
    public init(store: any SessionStore, snapshot: SessionSnapshot) {
        self.store = store
        self.snapshot = snapshot
    }

    func append(_ event: SessionEvent) async throws {
        try await store.append(snapshot.summary.id, event: event)
    }

    func accept(_ input: PendingInput) async throws {
        try await store.accept(snapshot.summary.id, input: input)
    }

    func consume(_ input: PendingInput, user: SessionUser) async throws {
        try await store.consume(snapshot.summary.id, inputID: input.id, user: user)
    }
}
