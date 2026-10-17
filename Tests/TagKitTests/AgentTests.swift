import Foundation
import OpenRouter
import Testing

@testable import TagKit

/// A model that plays back scripted replies and records what it was sent.
final class ScriptedModel: ChatModel {
    var replies: [ChatAssistantMessage]
    private(set) var conversations: [[ChatMessage]] = []
    private(set) var toolNames: [[String]] = []

    init(_ replies: [ChatAssistantMessage]) {
        self.replies = replies
    }

    func reply(to conversation: [ChatMessage], tools: [ChatTool]) throws -> ChatResult {
        conversations.append(conversation)
        toolNames.append(tools.compactMap { $0.value1?.function.name })
        let choices = replies.isEmpty ? [] : [ChatChoice(index: 0, message: replies.removeFirst())]
        return ChatResult(choices: choices, created: 0, id: "result", model: "scripted", object: .chat_completion)
    }
}

/// The user's side of a conversation, plus everything the agent printed.
final class Terminal {
    var inputs: [String]
    private(set) var printed = ""

    init(_ inputs: [String]) {
        self.inputs = inputs
    }

    func agent(model: ScriptedModel, tools: [ToolDefinition] = []) -> Agent {
        Agent(
            model: model,
            tools: tools,
            output: { self.printed += $0 },
            getUserMessage: { self.inputs.isEmpty ? nil : self.inputs.removeFirst() },
        )
    }
}

func toolCall(_ id: String, _ name: String, _ arguments: String) -> ChatToolCall {
    ChatToolCall(function: .init(arguments: arguments, name: name), id: id, _type: .function)
}

let echo = ToolDefinition(name: "echo", description: "Echo the input", parameters: ["type": "object"]) { "echo \($0)" }
let failing = ToolDefinition(name: "fail", description: "Always fails", parameters: ["type": "object"]) { _ in
    throw ToolError("boom")
}

struct AgentTests {
    @Test func chatsUntilInputEnds() async throws {
        let model = ScriptedModel([.init(text: "Hi!", toolCalls: nil)])
        let terminal = Terminal(["Hello"])
        try await terminal.agent(model: model).run()

        #expect(model.conversations == [[.user("Hello")]])
        #expect(model.toolNames == [[]])
        #expect(terminal.printed.contains("Agent\u{1B}[0m: Hi!\n"))
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
        #expect(terminal.printed.contains("tool\u{1B}[0m: echo({})\n"))
        // The user was asked once at the start and once after "Done.".
        #expect(terminal.printed.components(separatedBy: "You").count - 1 == 2)
    }

    @Test func throwsWhenTheModelReturnsNoChoices() async {
        let terminal = Terminal(["Hello"])
        await #expect(throws: Agent.InferenceError.emptyReply) {
            try await terminal.agent(model: ScriptedModel([])).run()
        }
    }
}
