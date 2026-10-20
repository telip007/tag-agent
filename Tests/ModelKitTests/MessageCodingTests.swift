import Foundation
import OpenRouter
import Testing

@testable import ModelKit

struct MessageCodingTests {
    @Test(arguments: WireFormat.allCases)
    func everyRolePreservesOpaqueReplayAndEmptyFields(format: WireFormat) throws {
        let messages: [Message] = [
            .system("trusted"), .user("Unicode: 猫\n"),
            .assistant(
                AssistantMessage(
                    text: "", reasoning: nil,
                    replay: [
                        ReplayItem(
                            format: format, payload: ["signature": "opaque", "nested": [1, true, nil]])
                    ], toolCalls: [ToolCall(id: "call", name: "read_file", arguments: "{\"path\":\"a\"}")])),
            .tool(callID: "call", name: "read_file", content: ""),
        ]
        let encoded = try JSONEncoder().encode(messages)
        let decoded = try JSONDecoder().decode([Message].self, from: encoded)
        #expect(decoded == messages)
        let objects = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        #expect(objects[2]["role"] as? String == "assistant")
    }

    @Test func unknownRoleIsRejected() {
        let encoded = Data("{\"role\":\"future\",\"text\":\"do not silently discard\"}".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Message.self, from: encoded) }
    }

    @Test func usagePreservesUnknownAndReportedZero() throws {
        let usages = [
            Usage(inputTokens: 4, outputTokens: 3),
            Usage(inputTokens: 4, outputTokens: 3, cost: 0, cachedInputTokens: 0, cacheWriteInputTokens: 2),
        ]
        #expect(try JSONDecoder().decode([Usage].self, from: JSONEncoder().encode(usages)) == usages)
    }
}
