public import Foundation

/// Persistence boundaries used by the agent, independent of the SQL backend.
public protocol SessionStore: Sendable {
    /// Reads metadata and history from one consistent transaction.
    func load(_ id: UUID) async throws -> SessionSnapshot
    /// Durably accepts a pending input before acknowledging it.
    func accept(_ id: UUID, input: PendingInput) async throws
    /// Atomically promotes exactly that input into model history.
    func consume(_ id: UUID, inputID: UUID, user: SessionUser) async throws
    /// Commits one semantic boundary before another external action.
    func append(_ id: UUID, event: SessionEvent) async throws
}

/// A consistent read of one session's indexed state and authoritative events.
public struct SessionSnapshot: Sendable {
    /// Metadata from the same database snapshot as the entries.
    public var summary: SessionSummary
    /// Complete ordered history, with disk versions already checked.
    public var entries: [SessionEntry]
}
