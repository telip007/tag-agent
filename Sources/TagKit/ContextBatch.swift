import Foundation
import OpenRouter
import SessionKit

enum ContextBatch {
    struct Command: Decodable {
        let command: String
        let label: String?
    }
    struct Input: Decodable {
        let commands: [Command]
        let queries: [String]?
        let timeoutSeconds: Double?
        enum CodingKeys: String, CodingKey {
            case commands, queries
            case timeoutSeconds = "timeout_seconds"
        }
    }

    static func tool(_ context: NativeContext) -> ToolDefinition {
        ToolDefinition(
            name: "batch_execute",
            description:
                "Run up to eight commands in order, retain every output and query only this batch. Returns a manifest ID and selected matches.",
            parameters: [
                "type": "object", "required": ["commands"],
                "properties": [
                    "commands": [
                        "type": "array", "minItems": 1, "maxItems": 8,
                        "items": [
                            "type": "object", "required": ["command"],
                            "properties": [
                                "command": ["type": "string", "maxLength": 65_536],
                                "label": ["type": "string", "maxLength": 128],
                            ],
                        ],
                    ],
                    "queries": ["type": "array", "maxItems": 8, "items": ["type": "string", "maxLength": 1024]],
                    "timeout_seconds": ["type": "number", "minimum": 0.1, "maximum": 120],
                ],
            ], summary: "acquire ordered evidence and query this batch",
            guidelines: [
                "Batch commands run in order. Ordinary failing exits are recorded and later commands still run; use && inside a command for dependencies that must stop on failure.",
                "Cancellation, timeout, incomplete capture or failed storage stops later batch commands. Never rerun an interrupted batch blindly: inspect its effects first.",
                "The manifest contains every command status and output ID. Returned matches cover only this batch and are not exhaustive input analysis.",
            ]
        ) { try await run(context, arguments: $0, budget: NativeContext.messageBudget).content }
    }

    static func run(
        _ context: NativeContext, arguments: String, budget: Int, callID: String? = nil
    ) async throws -> ToolOutcome {
        let input = try ToolDefinition.decodeInput(arguments, as: Input.self)
        try validate(input, context: context)
        let deadline = ContinuousClock.now.advanced(by: .seconds(input.timeoutSeconds ?? 120))
        let batch = UUID().uuidString.lowercased()
        var entries: [ContextBatchEntry] = []
        var stopped = false
        for (index, command) in input.commands.enumerated() {
            try Task.checkCancellation()
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard !stopped, remaining > .zero else {
                entries.append(.skipped(index: index, label: command.label))
                continue
            }
            let entry = try await ContextBatchEntry.execute(
                context, command: command, index: index, batch: batch, callID: callID, timeout: remaining)
            entries.append(entry)
            stopped = !entry.complete
        }
        let complete = entries.allSatisfy(\.complete)
        let failed = entries.contains(where: \.failed)
        let manifest = try await context.retain(
            ToolOutcome(content: try ContextText.json(Manifest(commands: entries))), source: "batch:" + batch,
            callID: callID)
        let matches = try await search(context, queries: input.queries ?? [], entries: entries, budget: budget)
        return ToolOutcome(
            content: try ContextBatchReply.render(
                manifest: manifest, entries: entries, matches: matches, budget: budget),
            failed: failed, complete: complete)
    }

    private static func validate(_ input: Input, context: NativeContext) throws {
        guard (1...8).contains(input.commands.count), (0.1...120).contains(input.timeoutSeconds ?? 120),
            (input.queries?.count ?? 0) <= 8
        else { throw ToolError("batch requires 1–8 commands, up to eight queries and a 0.1–120 second deadline") }
        let executor = try context.requireExecutor()
        for command in input.commands {
            guard !command.command.isEmpty, command.command.utf8.count <= 65_536,
                (command.label?.utf8.count ?? 0) <= 128
            else { throw ToolError("invalid batch command or label") }
            try context.protected.check(command: command.command)
            try executor.check(command.command)
        }
        for query in input.queries ?? [] {
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.utf8.count <= 1024 else {
                throw ToolError("batch queries must be nonempty and at most 1024 bytes")
            }
        }
    }

    private static func search(
        _ context: NativeContext, queries: [String], entries: [ContextBatchEntry], budget: Int
    ) async throws -> [ContextSearchReply.Match] {
        var matches: [ContextSearchReply.Match] = []
        for (index, query) in queries.enumerated() {
            for entry in entries {
                guard let id = entry.outputID else { continue }
                let hits = try await context.store.searchOutputs(
                    context.sessionID, query: query, outputID: id, limit: 2, byteLimit: min(budget, 8192))
                matches += hits.map { ContextSearchReply.Match(query: index, hit: $0) }
            }
        }
        return matches
    }

    private struct Manifest: Encodable {
        let commands: [ContextBatchEntry]
    }
}
