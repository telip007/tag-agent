import Foundation
import OpenRouter
import Testing

@testable import ModelKit

struct AnthropicChatModelTests {
    /// A reply that thinks (signed), writes and calls a tool with streamed input.
    static let stream = #"""
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","role":"assistant","content":[],"usage":{"input_tokens":10,"cache_read_input_tokens":90,"cache_creation_input_tokens":0,"output_tokens":1}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me look."}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig=="}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: ping
        data: {"type":"ping"}

        event: content_block_start
        data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Reading."}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":1}

        event: content_block_start
        data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"read_file","input":{}}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"path\": "}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\"a.txt\"}"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":2}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":42}}

        event: message_stop
        data: {"type":"message_stop"}

        """#

    @Test func streamsThinkingTextAndToolUse() async throws {
        let transport = FakeTransport(body: Self.stream)
        let model = AnthropicChatModel(endpoint: try Fixtures.endpoint(transport))
        var deltas: [ReplyDelta] = []
        let reply = try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) {
            deltas.append($0)
        }
        #expect(deltas == [.reasoning("Let me look."), .text("Reading."), .toolCall(name: "read_file")])
        #expect(reply.message.text == "Reading.")
        #expect(reply.message.reasoning == "Let me look.")
        #expect(
            reply.message.toolCalls == [ToolCall(id: "toolu_1", name: "read_file", arguments: #"{"path":"a.txt"}"#)])
        #expect(reply.usage == Usage(inputTokens: 100, outputTokens: 42))
        let replayed = try #require(reply.message.replay.first)
        #expect(replayed.format == .anthropicMessages)
        #expect(
            replayed.payload == [
                ["type": "thinking", "thinking": "Let me look.", "signature": "sig=="],
                ["type": "text", "text": "Reading."],
                ["type": "tool_use", "id": "toolu_1", "name": "read_file", "input": ["path": "a.txt"]],
            ])
        let request = try #require(transport.requests.last)
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
    }

    @Test func replaysThinkingBlocksVerbatimOnTheNextTurn() async throws {
        let first = FakeTransport(body: Self.stream)
        let reply = try await AnthropicChatModel(endpoint: try Fixtures.endpoint(first))
            .reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
        let messages = AnthropicChatModel.messages([
            .user("hi"), .assistant(reply.message), .tool(callID: "toolu_1", name: "read_file", content: "A"),
        ])
        #expect(messages[1]["content"] == reply.message.replay.first?.payload)
    }

    @Test func encodesSystemToolsAndMergedToolResults() throws {
        let settings = AnthropicChatModel.Settings(model: "m", maxTokens: 64_000, thinking: .budget)
        let body = AnthropicChatModel.body(
            Fixtures.conversation, tools: [Fixtures.readTool], options: Fixtures.options(), settings: settings)
        #expect(body["max_tokens"] == 64_000)
        #expect(body["stream"] == true)
        #expect(body["thinking"] == nil)
        #expect(body["system"] == [["type": "text", "text": "Be brief.", "cache_control": ["type": "ephemeral"]]])
        let tool = try #require(body["tools"]?.arrayValue?.first)
        #expect(tool["input_schema"]?["required"] == ["path"])
        #expect(tool["cache_control"] == ["type": "ephemeral"])
        let messages = try #require(body["messages"]?.arrayValue)
        #expect(messages.map { $0["role"]?.stringValue } == ["user", "assistant", "user"])
        #expect(
            messages[1]["content"] == [
                ["type": "text", "text": "Reading."],
                ["type": "tool_use", "id": "c1", "name": "read_file", "input": ["path": "a.txt"]],
                ["type": "tool_use", "id": "c2", "name": "read_file", "input": ["path": "b.txt"]],
            ])
        #expect(
            messages[2]["content"] == [
                ["type": "tool_result", "tool_use_id": "c1", "content": "A"],
                ["type": "tool_result", "tool_use_id": "c2", "content": "B", "cache_control": ["type": "ephemeral"]],
            ])
    }

    @Test func tellsTheModelHowHardToThink() {
        func fields(_ effort: String?, _ thinking: AnthropicChatModel.Thinking, maxTokens: Int = 32_000) -> JSONValue {
            let settings = AnthropicChatModel.Settings(model: "m", maxTokens: maxTokens, thinking: thinking)
            let body = AnthropicChatModel.body(
                [.user("hi")], tools: [], options: Fixtures.options(effort: effort), settings: settings)
            return ["thinking": body["thinking"] ?? .null, "output_config": body["output_config"] ?? .null]
        }
        #expect(
            fields("xhigh", .adaptive) == [
                "thinking": ["type": "adaptive", "display": "summarized"], "output_config": ["effort": "xhigh"],
            ])
        #expect(
            fields("high", .budget) == [
                "thinking": ["type": "enabled", "budget_tokens": 16_000], "output_config": nil,
            ])
        #expect(fields("max", .budget, maxTokens: 8192)["thinking"]?["budget_tokens"] == 7168)
        #expect(fields("low", .budget, maxTokens: 1500) == ["thinking": nil, "output_config": nil])
        #expect(fields("none", .adaptive)["thinking"] == ["type": "disabled"])
    }

    @Test func throwsStreamedErrors() async throws {
        let cases: [(String, ProviderError)] = [
            (#"{"type":"overloaded_error","message":"Overloaded"}"#, .unavailable(.openCodeGo, detail: "Overloaded")),
            (
                #"{"type":"rate_limit_error","message":"Slow down"}"#,
                .usageLimit(.openCodeGo, detail: "Slow down", manageURL: nil)
            ),
            (#"{"type":"authentication_error","message":"No"}"#, .signInRequired(.openCodeGo, detail: "No")),
        ]
        for (error, expected) in cases {
            let body = Fixtures.sse([
                ("message_start", #"{"type":"message_start","message":{"usage":{"input_tokens":1}}}"#),
                ("error", #"{"type":"error","error":\#(error)}"#),
            ])
            let model = AnthropicChatModel(endpoint: try Fixtures.endpoint(FakeTransport(body: body)))
            await #expect(throws: expected) {
                try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
            }
        }
    }

    @Test func keepsNoReplayWithoutThinkingAndRejectsEmptyStreams() async throws {
        let body = Fixtures.sse([
            ("message_start", #"{"type":"message_start","message":{"usage":{"input_tokens":5,"output_tokens":0}}}"#),
            (
                "content_block_start",
                #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"Hi"}}"#
            ),
            ("message_delta", #"{"type":"message_delta","usage":{"input_tokens":7,"output_tokens":2}}"#),
        ])
        let model = AnthropicChatModel(endpoint: try Fixtures.endpoint(FakeTransport(body: body)))
        var deltas: [ReplyDelta] = []
        let reply = try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) {
            deltas.append($0)
        }
        #expect(deltas == [.text("Hi")])
        #expect(reply.message == AssistantMessage(text: "Hi"))
        #expect(reply.usage == Usage(inputTokens: 7, outputTokens: 2))
        let empty = AnthropicChatModel(endpoint: try Fixtures.endpoint(FakeTransport(body: "")))
        await #expect(throws: ProviderError.self) {
            try await empty.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
        }
    }
}
