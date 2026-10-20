import Foundation
import OpenRouter
import Testing

@testable import ModelKit

struct CacheUsageTests {
    @Test func openRouterRetainsCacheDetailsWithoutAddingThemToInputAgain() throws {
        let json =
            #"{"id":"g","object":"chat.completion.chunk","created":0,"model":"m","choices":[],"usage":{"prompt_tokens":100,"completion_tokens":5,"total_tokens":105,"cost":0.2,"prompt_tokens_details":{"cached_tokens":80,"cache_write_tokens":10}}}"#
        var accumulator = ChatStreamAccumulator()
        accumulator.add(try JSONDecoder().decode(ChatStreamChunk.self, from: Data(json.utf8)))
        let usage = try #require(OpenRouterChatModel.reply(from: accumulator).usage)
        #expect(
            usage
                == Usage(inputTokens: 100, outputTokens: 5, cost: 0.2, cachedInputTokens: 80, cacheWriteInputTokens: 10)
        )
        #expect(usage.totalTokens == 105)
    }

    @Test func chatCompletionsRetainsReportedCacheReadsAndWrites() throws {
        var decoder = ChatCompletionsDecoder(provider: .openCodeGo)
        _ = try decoder.decode(
            ServerSentEvent(
                data:
                    #"{"choices":[],"usage":{"prompt_tokens":100,"completion_tokens":5,"prompt_tokens_details":{"cached_tokens":80,"cache_write_tokens":10}}}"#
            ))
        #expect(
            try decoder.reply().usage
                == Usage(inputTokens: 100, outputTokens: 5, cachedInputTokens: 80, cacheWriteInputTokens: 10))
    }

    @Test func responsesRetainsCacheDetails() {
        let event = ResponsesEvent(
            data:
                #"{"type":"response.completed","response":{"usage":{"input_tokens":100,"output_tokens":5,"input_tokens_details":{"cached_tokens":80,"cache_write_tokens":10}}}}"#,
            provider: .codex)
        #expect(
            event
                == .completed(
                    Usage(inputTokens: 100, outputTokens: 5, cachedInputTokens: 80, cacheWriteInputTokens: 10)))
    }

    @Test func geminiRetainsImplicitCacheHits() throws {
        var decoder = GeminiDecoder(provider: .openCodeGo)
        _ = try decoder.decode(
            ServerSentEvent(
                data:
                    #"{"candidates":[],"usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":3,"thoughtsTokenCount":2,"cachedContentTokenCount":80}}"#
            ))
        #expect(try decoder.reply().usage == Usage(inputTokens: 100, outputTokens: 5, cachedInputTokens: 80))
    }

    @Test func anthropicMergesIndependentUsageCountersAndHonorsZero() throws {
        var decoder = AnthropicDecoder(provider: .openCodeGo)
        let events = [
            #"{"type":"message_start","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":80,"cache_creation_input_tokens":20,"output_tokens":0}}}"#,
            #"{"type":"message_delta","usage":{"input_tokens":12,"output_tokens":5}}"#,
        ]
        for event in events { _ = try decoder.decode(ServerSentEvent(data: event)) }
        #expect(
            try decoder.reply().usage
                == Usage(inputTokens: 112, outputTokens: 5, cachedInputTokens: 80, cacheWriteInputTokens: 20))
        _ = try decoder.decode(
            ServerSentEvent(data: #"{"type":"message_delta","usage":{"cache_read_input_tokens":0}}"#))
        #expect(
            try decoder.reply().usage
                == Usage(inputTokens: 32, outputTokens: 5, cachedInputTokens: 0, cacheWriteInputTokens: 20))
    }

    @Test func omittedCacheMetricsRemainUnknown() throws {
        var chat = ChatCompletionsDecoder(provider: .openCodeGo)
        _ = try chat.decode(ServerSentEvent(data: #"{"choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2}}"#))
        #expect(try chat.reply().usage == Usage(inputTokens: 1, outputTokens: 2))
        var gemini = GeminiDecoder(provider: .openCodeGo)
        _ = try gemini.decode(
            ServerSentEvent(
                data: #"{"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"cachedContentTokenCount":0}}"#)
        )
        #expect(try gemini.reply().usage == Usage(inputTokens: 1, outputTokens: 2, cachedInputTokens: 0))
    }
}

struct CachePrefixTests {
    @Test func responsesEncodesToolSchemaKeysInAStableOrder() async throws {
        let transport = FakeTransport(
            body: Fixtures.sse([
                #"{"type":"response.completed","response":{"usage":{"input_tokens":1,"output_tokens":1}}}"#
            ]))
        let model = ResponsesChatModel(endpoint: try Fixtures.endpoint(transport))
        let tool = ToolSpec(
            name: "read", description: "Read",
            parameters: [
                "type": "object", "required": ["path"], "properties": ["path": ["type": "string"]],
            ])
        for _ in 0..<5 {
            _ = try await model.reply(to: [.user("Hi")], tools: [tool], options: Fixtures.options()) { _ in }
        }
        let schema = #""parameters":{"properties":{"path":{"type":"string"}},"required":["path"],"type":"object"}"#
        #expect(
            transport.requests.allSatisfy { request in
                request.httpBody.flatMap { String(bytes: $0, encoding: .utf8) }?.contains(schema) == true
            })
    }
}
