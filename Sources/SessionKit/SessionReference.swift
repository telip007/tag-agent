public import Foundation

/// Immutable coordinates into a source conversation.
public struct SessionCitation: Sendable, Equatable, Codable {
    /// Source session UUID.
    public var sessionID: UUID
    /// Source title at attachment time.
    public var title: String
    /// Source entry sequence.
    public var sequence: Int64
    /// Readable source role.
    public var role: String
    /// Source entry's wall-clock time.
    public var timestamp: Date

    /// Creates a stable source label.
    public init(sessionID: UUID, title: String, sequence: Int64, role: String, timestamp: Date) {
        self.sessionID = sessionID
        self.title = title
        self.sequence = sequence
        self.role = role
        self.timestamp = timestamp
    }
}

/// A copied excerpt; later source edits cannot rewrite destination history.
public struct SessionReference: Sendable, Equatable, Codable {
    /// Immutable source coordinates.
    public var source: SessionCitation
    /// Exact readable excerpt selected by the user.
    public var text: String

    /// Creates an excerpt.
    public init(source: SessionCitation, text: String) {
        self.source = source
        self.text = text
    }
}
