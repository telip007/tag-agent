public import Foundation
public import ModelKit
public import SessionKit

/// A model-facing result and the exact evidence retained behind it, when needed.
public struct AdmittedOutput: Sendable {
    /// Bounded model-visible content.
    public let content: String
    /// Original artifact; nil when ordinary small output passed through unchanged.
    public let reference: OutputReference?
}

/// Session-bound evidence admission and retrieval, independent of any model provider.
public struct NativeContext: Sendable {
    let store: SQLiteSessionStore
    let sessionID: UUID
    let workingDirectory: URL
    var executor: ContextCommandExecutor?
    let protected: ProtectedPaths
    let fetcher: ContextFetch
    let limits: OutputLimits
    static let messageBudget = 16_384
    static let groupBudget = 32_768
    static let maximumCalls = 64
    static let managedNames = [
        "read_output", "search_output", "index_file", "fetch_and_index", "analyze_output", "batch_execute",
        "read_history", "search_history", "context_stats", "context_doctor",
    ]

    /// Binds every model-facing evidence operation to one owned session.
    public init(
        store: SQLiteSessionStore, sessionID: UUID, workingDirectory: URL, limits: OutputLimits = OutputLimits(),
        protecting protected: ProtectedPaths = .tagConfig, fetchSession: URLSession? = nil
    ) {
        self.store = store
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.limits = limits
        self.protected = protected
        self.fetcher = ContextFetch(session: fetchSession)
    }

    /// Tools whose references remain valid when the same session is reopened.
    public var tools: [ToolDefinition] {
        [ContextRetrieval.readTool(self), ContextRetrieval.searchTool(self)] + ContextIndexing.tools(self)
            + ContextHistory.tools(self) + ContextDiagnostics.tools(self)
            + (executor == nil ? [] : [ContextAnalysis.tool(self), ContextBatch.tool(self)])
    }

    /// Retains large originals before returning a bounded preview; never reruns a tool on save failure.
    public func admit(
        _ text: String, call: ToolCall, failed: Bool, budget: Int = 16_384
    ) async throws -> AdmittedOutput {
        try await admit(ToolOutcome(content: text, failed: failed), call: call, budget: budget)
    }

    /// Admits captured evidence with status even when a small partial result would otherwise fit.
    public func admit(_ outcome: ToolOutcome, call: ToolCall, budget: Int = 16_384) async throws -> AdmittedOutput {
        let text = outcome.content
        guard (256...Self.messageBudget).contains(budget) else { throw OutputError.invalidRange }
        if outcome.complete, !outcome.failed, text.utf8.count <= budget, try ContextText.json(text).utf8.count <= budget
        {
            return AdmittedOutput(content: text, reference: nil)
        }
        let reference = try await store.saveOutput(
            sessionID, text: text, source: ContextText.prefix(call.name, bytes: 256), callID: call.id,
            complete: outcome.complete, limits: limits)
        var sample = budget / 3
        var preview = Preview(
            outputID: reference.id, bytes: reference.byteCount, failed: outcome.failed,
            complete: outcome.complete, exitCode: outcome.exitCode, timedOut: outcome.timedOut)
        while true {
            preview.head = ContextText.prefix(text, bytes: sample)
            preview.tail = ContextText.suffix(text, bytes: sample)
            let content = try ContextText.json(preview)
            if content.utf8.count <= budget { return AdmittedOutput(content: content, reference: reference) }
            guard sample > 0 else { throw OutputError.invalidRange }
            sample /= 2
        }
    }

    func invoke(_ call: ToolCall, budget: Int) async throws -> ToolOutcome {
        switch call.name {
        case "read_output":
            return ToolOutcome(
                content: try await ContextRetrieval.read(self, arguments: call.arguments, budget: budget))
        case "search_output":
            return ToolOutcome(
                content: try await ContextRetrieval.search(self, arguments: call.arguments, budget: budget))
        case "index_file":
            return try await ContextIndexing.file(self, arguments: call.arguments, budget: budget, callID: call.id)
        case "fetch_and_index":
            return try await ContextIndexing.fetch(self, arguments: call.arguments, budget: budget, callID: call.id)
        case "analyze_output":
            return try await ContextAnalysis.run(self, arguments: call.arguments, budget: budget, callID: call.id)
        case "batch_execute":
            return try await ContextBatch.run(self, arguments: call.arguments, budget: budget, callID: call.id)
        case "read_history":
            return ToolOutcome(content: try await ContextHistory.read(self, arguments: call.arguments, budget: budget))
        case "search_history":
            return ToolOutcome(
                content: try await ContextHistory.search(self, arguments: call.arguments, budget: budget))
        case "context_stats", "context_doctor":
            return ToolOutcome(content: try await ContextDiagnostics.run(self, name: call.name, budget: budget))
        default: throw ToolError("unknown native context tool")
        }
    }

    private struct Preview: Encodable {
        let outputID: String
        let bytes: Int
        let failed: Bool
        let complete: Bool
        let exitCode: Int32?
        let timedOut: Bool
        let readTool = "read_output"
        let coverage = "preview_only"
        var head = ""
        var tail = ""

        enum CodingKeys: String, CodingKey {
            case outputID = "output_id"
            case readTool = "read_tool"
            case exitCode = "exit_code"
            case timedOut = "timed_out"
            case bytes, failed, complete, coverage, head, tail
        }
    }
}
