import Foundation
import OpenRouter
import Testing

@testable import ModelKit

struct ChatCompletionsChatModelTests {
    /// A reply that reasons, writes, calls a tool in fragments and reports usage.
    static let stream = Fixtures.sse([
        #"{"choices":[{"index":0,"delta":{"role":"assistant","reasoning_content":"Think"}}]}"#,
        #"{"choices":[{"index":0,"delta":{"reasoning_content":"ing.","reasoning":"ing."}}]}"#,
        #"{"choices":[{"index":0,"delta":{"content":"Sure. "}}]}"#,
        #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_9","type":"function","function":{"name":"read_file","arguments":""}}]}}]}"#,
        #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"path\":"}}]}}]}"#,
        #"{"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"a.txt\"}"}}]}}]}"#,
        #"{"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#,
        #"{"choices":[],"usage":{"prompt_tokens":120,"completion_tokens":30,"total_tokens":150,"cost":0.0012}}"#,
        "[DONE]",
    ])

    @Test func streamsReasoningTextAndToolCalls() async throws {
        let transport = FakeTransport(body: Self.stream)
        let model = ChatCompletionsChatModel(endpoint: try Fixtures.endpoint(transport))
        var deltas: [ReplyDelta] = []
        let reply = try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) {
            deltas.append($0)
        }
        #expect(deltas == [.reasoning("Think"), .reasoning("ing."), .text("Sure. "), .toolCall(name: "read_file")])
        #expect(reply.message.text == "Sure. ")
        #expect(reply.message.reasoning == "Thinking.")
        #expect(reply.message.toolCalls == [ToolCall(id: "call_9", name: "read_file", arguments: #"{"path":"a.txt"}"#)])
        #expect(reply.message.replay == [ReplayItem(format: .chatCompletions, payload: ["reasoning": "Thinking."])])
        #expect(reply.usage == Usage(inputTokens: 120, outputTokens: 30, cost: 0.0012))
    }

    @Test func encodesTheConversationToolsAndEffort() async throws {
        let transport = FakeTransport(body: Self.stream)
        let model = ChatCompletionsChatModel(endpoint: try Fixtures.endpoint(transport))
        _ = try await model.reply(
            to: Fixtures.conversation, tools: [Fixtures.readTool], options: Fixtures.options(effort: "high")
        ) { _ in }
        let body = try transport.lastBody()
        #expect(body["model"] == "test-model")
        #expect(body["stream"] == true)
        #expect(body["stream_options"] == ["include_usage": true])
        #expect(body["reasoning_effort"] == "high")
        #expect(body["tools"]?.arrayValue?.first?["function"]?["name"] == "read_file")
        let messages = try #require(body["messages"]?.arrayValue)
        #expect(messages.map { $0["role"]?.stringValue } == ["system", "user", "assistant", "tool", "tool"])
        #expect(messages[2]["tool_calls"]?.arrayValue?.count == 2)
        #expect(messages[2]["tool_calls"]?.arrayValue?.first?["function"]?["arguments"] == #"{"path":"a.txt"}"#)
        #expect(messages[3] == ["role": "tool", "tool_call_id": "c1", "content": "A"])
        let request = try #require(transport.requests.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == TagUserAgent.value)
    }

    @Test func sendsReasoningBackOnlyFromItsOwnFormatAndWhenAsked() throws {
        let own = AssistantMessage(
            text: nil, reasoning: "Because.",
            replay: [ReplayItem(format: .chatCompletions, payload: ["reasoning": "Because."])],
            toolCalls: [ToolCall(id: "c1", name: "read_file", arguments: "{}")])
        let foreign = AssistantMessage(
            text: "Hi", reasoning: "Hmm", replay: [ReplayItem(format: .gemini, payload: ["reasoning": "Hmm"])])
        let body = ChatCompletionsChatModel.body(
            [.assistant(own), .assistant(foreign)], tools: [], options: Fixtures.options(), model: "m",
            reasoningField: "reasoning_content")
        let messages = try #require(body["messages"]?.arrayValue)
        #expect(messages[0]["reasoning_content"] == "Because.")
        #expect(messages[0]["content"] == .null)
        #expect(messages[1]["reasoning_content"]?.stringValue?.isEmpty == true)
        #expect(messages[1]["content"] == "Hi")
        let silent = ChatCompletionsChatModel.body(
            [.assistant(own)], tools: [], options: Fixtures.options(), model: "m", reasoningField: nil)
        #expect(silent["messages"]?.arrayValue?.first?["reasoning_content"] == nil)
        #expect(silent["tools"] == nil)
        #expect(silent["reasoning_effort"] == nil)
    }

    @Test func configuredInterleavingIncludesAnEmptyFieldWhenReasoningIsAbsent() throws {
        let message = AssistantMessage(
            toolCalls: [ToolCall(id: "call", name: "read_file", arguments: #"{"path":"a.py"}"#)])
        let options = Fixtures.options()
        let configured = ChatCompletionsChatModel.body(
            [.assistant(message), .assistant(AssistantMessage(text: "Done"))], tools: [], options: options,
            model: "m", reasoningField: "reasoning_content")
        let turns = try #require(configured["messages"]?.arrayValue)
        #expect(turns.count == 2)
        #expect(turns.allSatisfy { $0["reasoning_content"]?.stringValue?.isEmpty == true })
        let disabled = ChatCompletionsChatModel.body(
            [.assistant(message)], tools: [], options: options, model: "m", reasoningField: nil)
        #expect(disabled["messages"]?.arrayValue?.first?["reasoning_content"] == nil)
    }

    @Test func mapsHTTPErrors() async throws {
        let cases: [(Int, ProviderError)] = [
            (401, .signInRequired(.openCodeGo, detail: "The API key was rejected. Bad key")),
            (403, .notEligible(.openCodeGo, detail: "Bad key")),
            (429, .usageLimit(.openCodeGo, detail: "Bad key", manageURL: nil)),
            (503, .unavailable(.openCodeGo, detail: "Bad key")),
            (400, .http(.openCodeGo, status: 400, detail: "Bad key")),
        ]
        for (status, expected) in cases {
            let transport = FakeTransport(status: status, body: #"{"error":{"message":"Bad key"}}"#)
            let model = ChatCompletionsChatModel(endpoint: try Fixtures.endpoint(transport))
            await #expect(throws: expected) {
                try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
            }
        }
    }

    @Test func throwsErrorsReportedInTheStream() async throws {
        let transport = FakeTransport(body: Fixtures.sse([#"{"error":{"message":"Overloaded","code":529}}"#]))
        let model = ChatCompletionsChatModel(endpoint: try Fixtures.endpoint(transport))
        await #expect(throws: ProviderError.unavailable(.openCodeGo, detail: "Overloaded")) {
            try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
        }
    }

    @Test func rejectsStreamsWithoutAReply() async throws {
        for body in ["", Fixtures.sse(["not json"])] {
            let model = ChatCompletionsChatModel(endpoint: try Fixtures.endpoint(FakeTransport(body: body)))
            await #expect(throws: ProviderError.self) {
                try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
            }
        }
    }

    @Test func numbersCallsWithoutIDsAndFillsEmptyArguments() async throws {
        let body = Fixtures.sse([
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"list"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"name":"read_file","arguments":"{}"}}]}}]}"#,
        ])
        let model = ChatCompletionsChatModel(endpoint: try Fixtures.endpoint(FakeTransport(body: body)))
        let reply = try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
        #expect(
            reply.message.toolCalls == [
                ToolCall(id: "call_0", name: "list", arguments: "{}"),
                ToolCall(id: "call_1", name: "read_file", arguments: "{}"),
            ])
        #expect(reply.message.text == nil)
        #expect(reply.usage == nil)
    }
}
