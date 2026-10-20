import Foundation

/// One block of the conversation, as the workspace shows it. Blocks can still
/// change while the agent works (a tool tray grows) and can be expanded.
public struct TranscriptBlock: Identifiable, Sendable, Equatable {
    /// What the block shows.
    public enum Content: Sendable, Equatable {
        /// A message the user sent.
        case user(String)
        /// What the model reasoned before writing.
        case reasoning(Reasoning)
        /// Text the model wrote.
        case reply(String)
        /// The tool calls between two replies, in order.
        case tools([ToolRun])
        /// A change `edit_file` made.
        case edit(FileEdit)
        /// A model call that failed, and what the user can do about it.
        case failure(message: String, recovery: String?)
    }

    /// The block's position in the transcript.
    public let id: Int
    /// What the block shows.
    public var content: Content
}

/// The model's reasoning before a reply or tool calls.
public struct Reasoning: Sendable, Equatable {
    /// The reasoning text, as the model wrote it.
    public var text: String
    /// How long the model reasoned, once it stopped; `nil` while it still does.
    public var duration: Duration?
}

/// One tool call in a tray.
public struct ToolRun: Sendable, Equatable {
    /// Where the call is.
    public enum State: Sendable, Equatable {
        case running
        case succeeded
        case failed
    }

    /// The tool's name.
    public var name: String
    /// The gist of its arguments (see ``ToolSummary``).
    public var summary: String
    /// Where the call is.
    public var state: State
    /// How long it took, once finished.
    public var duration: Duration?
    /// What the tool returned, once finished.
    public var output: String
}

/// A file change, read from an `edit_file` call: the replaced text against the
/// new text, trimmed to the lines that differ.
public struct FileEdit: Sendable, Equatable {
    /// A line of the change.
    public enum Line: Sendable, Equatable {
        case removed(String)
        case added(String)
    }

    /// The file's path as the model gave it.
    public var path: String
    /// The changed lines: removals first, then additions.
    public var lines: [Line]

    /// How many lines were added.
    public var added: Int {
        lines.filter { if case .added = $0 { true } else { false } }.count
    }

    /// How many lines were removed.
    public var removed: Int {
        lines.count - added
    }

    /// Reads an `edit_file` call's JSON arguments, or `nil` when they aren't
    /// an edit.
    static func from(arguments: String) -> Self? {
        let object = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any]
        guard let object, let path = object["path"] as? String, let new = object["new_str"] as? String else {
            return nil
        }
        let old = object["old_str"] as? String ?? ""
        return Self(path: path, lines: diff(old: old, new: new))
    }

    /// The lines of `old` and `new` without the lines they share at the start
    /// and at the end, so a one-line change in a long snippet shows as one line.
    static func diff(old: String, new: String) -> [Line] {
        var before = old.isEmpty ? [] : old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var after = new.isEmpty ? [] : new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let first = before.first, first == after.first {
            before.removeFirst()
            after.removeFirst()
        }
        while let last = before.last, last == after.last {
            before.removeLast()
            after.removeLast()
        }
        return before.map(Line.removed) + after.map(Line.added)
    }
}

/// Lines added and removed in one file over the session.
public struct FileChange: Sendable, Equatable {
    /// The file's path as the model gave it.
    public var path: String
    /// Lines added across all edits.
    public var added: Int
    /// Lines removed across all edits.
    public var removed: Int
}
