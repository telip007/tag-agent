import Foundation

/// Capability supplied by the installed native bash tool, retaining its own path policy.
struct ContextCommandExecutor: Sendable {
    let directory: URL
    let protected: ProtectedPaths
    var makeSpool: @Sendable () throws -> CaptureSpool = { try CaptureSpool() }

    func check(_ command: String) throws { try protected.check(command: command) }

    func run(
        _ command: String, input: Data = Data(), byteLimit: Int, timeout: Duration = .seconds(120)
    ) async throws -> ToolOutcome {
        try check(command)
        return try await ProcessCapture.run(
            "bash", ["-c", command], in: directory, input: input, byteLimit: byteLimit, timeout: timeout,
            makeSpool: makeSpool)
    }
}

extension NativeContext {
    /// Custom or omitted shell tools do not silently acquire a different native executor.
    func withExecution(_ tools: [ToolDefinition]) -> Self {
        var context = self
        context.executor = tools.first { $0.name == "bash" }?.contextExecutor
        return context
    }

    func requireExecutor() throws -> ContextCommandExecutor {
        guard let executor else {
            throw ToolError("native artifact execution is unavailable without the native bash capability")
        }
        return executor
    }
}

extension ToolDefinition {
    func withContextExecutor(_ executor: ContextCommandExecutor) -> Self {
        var tool = self
        tool.contextExecutor = executor
        return tool
    }
}
