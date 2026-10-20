public import Foundation
public import ModelKit

/// Indexed metadata, updated atomically with the authoritative event log.
public struct SessionSummary: Sendable, Equatable, Codable, Identifiable {
    /// Immutable local conversation identity.
    public var id: UUID
    /// Canonical execution directory; worktrees remain distinct.
    public var workspace: String
    /// User title or a bounded first-message title.
    public var title: String
    /// Latest readable text, bounded for discovery without history loading.
    public var preview: String?
    /// Creation time.
    public var createdAt: Date
    /// Last durable activity.
    public var updatedAt: Date
    /// Last explicit opening, used for recent-session ordering.
    public var lastOpenedAt: Date
    /// Current trusted context revision.
    public var context: SessionContext
    /// Stable provider routing/cache identifier, preserved across restarts.
    public var providerSessionID: String
    /// Next sequence, allocated inside the append transaction.
    public var nextSequence: Int64
    /// Number of recorded prompt/model revisions.
    public var contextRevision: Int64
    /// Accumulated provider-reported cost, without estimates.
    public var cost: Double
    /// Latest reported full context size.
    public var contextTokens: Int
    /// Usage of the last completed reply; nil is unknown.
    public var latestUsage: Usage?
    /// Explicit request projection; the canonical journal remains authoritative.
    public var contextProjection: SessionContextProjection?
    /// Date annotation state of the last consumed input.
    public var lastDate: String?
    /// Whether a first user input has already supplied the automatic title.
    public var hasUserInput: Bool

    init(workspace: String, context: SessionContext, now: Date) {
        id = UUID()
        self.workspace = workspace
        title = "New session"
        createdAt = now
        updatedAt = now
        lastOpenedAt = now
        self.context = context
        providerSessionID = id.uuidString
        nextSequence = 0
        contextRevision = 0
        cost = 0
        contextTokens = 0
        hasUserInput = false
    }
}

/// An ordered, committed semantic event.
public struct SessionEntry: Sendable, Equatable {
    /// Session owning the record.
    public var sessionID: UUID
    /// Monotonic per-session position, starting at zero.
    public var sequence: Int64
    /// Durable wall-clock timestamp.
    public var timestamp: Date
    /// Version-checked decoded payload.
    public var event: SessionEvent
}

/// Accepted input which has not yet entered model history.
public struct PendingInput: Sendable, Equatable, Codable, Identifiable {
    /// Identity used for atomic, exactly-once promotion into the event log.
    public var id: UUID
    /// Original user text.
    public var text: String
    /// Explicitly selected reference attachments.
    public var references: [SessionReference]

    /// Creates a pending user message.
    public init(text: String, references: [SessionReference]) {
        id = UUID()
        self.text = text
        self.references = references
    }
}

/// Unsent UI state saved only at explicit clean boundaries.
public struct SessionDraft: Sendable, Equatable, Codable {
    /// Text still being edited.
    public var text: String
    /// A preview awaiting attachment to the next accepted input.
    public var references: [SessionReference]
    /// Accepted input being explicitly reviewed, preserving its identity after edits.
    public var pendingInputID: UUID?

    /// Creates an unsent draft.
    public init(text: String = "", references: [SessionReference] = [], pendingInputID: UUID? = nil) {
        self.text = text
        self.references = references
        self.pendingInputID = pendingInputID
    }
}
