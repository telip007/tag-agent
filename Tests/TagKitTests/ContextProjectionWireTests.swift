import Foundation
import OpenRouter
import SessionKit
import Testing

@testable import ModelKit
@testable import TagKit

@MainActor
struct ContextProjectionWireTests {
    @Test func retainedMultiCallGroupsSerializeWithTheirOriginalProviderReplay() async throws {
        let fixture = PersistentAgentFixture()
        let (store, session) = try await fixture.prepare()
        try await appendGroup(
            store, id: session.id, prefix: "old", output: String(repeating: "older evidence\n", count: 200))
        try await appendGroup(store, id: session.id, prefix: "recent", output: "recent evidence")
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "done"), usage: nil)))
        _ = try await store.compactContext(session.id, keepRecentGroups: 2)
        let state = ConversationState(
            active: fixture.model.active, prompt: { $0.name }, snapshot: try await store.load(session.id))
        let view = state.requestConversation
        let messages = AnthropicChatModel.messages(view)
        let blocks = messages.flatMap { $0["content"]?.arrayValue ?? [] }
        #expect(
            blocks.first { $0["type"]?.stringValue == "thinking" } == [
                "type": "thinking", "thinking": "reasoning", "signature": "sig-recent",
            ])
        #expect(
            blocks.compactMap { $0["type"]?.stringValue == "tool_use" ? $0["id"]?.stringValue : nil } == [
                "recent-a", "recent-b",
            ])
        #expect(
            blocks.compactMap { $0["type"]?.stringValue == "tool_result" ? $0["tool_use_id"]?.stringValue : nil } == [
                "recent-a", "recent-b",
            ])
        #expect(
            try ContextText.json(messages).utf8.count
                < ContextText.json(AnthropicChatModel.messages(state.conversation)).utf8.count)
        try assertResponses(view)
        let parts = GeminiChatModel.contents(view).flatMap { $0["parts"]?.arrayValue ?? [] }
        #expect(parts.first { $0["thoughtSignature"] != nil }?["thoughtSignature"] == "gemini-recent")
        #expect(parts.filter { $0["functionCall"] != nil }.count == 2)
        #expect(parts.filter { $0["functionResponse"] != nil }.count == 2)
        #expect(!ContextText.prefix(try ContextText.json(messages), bytes: 100_000).contains("sig-old"))
    }

    private func assertResponses(_ view: [Message]) throws {
        let body = ResponsesChatModel.body(
            for: view, tools: [], options: ReplyOptions(reasoningEffort: nil, sessionID: "projection"),
            model: "test", includeEncryptedReasoning: true)
        let input = try #require(body["input"]?.arrayValue)
        #expect(
            input.first { $0["type"]?.stringValue == "reasoning" } == [
                "type": "reasoning", "id": "rs-recent", "encrypted_content": "opaque-recent", "summary": [],
            ])
        #expect(
            input.compactMap { $0["type"]?.stringValue == "function_call" ? $0["call_id"]?.stringValue : nil } == [
                "recent-a", "recent-b",
            ])
        #expect(
            input.compactMap { $0["type"]?.stringValue == "function_call_output" ? $0["call_id"]?.stringValue : nil }
                == ["recent-a", "recent-b"])
    }

    private func appendGroup(_ store: SQLiteSessionStore, id: UUID, prefix: String, output: String) async throws {
        let first = ToolCall(id: prefix + "-a", name: "bash", arguments: #"{"step":1}"#)
        let second = ToolCall(id: prefix + "-b", name: "bash", arguments: #"{"step":2}"#)
        let signature = JSONValue.string("sig-" + prefix)
        let blocks: JSONValue = [
            ["type": "thinking", "thinking": "reasoning", "signature": signature],
            ["type": "tool_use", "id": .string(first.id), "name": "bash", "input": ["step": 1]],
            ["type": "tool_use", "id": .string(second.id), "name": "bash", "input": ["step": 2]],
        ]
        let gemini: JSONValue = [
            ["functionCall": ["name": "bash", "args": ["step": 1]], "thoughtSignature": .string("gemini-" + prefix)],
            ["functionCall": ["name": "bash", "args": ["step": 2]]],
        ]
        let reply = AssistantMessage(
            replay: [
                ReplayItem(format: .anthropicMessages, payload: blocks),
                ReplayItem(
                    format: .responses,
                    payload: [
                        "type": "reasoning", "id": .string("rs-" + prefix),
                        "encrypted_content": .string("opaque-" + prefix), "summary": [],
                    ]),
                ReplayItem(format: .gemini, payload: gemini),
            ], toolCalls: [first, second])
        try await store.append(id, event: .assistant(SessionAssistant(message: reply, usage: nil)))
        for call in [first, second] {
            try await store.append(
                id,
                event: .toolFinished(
                    SessionToolResult(call: call, output: output, failed: false, durationMilliseconds: nil)))
        }
    }
}
