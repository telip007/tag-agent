public import Foundation
import OpenRouter

/// What the agent loop reports to the user interface.
public enum AgentEvent: Sendable, Equatable {
    /// The agent is about to ask for the next user message.
    case status(StatusLine)
    /// The agent is waiting for the model's next reply.
    case thinking
    /// The model wrote text.
    case reply(String)
    /// A tool started running, with the raw JSON arguments the model sent.
    case toolStarted(name: String, arguments: String)
    /// The tool finished; `failed` when it was unknown or threw.
    case toolFinished(name: String, arguments: String, failed: Bool)
}

/// The agent loop: chat with the user and run the tools the model calls.
///
/// It runs on the main actor, next to the UI it reports to; the model and the
/// tools are awaited, so the interface stays live while they work.
@MainActor
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
    let workingDirectory: URL
    let getUserMessage: () async -> String?
    let output: (AgentEvent) -> Void

    /// Creates an agent.
    ///
    /// - Parameters:
    ///   - model: The model that writes the replies.
    ///   - tools: The tools the model may call.
    ///   - workingDirectory: The folder shown in the status line.
    ///   - output: Receives what happens in the conversation, for display.
    ///   - getUserMessage: Reads the next user message, or `nil` to end the session.
    public init(
        model: any ChatModel,
        tools: [ToolDefinition] = [],
        workingDirectory: URL,
        output: @escaping (AgentEvent) -> Void,
        getUserMessage: @escaping () async -> String?,
    ) {
        self.model = model
        self.tools = tools
        self.workingDirectory = workingDirectory
        self.output = output
        self.getUserMessage = getUserMessage
    }

    /// Runs the conversation until ``getUserMessage`` returns `nil`.
    public func run() async throws {
        var conversation: [ChatMessage] = []

        // A catalogue call for the status line.
        let modelDescription = await model.modelDescription()

        // After tool calls the model gets the results straight away, without
        // waiting for the user.
        var contextTokens = 0
        var cost = 0.0
        var readUserInput = true
        while true {
            if readUserInput {
                output(
                    .status(
                        StatusLine(
                            directory: workingDirectory,
                            model: modelDescription,
                            contextTokens: contextTokens,
                            cost: cost,
                        )
                    )
                )

                let userInput = await getUserMessage()
                guard let userInput else {
                    break
                }

                conversation.append(.user(userInput))
            }

            output(.thinking)
            let result = try await runInference(conversation: conversation)
            conversation.append(.assistant(result.message))
            if let usage = result.usage {
                contextTokens = usage.totalTokens
                cost += usage.cost ?? 0
            }

            if let reply = result.message.text, !reply.isEmpty {
                output(.reply(reply))
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
    ) async throws -> (message: ChatAssistantMessage, usage: ChatUsage?) {
        let result = try await model.reply(to: conversation, tools: tools.map(\.chatTool))

        guard let message = result.message else {
            throw InferenceError.emptyReply
        }

        return (message, result.usage)
    }

    /// Runs a tool call. Failures become the tool's result, so the model can
    /// see what went wrong and try again.
    private func execute(_ call: ChatToolCall) async -> String {
        let (name, arguments) = (call.function.name, call.function.arguments)
        output(.toolStarted(name: name, arguments: arguments))
        let result = await result(of: call)
        output(.toolFinished(name: name, arguments: arguments, failed: result.failed))
        return result.content
    }

    private func result(of call: ChatToolCall) async -> (content: String, failed: Bool) {
        guard let tool = tools.first(where: { $0.name == call.function.name }) else {
            return ("error: tool not found", true)
        }
        do {
            return (try await tool.function(call.function.arguments), false)
        } catch {
            return ("error: \(error.localizedDescription)", true)
        }
    }
}
