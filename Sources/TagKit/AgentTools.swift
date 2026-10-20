import Foundation
import ModelKit
import SessionKit

extension Agent {
    /// Runs a tool call. Failures become the tool's result, so the model can
    /// see what went wrong and try again.
    func execute(_ call: ToolCall, budget: Int) async throws -> String {
        try Task.checkCancellation()
        try await journal?.append(.toolStarted(call))
        try Task.checkCancellation()
        output(.toolStarted(name: call.name, arguments: call.arguments))
        let start = ContinuousClock.now
        var result = try await result(of: call, budget: budget)
        if let context, !NativeContext.managedNames.contains(call.name) {
            result.content = try await context.admit(result, call: call, budget: budget)
                .content
        }
        let milliseconds = Int64((ContinuousClock.now - start) / .milliseconds(1))
        try await journal?.append(
            .toolFinished(
                SessionToolResult(
                    call: call, output: result.content, failed: result.failed, durationMilliseconds: milliseconds)))
        output(.toolFinished(name: call.name, arguments: call.arguments, output: result.content, failed: result.failed))
        return result.content
    }

    private func result(of call: ToolCall, budget: Int) async throws -> ToolOutcome {
        guard let tool = tools.first(where: { $0.name == call.name }) else {
            return ToolOutcome(content: "error: tool not found", failed: true)
        }
        do {
            if let context, NativeContext.managedNames.contains(call.name) {
                return try await context.invoke(call, budget: budget)
            }
            if context != nil, let capture = tool.captureFunction { return try await capture(call.arguments) }
            return ToolOutcome(content: try await tool.function(call.arguments))
        } catch {
            if Task.isCancelled || error is CancellationError || error is ContextStorageFailure { throw error }
            var content = "error: " + error.localizedDescription
            if context != nil, NativeContext.managedNames.contains(call.name) {
                while try ContextText.json(content).utf8.count > budget {
                    content = ContextText.prefix(content, bytes: content.utf8.count / 2)
                }
            }
            return ToolOutcome(content: content, failed: true)
        }
    }
}
