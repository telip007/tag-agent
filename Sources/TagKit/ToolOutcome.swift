/// Original tool evidence and execution status, before presentation limits.
public struct ToolOutcome: Sendable {
    /// Exact UTF-8 output, including whitespace and NUL bytes.
    public var content: String
    /// Whether execution failed or evidence is incomplete.
    public var failed: Bool
    /// Whether all emitted output was captured.
    public var complete: Bool
    /// Shell-style exit code, including 128 + signal when signalled.
    public var exitCode: Int32?
    /// Whether the host stopped execution at its time limit.
    public var timedOut: Bool

    /// Creates an outcome for custom tools or bounded process capture.
    public init(
        content: String, failed: Bool = false, complete: Bool = true, exitCode: Int32? = nil, timedOut: Bool = false
    ) {
        self.content = content
        self.failed = failed
        self.complete = complete
        self.exitCode = exitCode
        self.timedOut = timedOut
    }
}
