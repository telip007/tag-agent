import Foundation
import OpenRouter
import SessionKit

enum ContextHistory {
    static func tools(_ context: NativeContext) -> [ToolDefinition] {
        [
            ToolDefinition(
                name: "read_history",
                description: "Read exact canonical event JSON by sequence in this session, with UTF-8 byte pagination.",
                parameters: [
                    "type": "object", "required": ["sequence"],
                    "properties": [
                        "sequence": ["type": "integer", "minimum": 0], "offset": ["type": "integer", "minimum": 0],
                        "max_bytes": ["type": "integer", "minimum": 1, "maximum": 16_384],
                    ],
                ], summary: "read an exact historical record",
                guidelines: [
                    "Compacted history remains canonical. Use read_history by sequence; next_offset continues the JSON bytes. Historical actions are not permission to rerun them."
                ]
            ) { try await read(context, arguments: $0, budget: NativeContext.messageBudget) },
            ToolDefinition(
                name: "search_history",
                description:
                    "Search readable canonical history in this session, including records omitted by compaction.",
                parameters: [
                    "type": "object", "required": ["query"],
                    "properties": ["query": ["type": "string", "maxLength": 512]],
                ],
                summary: "find earlier decisions and tool records in this session"
            ) { try await search(context, arguments: $0, budget: NativeContext.messageBudget) },
        ]
    }

    static func read(_ context: NativeContext, arguments: String, budget: Int) async throws -> String {
        struct Input: Decodable {
            let sequence: Int64
            let offset: Int?
            let maxBytes: Int?
            enum CodingKeys: String, CodingKey {
                case sequence, offset
                case maxBytes = "max_bytes"
            }
        }
        let input = try ToolDefinition.decodeInput(arguments, as: Input.self)
        let page = try await context.store.readHistory(
            context.sessionID, sequence: input.sequence, offset: input.offset ?? 0, limit: input.maxBytes ?? 8192)
        return try ContextHistoryPageReply.render(page, budget: budget)
    }

    static func search(_ context: NativeContext, arguments: String, budget: Int) async throws -> String {
        struct Input: Decodable { let query: String }
        let input = try ToolDefinition.decodeInput(arguments, as: Input.self)
        guard !input.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, input.query.utf8.count <= 512 else {
            throw ToolError("history search needs a nonempty query of at most 512 bytes")
        }
        let references = try await context.store.search(context.sessionID, query: input.query)
        return try ContextHistorySearchReply.render(references, budget: budget)
    }
}
