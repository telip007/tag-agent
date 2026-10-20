import OpenRouter
import SessionKit

/// Diagnostics never archive their own result or reinterpret disk bytes as token savings.
enum ContextDiagnostics {
    static func tools(_ context: NativeContext) -> [ToolDefinition] {
        ["context_stats", "context_doctor"].map { name in
            ToolDefinition(
                name: name,
                description: name == "context_stats"
                    ? "Read measured retained/admitted bytes and the last provider usage report in this session."
                    : "Check canonical history, evidence hashes, retrieval indexes and linked SQLite without changing data.",
                parameters: ["type": "object", "properties": [:]],
                summary: name == "context_stats" ? "inspect local context volumes" : "diagnose context integrity",
                guidelines: [
                    "Stored bytes, presented result bytes and provider tokens are different measurements. Diagnostics never imply billed savings."
                ]
            ) { _ in try await run(context, name: name, budget: NativeContext.messageBudget) }
        }
    }

    static func run(_ context: NativeContext, name: String, budget: Int) async throws -> String {
        let output: String
        if name == "context_stats" {
            output = try ContextText.json(try await context.store.contextStatistics(context.sessionID))
        } else {
            output = try ContextText.json(try await context.store.contextDoctor(context.sessionID))
        }
        guard output.utf8.count <= budget else { throw OutputError.invalidRange }
        return output
    }
}
