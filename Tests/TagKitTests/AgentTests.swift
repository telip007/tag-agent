import Foundation
import ModelKit
import OpenRouter
import Testing

@testable import TagKit

/// A model that plays back scripted replies and records what it was sent.
/// Reasoning and text stream word by word, then each tool call's name.
final class ScriptedModel: ChatModel {
    var replies: [AssistantMessage]
    var entry = ModelEntry(
        ref: ModelRef(provider: .openRouter, model: "scripted"),
        name: "Scripted Model",
        contextLength: 8_000,
        format: .openRouter,
    )
    var usage: Usage?
    var failure: (any Error)?
    private(set) var conversations: [[Message]] = []
    private(set) var toolNames: [[String]] = []
    private(set) var options: [ReplyOptions] = []

    init(_ replies: [AssistantMessage]) {
        self.replies = replies
    }

    /// The model as the agent sees it.
    var active: ActiveModel {
        ActiveModel(entry: entry, chatModel: self)
    }

    func reply(
        to conversation: [Message],
        tools: [ToolSpec],
        options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) throws -> ModelReply {
        conversations.append(conversation)
        toolNames.append(tools.map(\.name))
        self.options.append(options)
        if let failure {
            self.failure = nil
            throw failure
        }
        let message = replies.isEmpty ? AssistantMessage() : replies.removeFirst()
        for piece in Self.pieces(of: message.reasoning ?? "") {
            onDelta(.reasoning(piece))
        }
        for piece in Self.pieces(of: message.text ?? "") {
            onDelta(.text(piece))
        }
        for call in message.toolCalls {
            onDelta(.toolCall(name: call.name))
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

    func record(_ event: AgentEvent) {
        events.append(event)
    }

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
            model: { model.active },
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
func dialogue(_ conversation: [Message]) -> [Message] {
    conversation.dropFirst().map { message in
        guard case .user(let text) = message,
            let range = text.firstRange(of: "</environment_update>\n\n")
        else {
            return message
        }
        return .user(String(text[range.upperBound...]))
    }
}

func toolCall(_ id: String, _ name: String, _ arguments: String) -> ToolCall {
    ToolCall(id: id, name: name, arguments: arguments)
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
        let model = ScriptedModel([AssistantMessage(text: "Hi!")])
        let terminal = Terminal(["Hello"])
        try await terminal.agent(model: model).run()

        #expect(model.conversations.map(dialogue) == [[.user("Hello")]])
        #expect(model.toolNames == [[]])
        #expect(terminal.events.contains(.reply("Hi!")))
        #expect(terminal.events.contains(.thinking))
        #expect(terminal.statusLines.first == "/work/tag · Scripted Model · ctx 0/8k (0%) · $0.00")
    }

    @Test func streamsReasoningThenTextThenToolNames() async throws {
        let message = AssistantMessage(
            text: "On it.", reasoning: "Need echo.", toolCalls: [toolCall("1", "echo", "{}")])
        let model = ScriptedModel([message, AssistantMessage(text: "Done.")])
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
        let model = ScriptedModel([AssistantMessage(text: "Hi there, you.")])
        let terminal = Terminal(["Hello"])
        try await terminal.agent(model: model).run()

        let reply = terminal.events.drop { $0 != .thinking }.dropFirst().prefix(4)
        let deltas: [AgentEvent] = [.replyDelta("Hi"), .replyDelta(" there,"), .replyDelta(" you.")]
        #expect(Array(reply) == deltas + [.reply("Hi there, you.")])
    }

    @Test func statusLineReportsContextAndCostAfterAReply() async throws {
        let model = ScriptedModel([AssistantMessage(text: "Hi!")])
        model.usage = Usage(inputTokens: 100, outputTokens: 5, cost: 0.0012)
        let terminal = Terminal(["Hello"])
        try await terminal.agent(model: model).run()

        #expect(terminal.statusLines.last == "/work/tag · Scripted Model · ctx 105/8k (1%) · $0.0012")
    }

    @Test func addsEachReplysCostToTheStatusLine() async throws {
        let calls = [toolCall("1", "echo", "{}")]
        let model = ScriptedModel([AssistantMessage(toolCalls: calls), AssistantMessage(text: "Done.")])
        model.usage = Usage(inputTokens: 100, outputTokens: 5, cost: 0.001)
        let terminal = Terminal(["Go"])
        try await terminal.agent(model: model, tools: [echo]).run()

        // Two replies, so the last status line shows the summed cost.
        #expect(terminal.statusLines.last?.hasSuffix("· $0.002") == true)
    }

    @Test func runsToolCallsAndSendsResultsBackWithoutAskingTheUser() async throws {
        let calls = [toolCall("1", "echo", "{}"), toolCall("2", "fail", "{}"), toolCall("3", "missing", "{}")]
        let model = ScriptedModel([AssistantMessage(toolCalls: calls), AssistantMessage(text: "Done.")])
        let terminal = Terminal(["Go"])
        try await terminal.agent(model: model, tools: [echo, failing]).run()

        #expect(model.toolNames == [["echo", "fail"], ["echo", "fail"]])
        #expect(
            model.conversations.last.map(dialogue) == [
                .user("Go"),
                .assistant(AssistantMessage(toolCalls: calls)),
                .tool(callID: "1", name: "echo", content: "echo {}"),
                .tool(callID: "2", name: "fail", content: "error: boom"),
                .tool(callID: "3", name: "missing", content: "error: tool not found"),
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

    @Test func reportsAnEmptyReplyAndWaitsForTheNextMessage() async throws {
        let model = ScriptedModel([AssistantMessage(), AssistantMessage(text: "Back.")])
        let terminal = Terminal(["Hello", "Again"])
        try await terminal.agent(model: model).run()

        let message = Agent.InferenceError.emptyReply.localizedDescription
        #expect(terminal.events.contains(.failure(message: message, recovery: nil)))
        #expect(terminal.events.contains(.reply("Back.")))
        #expect(terminal.statusLines.count == 3)
    }

    @Test func reportsProviderErrorsWithTheirRecovery() async throws {
        let model = ScriptedModel([AssistantMessage(text: "Hi!")])
        let limit = ProviderError.usageLimit(.codex, detail: "", manageURL: URL(string: "https://example.com/usage"))
        model.failure = limit
        let terminal = Terminal(["Hello", "Again"])
        try await terminal.agent(model: model).run()

        let failure = AgentEvent.failure(message: limit.localizedDescription, recovery: limit.recoverySuggestion)
        #expect(terminal.events.contains(failure))
        #expect(limit.recoverySuggestion?.contains("Manage usage: https://example.com/usage") == true)
        #expect(terminal.events.contains(.reply("Hi!")))
    }

    @Test func switchingModelsKeepsTheConversationAndRenamesTheModel() async throws {
        let first = ScriptedModel([AssistantMessage(text: "One.")])
        let second = ScriptedModel([AssistantMessage(text: "Two.")])
        second.entry.ref = ModelRef(provider: .codex, model: "other")
        second.entry.name = "Other Model"
        var active = first.active
        let terminal = Terminal(["a", "b"])
        let agent = Agent(
            model: { active },
            environment: .fake,
            output: { event in
                terminal.record(event)
                if event == .reply("One.") {
                    active = ActiveModel(entry: second.entry, chatModel: second, effort: "high")
                }
            },
            input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() },
        )
        try await agent.run()

        let sent = try #require(second.conversations.first)
        #expect(dialogue(sent).count == 3)
        #expect(sent.first == .system(SystemPrompt.render(tools: [], environment: .fake, model: "Other Model")))
        #expect(second.options.first?.reasoningEffort == "high")
        #expect(second.options.first?.sessionID == first.options.first?.sessionID)
        #expect(terminal.statusLines.last?.contains("Other Model") == true)
    }

    @Test func clearingStartsANewSession() async throws {
        let model = ScriptedModel([AssistantMessage(text: "1"), AssistantMessage(text: "2")])
        let terminal = Terminal(["a", "b"])
        terminal.inputs.insert(.clear, at: 1)
        try await terminal.agent(model: model).run()

        #expect(model.options.count == 2)
        #expect(model.options[0].sessionID != model.options[1].sessionID)
    }

    @Test func startsWithTheSystemPromptAndKeepsItUnchanged() async throws {
        let calls = [toolCall("1", "echo", "{}")]
        let model = ScriptedModel([AssistantMessage(toolCalls: calls), AssistantMessage(text: "Done.")])
        let terminal = Terminal(["Go"])
        try await terminal.agent(model: model, tools: [echo]).run()

        let prompt = SystemPrompt.render(tools: [echo], environment: .fake, model: "Scripted Model")
        #expect(model.conversations.map(\.first) == [.system(prompt), .system(prompt)])
    }

    @Test func datesTheFirstMessageAndMessagesAfterTheDateChanged() async throws {
        let model = ScriptedModel([
            AssistantMessage(text: "1"), AssistantMessage(text: "2"), AssistantMessage(text: "3"),
        ])
        let terminal = Terminal(["a", "b", "c"])
        let day = Date(timeIntervalSince1970: 1_792_000_000)
        terminal.dates = [day, day, day.addingTimeInterval(86_400)]
        try await terminal.agent(model: model).run()

        let users = model.conversations.last?.compactMap { message -> String? in
            guard case .user(let text) = message else { return nil }
            return text
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
        let model = ScriptedModel([AssistantMessage(text: "Hi!"), AssistantMessage(text: "Again!")])
        model.usage = Usage(inputTokens: 100, outputTokens: 5, cost: 0.001)
        let terminal = Terminal(["Hello", "Again"])
        terminal.inputs.insert(.clear, at: 1)
        try await terminal.agent(model: model).run()

        // The second conversation holds the system prompt and the new message.
        #expect(model.conversations.map(dialogue) == [[.user("Hello")], [.user("Again")]])
        // Its first message carries the date again, as in a fresh session.
        let date = UserMessageDater.format(terminal.dates[0])
        let messages = model.conversations.last?.compactMap { message -> String? in
            guard case .user(let text) = message else { return nil }
            return text
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
