public import Foundation
import ModelKit
public import SessionKit

/// What the agent loop reports to the user interface.
public enum AgentEvent: Sendable, Equatable {
    /// The agent is about to ask for the next user message.
    case status(StatusLine)
    /// Model, context and usage changed while the agent is busy. This does
    /// not signal readiness or close an active tool tray.
    case metrics(StatusLine)
    /// The agent is waiting for the model's next reply.
    case thinking
    /// The next piece of the model's reasoning, as it streams in.
    case reasoningDelta(String)
    /// The next piece of the model's text, as it streams in.
    case replyDelta(String)
    /// The model started writing a call to the tool `name`; it runs once the
    /// reply is complete (``toolStarted(name:arguments:)``).
    case toolCallWriting(name: String)
    /// The model finished writing text: all of it, the deltas joined.
    case reply(String)
    /// A tool started running, with the raw JSON arguments the model sent.
    case toolStarted(name: String, arguments: String)
    /// The tool finished with `output`, what the model sees; `failed` when
    /// the tool was unknown or threw.
    case toolFinished(name: String, arguments: String, output: String, failed: Bool)
    /// A model call failed: what went wrong and what the user can do about
    /// it. The agent waits for the next message instead of ending.
    case failure(message: String, recovery: String?)
}

/// What the user does at the prompt.
public enum AgentInput: Sendable, Equatable {
    /// A message to add to the conversation.
    case message(String)
    /// Already accepted durably by the UI; consume its identity exactly once.
    case stored(PendingInput)
    /// Start the conversation over: the model forgets it, and the totals go
    /// back to zero.
    case clear
}

/// The agent loop: chat with the user and run the tools the model calls.
///
/// It runs on the main actor, next to the UI it reports to; the model and the
/// tools are awaited, so the interface stays live while they work.
@MainActor
public struct Agent {
    /// Errors from talking to the model.
    public enum InferenceError: LocalizedError {
        case emptyReply
        case duplicateToolCallIDs

        /// What went wrong.
        public var errorDescription: String? {
            switch self {
            case .emptyReply: "The model sent an empty reply."
            case .duplicateToolCallIDs: "The model sent duplicate tool-call IDs. No tools were run."
            }
        }
    }

    let model: @MainActor () -> ActiveModel
    let tools: [ToolDefinition]
    let environment: SessionEnvironment
    let now: () -> Date
    let input: () async -> AgentInput?
    let output: (AgentEvent) -> Void
    let journal: AgentJournal?

    /// Creates an agent.
    ///
    /// - Parameters:
    ///   - model: The model that writes the replies, read before every model
    ///     call: returning another model switches to it, and the
    ///     conversation carries over.
    ///   - tools: The tools the model may call.
    ///   - environment: The machine and project, for the system prompt and
    ///     the status line.
    ///   - now: The clock that dates user messages.
    ///   - journal: Durable history and awaited storage boundaries, when enabled.
    ///   - output: Receives what happens in the conversation, for display.
    ///   - input: Reads what the user does at the prompt, or `nil` to end the session.
    public init(
        model: @escaping @MainActor () -> ActiveModel,
        tools: [ToolDefinition] = [],
        environment: SessionEnvironment,
        now: @escaping () -> Date = Date.init,
        journal: AgentJournal? = nil,
        output: @escaping (AgentEvent) -> Void,
        input: @escaping () async -> AgentInput?,
    ) {
        self.model = model
        self.tools = tools
        self.environment = environment
        self.now = now
        self.output = output
        self.input = input
        self.journal = journal
    }

    /// Runs the conversation until ``input`` returns `nil`. A failed model
    /// call is reported as ``AgentEvent/failure(message:recovery:)`` and the
    /// agent waits for the next message.
    public func run() async throws {
        var state =
            journal.map { ConversationState(active: model(), prompt: systemPrompt, snapshot: $0.snapshot) }
            ?? ConversationState(active: model(), prompt: systemPrompt)
        var savedContext = journal?.snapshot.summary.context
        try await synchronize(model(), state: &state, saved: &savedContext)

        // After tool calls the model gets the results straight away, without
        // waiting for the user.
        var readUserInput = true
        while !Task.isCancelled {
            if readUserInput {
                output(.status(statusLine(state)))
                guard let userInput = await input() else {
                    break
                }
                try await synchronize(model(), state: &state, saved: &savedContext)
                guard try await take(userInput, state: &state) else { continue }
            }

            let active = model()
            try await synchronize(active, state: &state, saved: &savedContext)
            output(.metrics(statusLine(state)))
            try await journal?.append(.inferenceStarted)
            try Task.checkCancellation()
            output(.thinking)
            guard let reply = try await reply(from: active, state: state) else {
                readUserInput = true
                continue
            }
            try await journal?.append(.assistant(SessionAssistant(message: reply.message, usage: reply.usage)))
            state.record(reply)
            if let text = reply.message.text, !text.isEmpty { output(.reply(text)) }
            output(.metrics(statusLine(state)))
            for call in reply.message.toolCalls {
                let result = try await execute(call)
                state.conversation.append(.tool(callID: call.id, name: call.name, content: result))
            }
            readUserInput = reply.message.toolCalls.isEmpty
        }
    }

    /// The system prompt for a model.
    private func systemPrompt(model: ModelDescription) -> String {
        SystemPrompt.render(tools: tools, environment: environment, model: model.name)
    }

    /// The line the panel shows above the prompt.
    private func statusLine(_ state: ConversationState) -> StatusLine {
        StatusLine(
            directory: environment.workingDirectory,
            model: state.description,
            contextTokens: state.contextTokens,
            cost: state.cost,
            usage: state.latestUsage,
        )
    }

    /// The model's next reply, or `nil` after reporting why there is none.
    private func reply(from active: ActiveModel, state: ConversationState) async throws -> ModelReply? {
        do {
            return try await runInference(active: active, state: state)
        } catch {
            if Task.isCancelled || error is CancellationError { throw error }
            let localized = error as? any LocalizedError
            let recovery =
                localized?.recoverySuggestion
                ?? (journal == nil
                    ? nil : "Your full history was kept. Try again, choose a larger model with /model, or start /new.")
            try await journal?.append(
                .failure(
                    SessionFailure(
                        message: error.localizedDescription, recovery: recovery)))
            output(.failure(message: error.localizedDescription, recovery: recovery))
            return nil
        }
    }

    private func runInference(active: ActiveModel, state: ConversationState) async throws -> ModelReply {
        let options = ReplyOptions(reasoningEffort: active.effort, sessionID: state.sessionID)
        let tools = tools.map(\.spec)
        let result = try await active.chatModel.reply(to: state.conversation, tools: tools, options: options) { delta in
            switch delta {
            case .text(let text): output(.replyDelta(text))
            case .reasoning(let text): output(.reasoningDelta(text))
            case .toolCall(let name): output(.toolCallWriting(name: name))
            }
        }

        let message = result.message
        guard message.text?.isEmpty == false || !message.toolCalls.isEmpty else {
            throw InferenceError.emptyReply
        }
        guard Set(message.toolCalls.map(\.id)).count == message.toolCalls.count else {
            throw InferenceError.duplicateToolCallIDs
        }
        return result
    }

    /// Runs a tool call. Failures become the tool's result, so the model can
    /// see what went wrong and try again.
    private func execute(_ call: ToolCall) async throws -> String {
        try Task.checkCancellation()
        try await journal?.append(.toolStarted(call))
        try Task.checkCancellation()
        output(.toolStarted(name: call.name, arguments: call.arguments))
        let start = ContinuousClock.now
        let result = await result(of: call)
        let milliseconds = Int64((ContinuousClock.now - start) / .milliseconds(1))
        try await journal?.append(
            .toolFinished(
                SessionToolResult(
                    call: call, output: result.content, failed: result.failed, durationMilliseconds: milliseconds)))
        output(.toolFinished(name: call.name, arguments: call.arguments, output: result.content, failed: result.failed))
        return result.content
    }

    private func result(of call: ToolCall) async -> (content: String, failed: Bool) {
        guard let tool = tools.first(where: { $0.name == call.name }) else {
            return ("error: tool not found", true)
        }
        do {
            return (try await tool.function(call.arguments), false)
        } catch {
            return ("error: \(error.localizedDescription)", true)
        }
    }
}
