import Foundation
import OpenRouter

/// The agent loop: chat with the user and run the tools the model calls.
public struct Agent {
    /// Errors from ``run()``.
    public enum AgentRunError: Error {
        case unexpected
    }

    /// Errors from talking to the model.
    public enum InferenceError: Error {
        case emptyReply
    }

    let model: any ChatModel
    let tools: [ToolDefinition]
    let getUserMessage: () -> String?
    let output: (String) -> Void

    /// Creates an agent.
    ///
    /// - Parameters:
    ///   - model: The model that writes the replies.
    ///   - tools: The tools the model may call.
    ///   - output: Where the conversation is printed. Defaults to standard output.
    ///   - getUserMessage: Reads the next user message, or `nil` to end the session.
    public init(
        model: any ChatModel,
        tools: [ToolDefinition] = [],
        output: @escaping (String) -> Void = { print($0, terminator: "") },
        getUserMessage: @escaping () -> String?,
    ) {
        self.model = model
        self.tools = tools
        self.output = output
        self.getUserMessage = getUserMessage
    }

    /// Runs the conversation until ``getUserMessage`` returns `nil`.
    public func run() async throws {
        var conversation: [ChatMessage] = []

        output("Chat with Tag Agent (use 'ctrl-c' to quit)\n")

        // After tool calls the model gets the results straight away, without
        // waiting for the user.
        var readUserInput = true
        while true {
            if readUserInput {
                output("\u{1B}[94mYou\u{1B}[0m: ")

                let userInput = getUserMessage()
                guard let userInput else {
                    break
                }

                conversation.append(.user(userInput))
            }

            let result = try await runInference(conversation: conversation)
            conversation.append(.assistant(result.message))

            if let reply = result.message.text, !reply.isEmpty {
                output("\u{1B}[93mAgent\u{1B}[0m: \(reply)\n")
            }

            let toolCalls = result.message.toolCalls ?? []
            for call in toolCalls {
                conversation.append(.tool(callID: call.id, content: await execute(call)))
            }
            readUserInput = toolCalls.isEmpty
        }
    }

    private func runInference(
        conversation: [ChatMessage]
    ) async throws -> (message: ChatAssistantMessage, finishReason: String?) {
        let result = try await model.reply(to: conversation, tools: tools.map(\.chatTool))

        guard let message = result.message else {
            throw InferenceError.emptyReply
        }

        return (message, result.finishReason)
    }

    /// Runs a tool call. Failures become the tool's result, so the model can
    /// see what went wrong and try again.
    private func execute(_ call: ChatToolCall) async -> String {
        output("\u{1B}[92mtool\u{1B}[0m: \(call.function.name)(\(call.function.arguments))\n")

        guard let tool = tools.first(where: { $0.name == call.function.name }) else {
            return "error: tool not found"
        }
        do {
            return try await tool.function(call.function.arguments)
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }
}
