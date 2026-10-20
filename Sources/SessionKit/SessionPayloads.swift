public import ModelKit

/// Trusted execution context, recorded when it changes.
public struct SessionContext: Sendable, Equatable, Codable {
    /// Rendered system prompt for this revision.
    public var prompt: String
    /// Provider and model identifier.
    public var model: ModelRef
    /// Reasoning effort, when selected.
    public var effort: String?

    /// Creates a context revision.
    public init(prompt: String, model: ModelRef, effort: String?) {
        self.prompt = prompt
        self.model = model
        self.effort = effort
    }
}

/// A user's accepted input, retaining both display and provider representations.
public struct SessionUser: Sendable, Equatable, Codable {
    /// Original input for display and command history.
    public var raw: String
    /// Exact text sent to the provider, including date and attached excerpts.
    public var message: String
    /// Last date annotation state after this input.
    public var date: String
    /// Immutable excerpts explicitly attached by the user.
    public var references: [SessionReference]

    /// Creates an accepted input.
    public init(raw: String, message: String, date: String, references: [SessionReference]) {
        self.raw = raw
        self.message = message
        self.date = date
        self.references = references
    }
}

/// A provider reply saved before tools may run.
public struct SessionAssistant: Sendable, Equatable, Codable {
    /// Complete text, reasoning, opaque replay and tool calls.
    public var message: AssistantMessage
    /// Reported metrics; nil remains unknown.
    public var usage: Usage?

    /// Creates a completed reply.
    public init(message: AssistantMessage, usage: Usage?) {
        self.message = message
        self.usage = usage
    }
}

/// A tool result saved before another external action.
public struct SessionToolResult: Sendable, Equatable, Codable {
    /// Original call, retaining raw arguments for display and edits.
    public var call: ToolCall
    /// Exact output seen by the model.
    public var output: String
    /// Whether execution failed or was interrupted.
    public var failed: Bool
    /// Measured elapsed time, independent of process-local clocks.
    public var durationMilliseconds: Int64?

    /// Creates a completed or explicitly interrupted tool result.
    public init(call: ToolCall, output: String, failed: Bool, durationMilliseconds: Int64?) {
        self.call = call
        self.output = output
        self.failed = failed
        self.durationMilliseconds = durationMilliseconds
    }
}

/// A visible diagnostic saved with the session.
public struct SessionFailure: Sendable, Equatable, Codable {
    /// User-facing diagnostic.
    public var message: String
    /// Suggested next step, when known.
    public var recovery: String?

    /// Creates a diagnostic.
    public init(message: String, recovery: String?) {
        self.message = message
        self.recovery = recovery
    }
}
