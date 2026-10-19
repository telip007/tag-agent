public import Foundation
import ModelKit

/// What the agent loop reports to the user interface.
public enum AgentEvent: Sendable, Equatable {
    /// The agent is about to ask for the next user message.
    case status(StatusLine)
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

        /// What went wrong.
        public var errorDescription: String? {
            "The model sent an empty reply."
        }
    }

    let model: @MainActor () -> ActiveModel
    let tools: [ToolDefinition]
    let environment: SessionEnvironment
    let now: () -> Date
    let input: () async -> AgentInput?
    let output: (AgentEvent) -> Void

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
    ///   - output: Receives what happens in the conversation, for display.
    ///   - input: Reads what the user does at the prompt, or `nil` to end the session.
    public init(
        model: @escaping @MainActor () -> ActiveModel,
        tools: [ToolDefinition] = [],
        environment: SessionEnvironment,
        now: @escaping () -> Date = Date.init,
        output: @escaping (AgentEvent) -> Void,
        input: @escaping () async -> AgentInput?,
    ) {
        self.model = model
        self.tools = tools
        self.environment = environment
        self.now = now
        self.output = output
        self.input = input
    }

    /// Runs the conversation until ``input`` returns `nil`. A failed model
    /// call is reported as ``AgentEvent/failure(message:recovery:)`` and the
    /// agent waits for the next message.
    public func run() async throws {
        var state = ConversationState(active: model(), prompt: systemPrompt)

        // After tool calls the model gets the results straight away, without
        // waiting for the user.
        var readUserInput = true
        while true {
            if readUserInput {
                output(.status(statusLine(state)))
                guard let userInput = await input() else {
                    break
                }
                switch userInput {
                case .clear:
                    state.reset()
                    continue
                case .message(let text):
                    state.conversation.append(.user(state.dater.message(text, at: now())))
                }
            }

            let active = model()
            state.follow(active)
            output(.thinking)
            guard let reply = await reply(from: active, state: state) else {
                readUserInput = true
                continue
            }
            state.record(reply)
            for call in reply.message.toolCalls {
                state.conversation.append(.tool(callID: call.id, name: call.name, content: await execute(call)))
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
        )
    }

    /// The model's next reply, or `nil` after reporting why there is none.
    private func reply(from active: ActiveModel, state: ConversationState) async -> ModelReply? {
        do {
            return try await runInference(active: active, state: state)
        } catch {
            let localized = error as? any LocalizedError
            output(.failure(message: error.localizedDescription, recovery: localized?.recoverySuggestion))
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
        if let reply = message.text, !reply.isEmpty {
            output(.reply(reply))
        }
        return result
    }

    /// Runs a tool call. Failures become the tool's result, so the model can
    /// see what went wrong and try again.
    private func execute(_ call: ToolCall) async -> String {
        output(.toolStarted(name: call.name, arguments: call.arguments))
        let result = await result(of: call)
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

/// What the agent keeps about the conversation between model calls.
struct ConversationState {
    /// The model the conversation was last sent to.
    private(set) var model: ModelRef
    /// Its name and context window, for the status line.
    private(set) var description: ModelDescription
    /// Everything the model is told, the system prompt first.
    var conversation: [Message]
    /// Dates user messages when the day changed.
    var dater = UserMessageDater()
    /// Tokens the context held after the latest reply.
    private(set) var contextTokens = 0
    /// What the conversation has cost so far, in US dollars.
    private(set) var cost = 0.0
    /// The conversation's id for providers that route or cache by session.
    private(set) var sessionID = UUID().uuidString
    private let prompt: (ModelDescription) -> String

    init(active: ActiveModel, prompt: @escaping (ModelDescription) -> String) {
        model = active.entry.ref
        description = active.description
        self.prompt = prompt
        // Rendered once per model: changing it would invalidate the cache.
        conversation = [.system(prompt(active.description))]
    }

    /// Starts over: the system prompt stays; everything the model was told
    /// goes, so the prompt cache prefix does too.
    mutating func reset() {
        conversation = [.system(prompt(description))]
        dater = UserMessageDater()
        contextTokens = 0
        cost = 0
        sessionID = UUID().uuidString
    }

    /// Switches to `active` when it is another model: the system prompt
    /// names the new model and the rest of the conversation carries over.
    mutating func follow(_ active: ActiveModel) {
        guard active.entry.ref != model else {
            return
        }
        model = active.entry.ref
        description = active.description
        conversation[0] = .system(prompt(description))
    }

    /// Adds the reply and its usage.
    mutating func record(_ reply: ModelReply) {
        conversation.append(.assistant(reply.message))
        if let usage = reply.usage {
            contextTokens = usage.totalTokens
            cost += usage.cost ?? 0
        }
    }
}
