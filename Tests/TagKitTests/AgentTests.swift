import Foundation
import OpenRouter
import Testing

@testable import TagKit

/// A model that plays back scripted replies and records what it was sent.
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

    func reply(to conversation: [ChatMessage], tools: [ChatTool]) throws -> ChatResult {
        conversations.append(conversation)
        toolNames.append(tools.compactMap { $0.value1?.function.name })
        let choices = replies.isEmpty ? [] : [ChatChoice(index: 0, message: replies.removeFirst())]
        return ChatResult(
            choices: choices,
            created: 0,
            id: "result",
            model: "scripted",
            object: .chat_completion,
            usage: usage,
        )
    }
}

/// The user's side of a conversation, plus everything the agent reported.
@MainActor
final class Terminal {
    var inputs: [String]
    private(set) var events: [AgentEvent] = []

    init(_ inputs: [String]) {
        self.inputs = inputs
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
            workingDirectory: URL(filePath: "/work/tag", directoryHint: .isDirectory),
            output: { self.events.append($0) },
            getUserMessage: { self.inputs.isEmpty ? nil : self.inputs.removeFirst() },
        )
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

        #expect(model.conversations == [[.user("Hello")]])
        #expect(model.toolNames == [[]])
        #expect(terminal.events.contains(.reply("Hi!")))
        #expect(terminal.events.contains(.thinking))
        #expect(terminal.statusLines.first == "/work/tag · Scripted Model · ctx 0/8k (0%) · $0.00")
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
            model.conversations.last == [
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
                .toolFinished(name: "echo", arguments: "{}", failed: false),
                .toolStarted(name: "fail", arguments: "{}"),
                .toolFinished(name: "fail", arguments: "{}", failed: true),
                .toolStarted(name: "missing", arguments: "{}"),
                .toolFinished(name: "missing", arguments: "{}", failed: true),
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
}
