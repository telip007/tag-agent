import Foundation
import OpenRouter
import Testing

@testable import ModelKit

struct ResponsesChatModelTests {
    private static let options = ReplyOptions(reasoningEffort: "high", sessionID: "session-1")
    private static let reasoningItem: JSONValue = [
        "type": "reasoning", "id": "rs_1", "encrypted_content": "secret", "summary": [],
    ]

    private static func model(
        _ transport: CodexTestTransport, includeEncryptedReasoning: Bool = false,
    ) -> ResponsesChatModel {
        let endpoint = WireEndpoint(
            url: URL(filePath: "/v1/responses"), model: "gpt-test", provider: .codex,
            headers: { ["Authorization": "Bearer token"] }, transport: transport)
        return ResponsesChatModel(endpoint: endpoint, includeEncryptedReasoning: includeEncryptedReasoning)
    }

    private static func reply(streaming events: [String]) async throws -> (ModelReply, [ReplyDelta]) {
        try await reply(using: CodexTestTransport(body: CodexFixtures.sse(events)))
    }

    private static func reply(using transport: CodexTestTransport) async throws -> (ModelReply, [ReplyDelta]) {
        var deltas: [ReplyDelta] = []
        let reply = try await model(transport).reply(to: [.user("Hi")], tools: [], options: options) {
            deltas.append($0)
        }
        return (reply, deltas)
    }

    private static func malformed(_ detail: String) -> ProviderError {
        .malformedResponse(.codex, detail: detail)
    }

    // MARK: Request

    @Test func sendsTheWholeConversationWithoutServerState() {
        let body = ResponsesChatModel.body(
            for: [.system("Be brief."), .user("Hi"), .system("Use tools.")],
            tools: [ToolSpec(name: "read", description: "Reads a file.", parameters: ["type": "object"])],
            options: Self.options, model: "gpt-test", includeEncryptedReasoning: true)
        let expectedTool: JSONValue = [
            "type": "function", "name": "read", "description": "Reads a file.", "parameters": ["type": "object"],
            "strict": false,
        ]
        guard case .object(let fields) = body else {
            Issue.record("The body isn't an object.")
            return
        }
        #expect(fields["model"] == "gpt-test")
        #expect(fields["instructions"] == "Be brief.\n\nUse tools.")
        #expect(fields["store"] == false)
        #expect(fields["stream"] == true)
        #expect(fields["tools"] == [expectedTool])
        #expect(fields["tool_choice"] == "auto")
        #expect(fields["reasoning"] == ["effort": "high", "summary": "auto"])
        #expect(fields["include"] == ["reasoning.encrypted_content"])
        #expect(fields["prompt_cache_key"] == "session-1")
        for forbidden in ["temperature", "top_p", "max_output_tokens", "metadata", "user", "truncation"] {
            #expect(fields[forbidden] == nil)
        }
        #expect(fields["previous_response_id"] == nil)
    }

    @Test func leavesOutOptionalFieldsWhenUnused() {
        let body = ResponsesChatModel.body(
            for: [.user("Hi")], tools: [], options: ReplyOptions(sessionID: ""), model: "m",
            includeEncryptedReasoning: false)
        guard case .object(let fields) = body else {
            Issue.record("The body isn't an object.")
            return
        }
        #expect(Set(fields.keys) == ["model", "input", "store", "stream"])
    }

    @Test func translatesMessagesIntoInputItems() {
        let assistant = AssistantMessage(
            text: "Reading.", reasoning: "Thinking",
            replay: [
                ReplayItem(format: .anthropicMessages, payload: ["signature": "x"]),
                ReplayItem(format: .responses, payload: Self.reasoningItem),
            ],
            toolCalls: [ToolCall(id: "call_1", name: "read", arguments: #"{"path":"a"}"#)])
        let (instructions, items) = ResponsesChatModel.input(for: [
            .user("Hi"), .assistant(assistant), .tool(callID: "call_1", name: "read", content: "contents"),
        ])
        let expected: [JSONValue] = [
            ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Hi"]]],
            Self.reasoningItem,
            [
                "type": "message", "role": "assistant",
                "content": [["type": "output_text", "text": "Reading.", "annotations": []]],
            ],
            ["type": "function_call", "call_id": "call_1", "name": "read", "arguments": #"{"path":"a"}"#],
            ["type": "function_call_output", "call_id": "call_1", "output": "contents"],
        ]
        #expect(instructions == nil)
        #expect(items == expected)
    }

    @Test func postsWithTheEndpointsHeaders() async throws {
        let transport = CodexTestTransport(body: CodexFixtures.sse([#"{"type":"response.completed","response":{}}"#]))
        _ = try await Self.reply(using: transport)
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        #expect(CodexFixtures.json(request)["store"] as? Bool == false)
    }

    // MARK: Stream

    @Test func streamsTextReasoningAndToolCalls() async throws {
        let (reply, deltas) = try await Self.reply(streaming: [
            #"{"type":"response.created","response":{}}"#,
            #"{"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_1"}}"#,
            #"{"type":"response.reasoning_summary_part.added","output_index":0,"summary_index":0}"#,
            #"{"type":"response.reasoning_summary_text.delta","output_index":0,"delta":"Plan"}"#,
            #"{"type":"response.reasoning_summary_part.added","output_index":0,"summary_index":1}"#,
            #"{"type":"response.reasoning_text.delta","output_index":0,"delta":"More"}"#,
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_1","encrypted_content":"secret","summary":[{"type":"summary_text","text":"Plan"},{"type":"summary_text","text":"More"}]}}"#,
            #"{"type":"response.output_text.delta","output_index":1,"delta":"Hel"}"#,
            #"{"type":"response.output_text.delta","output_index":1,"delta":"lo"}"#,
            #"{"type":"response.output_item.done","output_index":1,"item":{"type":"message","content":[{"type":"output_text","text":"Hello"}]}}"#,
            #"{"type":"response.output_item.added","output_index":2,"item":{"type":"function_call","name":"read","call_id":"call_1"}}"#,
            #"{"type":"response.function_call_arguments.delta","output_index":2,"delta":"{\"path\""}"#,
            #"{"type":"response.function_call_arguments.delta","output_index":2,"delta":":\"a\"}"}"#,
            #"{"type":"response.output_item.done","output_index":2,"item":{"type":"function_call","name":"read","call_id":"call_1","arguments":"{\"path\":\"a\"}"}}"#,
            #"{"type":"response.completed","response":{"usage":{"input_tokens":12,"output_tokens":5}}}"#,
        ])
        #expect(
            deltas == [
                .reasoning("Plan"), .reasoning("\n\n"), .reasoning("More"), .text("Hel"), .text("lo"),
                .toolCall(name: "read"),
            ])
        #expect(reply.message.text == "Hello")
        #expect(reply.message.reasoning == "Plan\n\nMore")
        #expect(reply.message.toolCalls == [ToolCall(id: "call_1", name: "read", arguments: #"{"path":"a"}"#)])
        #expect(reply.message.replay.map(\.format) == [.responses])
        #expect(reply.usage == Usage(inputTokens: 12, outputTokens: 5))
    }

    @Test func keepsOnlyReasoningThatCanBeSentBack() async throws {
        let (reply, _) = try await Self.reply(streaming: [
            #"{"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_1","summary":[]}}"#,
            #"{"type":"response.output_item.done","output_index":1,"item":{"type":"message","content":[{"type":"refusal","refusal":"No."}]}}"#,
            #"{"type":"response.completed","response":{}}"#,
        ])
        #expect(reply.message.replay.isEmpty)
        #expect(reply.message.text == "No.")
        #expect(reply.message.reasoning == nil)
        #expect(reply.usage == nil)
    }

    @Test func failsWhenTheStreamEndsEarly() async {
        await #expect(throws: Self.malformed("The stream ended before the reply was complete.")) {
            _ = try await Self.reply(streaming: [#"{"type":"response.output_text.delta","delta":"Hi"}"#])
        }
    }

    @Test func failsOnAnUnfinishedToolCall() async {
        await #expect(throws: Self.malformed("A tool call was left unfinished.")) {
            _ = try await Self.reply(streaming: [
                #"{"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","name":"read"}}"#,
                #"{"type":"response.completed","response":{}}"#,
            ])
        }
    }

    @Test func failsOnEventsThatArentJSON() async {
        await #expect(throws: Self.malformed("An event wasn't JSON.")) {
            _ = try await Self.reply(streaming: ["nonsense"])
        }
        #expect(ResponsesEvent(data: "[DONE]", provider: .codex) == .ignored)
    }

    @Test func reportsAFailedResponseMidStream() async {
        let usageURL = URL(string: "https://chatgpt.com/settings/usage")
        await #expect(throws: ProviderError.usageLimit(.codex, detail: "Limit reached.", manageURL: usageURL)) {
            _ = try await Self.reply(streaming: [
                #"{"type":"response.output_text.delta","delta":"Hi"}"#,
                #"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"Limit reached."}}}"#,
            ])
        }
    }

    @Test func reportsErrorEventsAndIncompleteResponses() {
        #expect(
            ResponsesEvent(data: #"{"type":"error","code":"server_error","message":"Oops."}"#, provider: .codex)
                == .failed(.malformedResponse(.codex, detail: "Oops. (server_error)")))
        #expect(
            ResponsesEvent(
                data: #"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"content_filter"}}}"#,
                provider: .codex)
                == .failed(.unavailable(.codex, detail: "The reply stopped early (content_filter).")))
    }

    // MARK: Errors

    @Test func reportsHTTPErrorsBeforeTheStream() async {
        await #expect(throws: ProviderError.signInRequired(.codex, detail: "Bad token.")) {
            _ = try await Self.reply(using: CodexTestTransport(status: 401, body: #"{"detail":"Bad token."}"#))
        }
    }
}
