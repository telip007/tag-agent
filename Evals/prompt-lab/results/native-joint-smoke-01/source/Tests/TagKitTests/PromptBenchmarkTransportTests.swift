import Foundation
import Testing

struct PromptBenchmarkTransportTests {
    @Test func chatLimitsPreserveTheActualConversationAndReplay() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.invalid/v1/chat/completions")))
        let messages: [[String: Any]] = [["role": "assistant", "reasoning_content": "", "content": "Done"]]
        request.httpBody = try JSONSerialization.data(withJSONObject: ["messages": messages, "stream": true])
        let capped = try BenchmarkTransport(maxTokens: 512).capped(request)
        let data = try #require(capped.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        let body = try #require(object as? [String: Any])
        #expect(body["max_tokens"] as? Int == 512)
        #expect(body["temperature"] as? Int == 0)
        let retained = try #require(body["messages"] as? [[String: String]])
        #expect(retained.first?["reasoning_content"]?.isEmpty == true)
        #expect(retained.first?["content"] == "Done")
    }

    @Test func geminiLimitsPreserveThinkingConfigurationAndContents() throws {
        var request = URLRequest(
            url: try #require(URL(string: "https://example.invalid/v1beta/models/m:streamGenerateContent?alt=sse")))
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["role": "user", "parts": [["text": "Task"]]]],
            "generationConfig": ["thinkingConfig": ["includeThoughts": true]],
        ])
        let capped = try BenchmarkTransport(maxTokens: 512).capped(request)
        let data = try #require(capped.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        let body = try #require(object as? [String: Any])
        let configuration = try #require(body["generationConfig"] as? [String: Any])
        #expect(configuration["maxOutputTokens"] as? Int == 512)
        #expect(configuration["temperature"] as? Int == 0)
        #expect((configuration["thinkingConfig"] as? [String: Bool])?["includeThoughts"] == true)
        #expect((body["contents"] as? [[String: Any]])?.count == 1)
        #expect(body["max_tokens"] == nil)
    }
}
