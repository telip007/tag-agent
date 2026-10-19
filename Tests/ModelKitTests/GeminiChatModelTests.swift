import Foundation
import OpenRouter
import Testing

@testable import ModelKit

struct GeminiChatModelTests {
    /// A reply that thinks, writes, and calls a tool with a thought signature.
    static let stream = #"""
        data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Plan","thought":true}]}}]}

        data: {"candidates":[{"content":{"role":"model","parts":[{"text":"ning.","thought":true,"thoughtSignature":"t1"}]}}]}

        data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Reading "}]}}]}

        data: {"candidates":[{"content":{"role":"model","parts":[{"text":"now."}]}}]}

        data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"read_file","args":{"path":"a.txt"}},"thoughtSignature":"t2"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":12,"thoughtsTokenCount":8,"totalTokenCount":70}}

        """#

    @Test func streamsThoughtsTextAndCalls() async throws {
        let transport = FakeTransport(body: Self.stream)
        let model = GeminiChatModel(endpoint: try Fixtures.endpoint(transport))
        var deltas: [ReplyDelta] = []
        let reply = try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) {
            deltas.append($0)
        }
        #expect(
            deltas == [
                .reasoning("Plan"), .reasoning("ning."), .text("Reading "), .text("now."), .toolCall(name: "read_file"),
            ])
        #expect(reply.message.text == "Reading now.")
        #expect(reply.message.reasoning == "Planning.")
        let call = try #require(reply.message.toolCalls.first)
        #expect(call.name == "read_file")
        #expect(call.arguments == #"{"path":"a.txt"}"#)
        #expect(call.id.hasPrefix("call_"))
        #expect(reply.usage == Usage(inputTokens: 50, outputTokens: 20))
        #expect(
            reply.message.replay == [
                ReplayItem(
                    format: .gemini,
                    payload: [
                        ["text": "Planning.", "thought": true, "thoughtSignature": "t1"],
                        ["text": "Reading now."],
                        ["functionCall": ["name": "read_file", "args": ["path": "a.txt"]], "thoughtSignature": "t2"],
                    ])
            ])
    }

    @Test func encodesContentsToolsAndThinking() throws {
        let body = GeminiChatModel.body(
            Fixtures.conversation, tools: [Fixtures.readTool], options: Fixtures.options(effort: "high"),
            includesThoughts: true)
        #expect(body["systemInstruction"] == ["parts": [["text": "Be brief."]]])
        #expect(body["generationConfig"] == ["thinkingConfig": ["includeThoughts": true, "thinkingLevel": "high"]])
        let declaration = try #require(body["tools"]?.arrayValue?.first?["functionDeclarations"]?.arrayValue?.first)
        #expect(
            declaration["parameters"] == [
                "type": "object", "properties": ["path": ["type": "string"]], "required": ["path"],
            ])
        let contents = try #require(body["contents"]?.arrayValue)
        #expect(contents.map { $0["role"]?.stringValue } == ["user", "model", "user"])
        #expect(
            contents[1]["parts"] == [
                ["text": "Reading."],
                [
                    "functionCall": ["name": "read_file", "args": ["path": "a.txt"]],
                    "thoughtSignature": .string(GeminiChatModel.unsignedCall),
                ],
                ["functionCall": ["name": "read_file", "args": ["path": "b.txt"]]],
            ])
        #expect(
            contents[2]["parts"] == [
                ["functionResponse": ["name": "read_file", "response": ["output": "A"]]],
                ["functionResponse": ["name": "read_file", "response": ["output": "B"]]],
            ])
        let plain = GeminiChatModel.body([.user("hi")], tools: [], options: Fixtures.options(), includesThoughts: false)
        #expect(plain["generationConfig"] == nil)
        #expect(plain["tools"] == nil)
        #expect(plain["systemInstruction"] == nil)
    }

    @Test func replaysSignedPartsVerbatim() async throws {
        let model = GeminiChatModel(endpoint: try Fixtures.endpoint(FakeTransport(body: Self.stream)))
        let reply = try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
        let contents = GeminiChatModel.contents([.user("hi"), .assistant(reply.message)])
        #expect(contents[1]["parts"] == reply.message.replay.first?.payload)
    }

    @Test func stripsSchemaKeysGeminiRejects() {
        let schema: JSONValue = [
            "$schema": "x", "type": "object", "additionalProperties": false,
            "properties": [
                "mode": ["const": "fast"],
                "tags": ["type": "array", "items": ["type": ["string", "null"], "examples": ["a"]]],
                "either": [
                    "anyOf": [["type": "string", "format": "uri"], ["type": "integer", "exclusiveMinimum": 0]]
                ],
            ],
        ]
        #expect(
            GeminiSchema.sanitize(schema) == [
                "type": "object",
                "properties": [
                    "mode": ["enum": ["fast"]],
                    "tags": ["type": "array", "items": ["type": "string", "nullable": true]],
                    "either": ["anyOf": [["type": "string", "format": "uri"], ["type": "integer"]]],
                ],
            ])
        #expect(GeminiSchema.sanitize("text") == "text")
    }

    @Test func throwsStreamedAndHTTPErrors() async throws {
        let streamed = Fixtures.sse([#"{"error":{"code":429,"message":"Quota","status":"RESOURCE_EXHAUSTED"}}"#])
        let model = GeminiChatModel(endpoint: try Fixtures.endpoint(FakeTransport(body: streamed)))
        await #expect(throws: ProviderError.usageLimit(.openCodeGo, detail: "Quota", manageURL: nil)) {
            try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
        }
        let http = FakeTransport(status: 400, body: #"{"error":{"code":400,"message":"Bad schema"}}"#)
        await #expect(throws: ProviderError.http(.openCodeGo, status: 400, detail: "Bad schema")) {
            try await GeminiChatModel(endpoint: try Fixtures.endpoint(http))
                .reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
        }
        for body in ["", Fixtures.sse(["nope"])] {
            let empty = GeminiChatModel(endpoint: try Fixtures.endpoint(FakeTransport(body: body)))
            await #expect(throws: ProviderError.self) {
                try await empty.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
            }
        }
    }

    @Test func keepsNoReplayWithoutSignatures() async throws {
        let body = Fixtures.sse([
            #"{"candidates":[{"content":{"parts":[{"text":"Hi"},{"inlineData":{}}]}}]}"#,
            #"{"candidates":[{"content":{"parts":[{"functionCall":{"id":"f1","name":"list"}}]}}]}"#,
        ])
        let model = GeminiChatModel(endpoint: try Fixtures.endpoint(FakeTransport(body: body)))
        let reply = try await model.reply(to: [.user("hi")], tools: [], options: Fixtures.options()) { _ in }
        #expect(
            reply.message
                == AssistantMessage(text: "Hi", toolCalls: [ToolCall(id: "f1", name: "list", arguments: "{}")]))
        #expect(reply.usage == nil)
    }
}
