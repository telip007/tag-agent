import Foundation
import OpenRouter
import Testing

@testable import ModelKit

/// The OpenRouter key for live tests, when they were asked for.
private let liveKey: String? = {
    let environment = ProcessInfo.processInfo.environment
    guard environment["TAG_LIVE_TESTS"] == "1" else {
        return nil
    }
    return environment["OPENROUTER_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
}()

/// Real requests through OpenRouter, which serves three of the four wire
/// formats: a tool call and its result, then the final answer. Run with
/// `TAG_LIVE_TESTS=1` and `OPENROUTER_API_KEY` set; skipped otherwise.
@Suite(.enabled(if: liveKey != nil))
struct LiveAdapterTests {
    static let key = liveKey

    private static let weather = ToolSpec(
        name: "get_weather",
        description: "The weather in a city.",
        parameters: [
            "type": "object", "properties": ["city": ["type": "string"]], "required": ["city"],
        ],
    )

    private func endpoint(_ path: String, model: String) throws -> WireEndpoint {
        let key = try #require(Self.key)
        let url = try #require(URL(string: "https://openrouter.ai/api/v1/\(path)"))
        return WireEndpoint(url: url, model: model, provider: .openRouter) {
            ["Authorization": "Bearer \(key)", "x-api-key": key]
        }
    }

    /// Asks for the weather, answers the tool call, and returns the final text.
    private func roundTrip(_ model: any ChatModel) async throws -> String {
        let options = ReplyOptions(sessionID: UUID().uuidString)
        var conversation: [Message] = [
            .system("Use the get_weather tool to answer weather questions."),
            .user("What is the weather in Berlin? Use the tool, then answer in one short sentence."),
        ]
        let first = try await model.reply(to: conversation, tools: [Self.weather], options: options) { _ in }
        let call = try #require(first.message.toolCalls.first)
        #expect(call.name == "get_weather")
        #expect(call.arguments.contains("Berlin"))
        conversation.append(.assistant(first.message))
        conversation.append(.tool(callID: call.id, name: call.name, content: "Sunny, 21 °C"))

        var streamed = ""
        let second = try await model.reply(to: conversation, tools: [Self.weather], options: options) { delta in
            if case .text(let text) = delta {
                streamed += text
            }
        }
        let text = try #require(second.message.text)
        #expect(text == streamed)
        #expect(second.usage.map { $0.inputTokens > 0 } == true)
        return text
    }

    @Test func chatCompletions() async throws {
        let text = try await roundTrip(
            ChatCompletionsChatModel(endpoint: try endpoint("chat/completions", model: "deepseek/deepseek-v4.1-flash")))
        #expect(text.contains("21"))
    }

    @Test func responses() async throws {
        let model = ResponsesChatModel(
            endpoint: try endpoint("responses", model: "openai/gpt-5-mini"), includeEncryptedReasoning: true)
        #expect(try await roundTrip(model).contains("21"))
    }

    @Test func anthropicMessages() async throws {
        let model = AnthropicChatModel(endpoint: try endpoint("messages", model: "anthropic/claude-haiku-5.5"))
        #expect(try await roundTrip(model).contains("21"))
    }
}
