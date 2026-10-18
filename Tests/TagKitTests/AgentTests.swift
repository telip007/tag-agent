import Foundation
import OpenRouter
import Testing

@testable import TagKit

/// A model that plays back scripted replies and records what it was sent.
/// Reasoning and text stream word by word, then each tool call's name.
final class ScriptedModel: ChatModel {
    var replies: [ChatAssistantMessage]
    var description = ModelDescription(name: "Scripted Model", contextLength: 8_000)
    var usage: ChatUsage?
    private(set) var conversations: [[ChatMessage]] = []
    private(set) var toolNames: [[String]] = []

    init(_ replies: [ChatAssistantMessage]) {
        self.replies = replies
    }

    func modelDescription() -> ModelDescription {
        description
    }

    func reply(
        to conversation: [ChatMessage],
        tools: [ChatTool],
        onDelta: (ReplyDelta) -> Void,
    ) throws -> ModelReply {
        conversations.append(conversation)
        toolNames.append(tools.compactMap { $0.value1?.function.name })
        let message = replies.isEmpty ? ChatAssistantMessage(text: nil, toolCalls: nil) : replies.removeFirst()
        for piece in Self.pieces(of: message.reasoning ?? "") {
            onDelta(.reasoning(piece))
        }
        for piece in Self.pieces(of: message.text ?? "") {
            onDelta(.text(piece))
        }
        for call in message.toolCalls ?? [] {
            onDelta(.toolCall(name: call.function.name))
        }
        return ModelReply(message: message, usage: usage)
    }

    /// `"Hi there"` streams as `"Hi "`, `"there"`.
    static func pieces(of text: String) -> [String] {
        text.split(separator: " ", omittingEmptySubsequences: false).enumerated().map { index, word in
            index == 0 ? String(word) : " " + word
        }
        .filter { !$0.isEmpty }
    }
}

/// The user's side of a conversation, plus everything the agent reported.
@MainActor
final class Terminal {
    var inputs: [AgentInput]
    /// What the agent's clock reads, one entry per user message; the last
    /// entry repeats.
    var dates = [Date(timeIntervalSince1970: 1_792_000_000)]
    private(set) var events: [AgentEvent] = []

    init(_ inputs: [String]) {
        self.inputs = inputs.map(AgentInput.message)
    }

    /// The status lines shown, in order.
    var statusLines: [String] {
        events.compactMap { event in
            guard case .status(let line) = event else { return nil }
            return line.text
        }
    }

    func agent(model: ScriptedModel, tools: [ToolDefinition] = []) -> Agent {
        Agent(
            model: model,
            tools: tools,
            environment: .fake,
            now: { self.dates.count > 1 ? self.dates.removeFirst() : self.dates[0] },
            output: { self.events.append($0) },
            input: { self.inputs.isEmpty ? nil : self.inputs.removeFirst() },
        )
    }
}

extension SessionEnvironment {
    static let fake = SessionEnvironment(
        workingDirectory: URL(filePath: "/work/tag", directoryHint: .isDirectory),
        operatingSystem: "macOS 26.0.0",
        architecture: "arm64",
        isMacOS: true,
        shell: "bash 3.2.57(1)-release",
        isGitRepository: true,
    )
}

/// The conversation a model was sent, without the system prompt and with
/// the date notes stripped from user messages.
func dialogue(_ conversation: [ChatMessage]) -> [ChatMessage] {
    conversation.dropFirst().map { message in
        guard case .user(let user) = message, let text = user.content.value1,
            let range = text.firstRange(of: "</environment_update>\n\n")
        else {
            return message
        }
        return .user(String(text[range.upperBound...]))
    }
}

func toolCall(_ id: String, _ name: String, _ arguments: String) -> ChatToolCall {
    ChatToolCall(function: .init(arguments: arguments, name: name), id: id, _type: .function)
}

extension AgentEvent {
    var isToolEvent: Bool {
        switch self {
        case .toolStarted, .toolFinished: true
        default: false
        }
    }
}

let echo = ToolDefinition(name: "echo", description: "Echo the input", parameters: ["type": "object"]) { "echo \($0)" }
let failing = ToolDefinition(name: "fail", description: "Always fails", parameters: ["type": "object"]) { _ in
    throw ToolError("boom")
}

@MainActor
struct AgentTests {
    @Test func chatsUntilInputEnds() async throws {
        let model = ScriptedModel([.init(text: "Hi!", toolCalls: nil)])
        let terminal = Terminal(["Hello"])
        try await terminal.agent(model: model).run()

        #expect(model.conversations.map(dialogue) == [[.user("Hello")]])
        #expect(model.toolNames == [[]])
        #expect(terminal.events.contains(.reply("Hi!")))
        #expect(terminal.events.contains(.thinking))
        #expect(terminal.statusLines.first == "/work/tag · Scripted Model · ctx 0/8k (0%) · $0.00")
    }

    @Test func streamsReasoningThenTextThenToolNames() async throws {
        var message = ChatAssistantMessage(text: "On it.", toolCalls: [toolCall("1", "echo", "{}")])
        message.reasoning = "Need echo."
        let model = ScriptedModel([message, .init(text: "Done.", toolCalls: nil)])
        let terminal = Terminal(["Go"])
        try await terminal.agent(model: model, tools: [echo]).run()

        let streamed = terminal.events.drop { $0 != .thinking }.dropFirst().prefix(6)
        let expected: [AgentEvent] = [
            .reasoningDelta("Need"), .reasoningDelta(" echo."), .replyDelta("On"), .replyDelta(" it."),
            .toolCallWriting(name: "echo"), .reply("On it."),
        ]
        #expect(Array(streamed) == expected)
    }

    @Test func streamsTheReplyBeforeReportingAllOfIt() async throws {
        let model = ScriptedModel([.init(text: "Hi there, you.", toolCalls: nil)])
        let terminal = Terminal(["Hello"])
        try await terminal.agent(model: model).run()

        let reply = terminal.events.drop { $0 != .thinking }.dropFirst().prefix(4)
        let deltas: [AgentEvent] = [.replyDelta("Hi"), .replyDelta(" there,"), .replyDelta(" you.")]
        #expect(Array(reply) == deltas + [.reply("Hi there, you.")])
    }

    @Test func statusLineReportsContextAndCostAfterAReply() async throws {
        let model = ScriptedModel([.init(text: "Hi!", toolCalls: nil)])
        model.usage = ChatUsage(completionTokens: 5, cost: 0.0012, promptTokens: 100, totalTokens: 105)
        let terminal = Terminal(["Hello"])
        try await terminal.agent(model: model).run()

        #expect(terminal.statusLines.last == "/work/tag · Scripted Model · ctx 105/8k (1%) · $0.0012")
    }

    @Test func addsEachReplysCostToTheStatusLine() async throws {
        let calls = [toolCall("1", "echo", "{}")]
        let model = ScriptedModel([.init(text: nil, toolCalls: calls), .init(text: "Done.", toolCalls: nil)])
        model.usage = ChatUsage(completionTokens: 5, cost: 0.001, promptTokens: 100, totalTokens: 105)
        let terminal = Terminal(["Go"])
        try await terminal.agent(model: model, tools: [echo]).run()

        // Two replies, so the last status line shows the summed cost.
        #expect(terminal.statusLines.last?.hasSuffix("· $0.002") == true)
    }

    @Test func runsToolCallsAndSendsResultsBackWithoutAskingTheUser() async throws {
        let calls = [toolCall("1", "echo", "{}"), toolCall("2", "fail", "{}"), toolCall("3", "missing", "{}")]
        let model = ScriptedModel([.init(text: nil, toolCalls: calls), .init(text: "Done.", toolCalls: nil)])
        let terminal = Terminal(["Go"])
        try await terminal.agent(model: model, tools: [echo, failing]).run()

        #expect(model.toolNames == [["echo", "fail"], ["echo", "fail"]])
        #expect(
            model.conversations.last.map(dialogue) == [
                .user("Go"),
                .assistant(.init(text: nil, toolCalls: calls)),
                .tool(callID: "1", content: "echo {}"),
                .tool(callID: "2", content: "error: boom"),
                .tool(callID: "3", content: "error: tool not found"),
            ]
        )
        #expect(
            terminal.events.filter(\.isToolEvent) == [
                .toolStarted(name: "echo", arguments: "{}"),
                .toolFinished(name: "echo", arguments: "{}", output: "echo {}", failed: false),
                .toolStarted(name: "fail", arguments: "{}"),
                .toolFinished(name: "fail", arguments: "{}", output: "error: boom", failed: true),
                .toolStarted(name: "missing", arguments: "{}"),
                .toolFinished(name: "missing", arguments: "{}", output: "error: tool not found", failed: true),
            ]
        )
        // The user was asked once at the start and once after "Done.".
        #expect(terminal.statusLines.count == 2)
    }

    @Test func throwsWhenTheModelReturnsNoChoices() async {
        let terminal = Terminal(["Hello"])
        await #expect(throws: Agent.InferenceError.emptyReply) {
            try await terminal.agent(model: ScriptedModel([])).run()
        }
    }

    @Test func startsWithTheSystemPromptAndKeepsItUnchanged() async throws {
        let calls = [toolCall("1", "echo", "{}")]
        let model = ScriptedModel([.init(text: nil, toolCalls: calls), .init(text: "Done.", toolCalls: nil)])
        let terminal = Terminal(["Go"])
        try await terminal.agent(model: model, tools: [echo]).run()

        let prompt = SystemPrompt.render(tools: [echo], environment: .fake, model: "Scripted Model")
        #expect(model.conversations.map(\.first) == [.system(prompt), .system(prompt)])
    }

    @Test func datesTheFirstMessageAndMessagesAfterTheDateChanged() async throws {
        let model = ScriptedModel([
            .init(text: "1", toolCalls: nil), .init(text: "2", toolCalls: nil), .init(text: "3", toolCalls: nil),
        ])
        let terminal = Terminal(["a", "b", "c"])
        let day = Date(timeIntervalSince1970: 1_792_000_000)
        terminal.dates = [day, day, day.addingTimeInterval(86_400)]
        try await terminal.agent(model: model).run()

        let users = model.conversations.last?.compactMap { message -> String? in
            guard case .user(let user) = message else { return nil }
            return user.content.value1
        }
        let (first, next) = (UserMessageDater.format(day), UserMessageDater.format(day.addingTimeInterval(86_400)))
        #expect(
            users == [
                "<environment_update>date: \(first)</environment_update>\n\na",
                "b",
                "<environment_update>date: \(next)</environment_update>\n\nc",
            ]
        )
    }

    @Test func clearingDropsTheConversationAndTheTotals() async throws {
        let model = ScriptedModel([.init(text: "Hi!", toolCalls: nil), .init(text: "Again!", toolCalls: nil)])
        model.usage = ChatUsage(completionTokens: 5, cost: 0.001, promptTokens: 100, totalTokens: 105)
        let terminal = Terminal(["Hello", "Again"])
        terminal.inputs.insert(.clear, at: 1)
        try await terminal.agent(model: model).run()

        // The second conversation holds the system prompt and the new message.
        #expect(model.conversations.map(dialogue) == [[.user("Hello")], [.user("Again")]])
        // Its first message carries the date again, as in a fresh session.
        let date = UserMessageDater.format(terminal.dates[0])
        let messages = model.conversations.last?.compactMap { message -> String? in
            guard case .user(let user) = message else { return nil }
            return user.content.value1
        }
        #expect(messages == ["<environment_update>date: \(date)</environment_update>\n\nAgain"])
        // The user is asked again, with the context and the cost back to zero:
        // the last line costs what one reply costs, not two.
        #expect(
            terminal.statusLines == [
                "/work/tag · Scripted Model · ctx 0/8k (0%) · $0.00",
                "/work/tag · Scripted Model · ctx 105/8k (1%) · $0.001",
                "/work/tag · Scripted Model · ctx 0/8k (0%) · $0.00",
                "/work/tag · Scripted Model · ctx 105/8k (1%) · $0.001",
            ]
        )
    }
}

struct ReplyDeltaTests {
    private func chunk(_ delta: String) throws -> ChatStreamChunk {
        let json = """
            {"id":"g","object":"chat.completion.chunk","created":0,"model":"m",\
            "choices":[{"index":0,"delta":\(delta),"finish_reason":null}]}
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
}
