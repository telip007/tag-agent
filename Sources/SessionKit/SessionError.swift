public import Foundation

/// Recoverable local session failures; none means an empty successful session.
public enum SessionError: Error, Sendable, Equatable, LocalizedError {
    /// A disk format this binary does not understand.
    case unsupportedVersion(Int)
    /// No session matches the supplied ID.
    case notFound
    /// More than one session matches the supplied prefix.
    case ambiguousID
    /// The pending input was already consumed or does not exist.
    case missingInput
    /// Another process owns this conversation.
    case sessionInUse
    /// Changing the store's existing journal mode requires an explicit migration.
    case unsupportedJournal(String)
    /// A required entry payload is missing or inconsistent.
    case invalidEvent
    /// Storage and lock paths must be ordinary local files/directories.
    case unsafeStoragePath

    /// What the user can do about the local failure.
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Session format \(version) needs a newer Tag. The saved data was preserved."
        case .notFound: "No saved session matches that ID."
        case .ambiguousID: "That session ID prefix is ambiguous. Use more characters."
        case .missingInput: "That pending message was already consumed or does not exist."
        case .sessionInUse: "This session is open in another Tag process. Close it there before continuing."
        case .unsupportedJournal(let mode):
            "The session store uses \(mode) journaling; an explicit migration is required."
        case .invalidEvent: "The session contains an invalid event. The saved data was preserved."
        case .unsafeStoragePath:
            "Session storage refuses symbolic links and special files. Choose an ordinary local directory."
        }
    }
}
