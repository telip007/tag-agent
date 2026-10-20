import Foundation
import OpenRouter
import Testing

@testable import ModelKit

struct OpenRouterChatModelTests {
    private func chunk(_ delta: String, usage: String = "") throws -> ChatStreamChunk {
        let json = """
            {"id":"g","object":"chat.completion.chunk","created":0,"model":"m",\
            "choices":[{"index":0,"delta":\(delta),"finish_reason":null}]\(usage)}
            """
        return try JSONDecoder().decode(ChatStreamChunk.self, from: Data(json.utf8))
    }

    @Test func aChunkBecomesReasoningTextAndToolNames() throws {
        let call = #"{"index":0,"id":"a","type":"function","function":{"name":"bash","arguments":""}}"#
        let delta = #"{"reasoning":"Hm.","content":"Ok","tool_calls":["# + call + "]}"
        let deltas = OpenRouterChatModel.deltas(in: try chunk(delta))
        #expect(deltas == [.reasoning("Hm."), .text("Ok"), .toolCall(name: "bash")])
    }

    @Test func argumentFragmentsAndEmptyPiecesAreSkipped() throws {
        let delta = #"{"content":"","tool_calls":[{"index":0,"function":{"arguments":"{}"}}]}"#
        #expect(OpenRouterChatModel.deltas(in: try chunk(delta)).isEmpty)
    }

    @Test func theAccumulatedStreamBecomesANeutralReply() throws {
        var accumulator = ChatStreamAccumulator()
        let call = #"{"index":0,"id":"c1","type":"function","function":{"name":"bash","arguments":"{}"}}"#
        accumulator.add(try chunk(#"{"reasoning":"Think.","content":"Hi","tool_calls":["# + call + "]}"))
        let usage = #","usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12,"cost":0.5}"#
        accumulator.add(try chunk(#"{"content":"!"}"#, usage: usage))

        let reply = OpenRouterChatModel.reply(from: accumulator)
        #expect(reply.message.text == "Hi!")
        #expect(reply.message.reasoning == "Think.")
        #expect(reply.message.toolCalls == [ToolCall(id: "c1", name: "bash", arguments: "{}")])
        #expect(reply.usage == Usage(inputTokens: 10, outputTokens: 2, cost: 0.5))
    }

    @Test func requestsCarryToolsEffortAndSession() {
        let tool = ToolSpec(name: "echo", description: "Echo", parameters: ["type": "object"])
        let conversation: [Message] = [
            .system("You are Tag."), .user("Hi"),
            .assistant(AssistantMessage(text: "On it.", toolCalls: [ToolCall(id: "1", name: "echo", arguments: "{}")])),
            .tool(callID: "1", name: "echo", content: "done"),
        ]
        let options = ReplyOptions(reasoningEffort: "high", sessionID: "s1")
        let request = OpenRouterChatModel.request(conversation, tools: [tool], model: "m/x", options: options)

        #expect(request.messages.count == 4)
        #expect(request.reasoningEffort == "high")
        #expect(request.sessionId == "s1")
        #expect(request.tools?.count == 1)
        guard case .assistant(let assistant) = request.messages[2] else {
            Issue.record("expected an assistant message")
            return
        }
        #expect(assistant.text == "On it.")
        #expect(assistant.toolCalls?.first?.function.name == "echo")
    }

    @Test(arguments: ["deepseek/deepseek-v4.1-flash", "google/gemini-2.5-pro", "openai/gpt-5.4"])
    func enablesAutomaticCachingAndOmitsAnEmptySession(model: String) throws {
        let request = OpenRouterChatModel.request(
            [.user("Hi")], tools: [], model: model, options: ReplyOptions(sessionID: ""))
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
        #expect(json["cache_control"] == ["type": "ephemeral"])
        #expect(json["session_id"] == nil)
        #expect(json["messages"]?.arrayValue?.first?["content"] == "Hi")
    }

    @Test(arguments: [
        "anthropic/claude-sonnet-4.6", "~anthropic/claude-sonnet-latest", "qwen/qwen3-coder-plus",
        "deepseek/deepseek-v3.2",
        "openrouter/auto", "openrouter/auto-beta", "openrouter/pareto-code", "openrouter/free",
    ])
    func marksOptInProvidersHistory(model: String) throws {
        let request = OpenRouterChatModel.request(
            Fixtures.conversation, tools: [Fixtures.readTool], model: model, options: Fixtures.options())
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
        let messages = try #require(json["messages"]?.arrayValue)
        #expect(messages[0]["content"]?.arrayValue?.last?["cache_control"] == ["type": "ephemeral"])
        #expect(messages[1]["content"]?.arrayValue?.last?["cache_control"] == ["type": "ephemeral"])
        #expect(messages[3]["content"] == [["type": "text", "text": "A"]])
        #expect(messages[4]["content"]?.arrayValue?.last?["cache_control"] == ["type": "ephemeral"])
        #expect(messages[4]["tool_call_id"] == "c2")
    }

    @Test func onlyOpenRouterReplayItemsGoBack() {
        let foreign = ReplayItem(format: .responses, payload: ["type": "reasoning"])
        let message = Message.assistant(AssistantMessage(text: "x", replay: [foreign]))
        guard case .assistant(let assistant) = OpenRouterChatModel.chatMessage(message) else {
            Issue.record("expected an assistant message")
            return
        }
        #expect(assistant.reasoningDetails == nil)
    }
}

struct OpenRouterProviderTests {
    @Test(arguments: [
        ("DeepSeek: DeepSeek V4.1 Flash", "DeepSeek V4.1 Flash"),
        ("Plain Name", "Plain Name"),
        ("Odd: ", "Odd: "),
    ])
    func dropsTheCatalogueAuthorPrefix(name: String, expected: String) {
        #expect(OpenRouterProvider.displayName(name) == expected)
    }

    @Test func pricesArePerMillionTokens() {
        #expect(
            OpenRouterProvider.pricing(prompt: "0.00000027", completion: "0.0000011")
                == .perMillion(input: 0.27, output: 1.1))
        #expect(OpenRouterProvider.pricing(prompt: "0", completion: "0") == .free)
        #expect(OpenRouterProvider.pricing(prompt: "-", completion: "0") == .unknown)
    }

    @Test func isConnectedWithAKeyFromTheEnvironmentOrTheStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let withoutKey = OpenRouterProvider(credentials: CredentialStore(directory: directory, environment: [:]))
        #expect(!withoutKey.isConnected())
        #expect(throws: ProviderError.notConnected(.openRouter)) {
            try withoutKey.chatModel(
                for: ModelEntry(ref: ModelRef(provider: .openRouter, model: "a/b"), name: "B", format: .openRouter))
        }

        let environment = OpenRouterProvider(
            credentials: CredentialStore(directory: directory, environment: ["OPENROUTER_API_KEY": "sk-env"]))
        #expect(environment.isConnected())

        let store = CredentialStore(directory: directory, environment: [:])
        try store.setAPIKey("sk-stored", for: .openRouter)
        #expect(OpenRouterProvider(credentials: store).isConnected())
    }
}
