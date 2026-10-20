public import Foundation
import ModelKit
public import Observation
public import SessionKit

/// Owns durable session selection and exactly one foreground agent task.
@MainActor
@Observable
public final class SessionController {
    /// The authoritative local store.
    @ObservationIgnored public let store: SQLiteSessionStore
    /// Explicit model selection, shared with the model picker.
    @ObservationIgnored public let selection: ModelSelection
    /// The single transcript/input surface used by the foreground task.
    public let session = ChatSession()
    /// The selected conversation, including read-only inspections.
    public internal(set) var active: SessionSummary?
    /// Unsent input and attachments, scoped to the selected conversation.
    public var draft = SessionDraft()
    /// Accepted inputs restored for explicit review, never automatically dispatched.
    public internal(set) var pendingForReview: [PendingInput] = []
    /// A local context report, never added to model history.
    public internal(set) var contextReport: String?
    /// Why execution is unavailable, when inspecting another workspace or writer.
    public internal(set) var readOnlyReason: String?
    /// A storage failure pauses dispatch until explicit retry.
    public internal(set) var pauseReason: String?
    /// A selection/save transition is awaiting completion.
    public internal(set) var isTransitioning = false

    @ObservationIgnored var environment: SessionEnvironment
    @ObservationIgnored let tools: [ToolDefinition]
    @ObservationIgnored let probe: @MainActor (URL) async -> SessionEnvironment
    @ObservationIgnored var ownership: SessionOwnership?
    @ObservationIgnored var snapshot: SessionSnapshot?
    @ObservationIgnored var agentTask: Task<Void, Never>?
    @ObservationIgnored var runEnd: CheckedContinuation<Void, Never>?
    @ObservationIgnored var isRunning = false
    @ObservationIgnored var modelSavePending = false
    @ObservationIgnored var isClosed = false

    /// Creates a controller without opening or running a conversation.
    public init(
        store: SQLiteSessionStore, selection: ModelSelection, environment: SessionEnvironment,
        tools: [ToolDefinition],
        probe: (@MainActor (URL) async -> SessionEnvironment)? = nil
    ) {
        self.store = store
        self.selection = selection
        self.environment = environment
        self.tools = tools
        self.probe = probe ?? { await SessionEnvironment.probe(workingDirectory: $0) }
    }

    /// Canonical directory identity resolves symlinks but preserves distinct worktrees.
    public var workspace: String { environment.workingDirectory.standardizedFileURL.resolvingSymlinksInPath().path }
    /// Inspection never gains execution rights by selecting a model.
    public var isReadOnly: Bool { readOnlyReason != nil }
    /// Saved model could not be restored; the user must choose one explicitly.
    public var needsModel: Bool { selection.current == nil }
    /// Switching waits for a ready input boundary, without cancelling active effects.
    public var isBusy: Bool {
        isTransitioning || (agentTask != nil && pauseReason == nil && !session.isWaitingForInput)
    }

    /// Startup behavior; opening never submits a request or drains saved input.
    public enum Startup: Sendable {
        case continueLast
        case new
        case resume(String)
    }

    /// Selects the requested conversation, or creates the first one for this workspace.
    public func open(_ startup: Startup) async throws {
        switch startup {
        case .continueLast:
            if let last = try await store.lastSession(workspace: workspace) {
                try await switchTo(last.id)
            } else {
                try await newSession()
            }
        case .new: try await newSession()
        case .resume(let prefix): try await switchTo(store.resolve(prefix).id)
        }
    }

    /// Keeps the UI lifecycle alive while controller-owned agent tasks may change.
    public func run() async {
        guard !isRunning, !isClosed else { return }
        isRunning = true
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                runEnd = continuation
                startAgent()
            }
        } onCancel: {
            Task { @MainActor in await self.shutdown() }
        }
    }

    func startAgent() {
        guard isRunning, !isClosed, agentTask == nil, !isReadOnly, pauseReason == nil,
            let snapshot, let first = selection.current
        else { return }
        let id = snapshot.summary.id
        let agent = Agent(
            model: { [selection] in selection.current ?? first }, tools: tools, environment: environment,
            journal: AgentJournal(store: store, snapshot: snapshot),
            context: NativeContext(store: store, sessionID: id, workingDirectory: environment.workingDirectory),
            output: { [weak self] in self?.receive($0, sessionID: id) }, input: session.nextMessage)
        agentTask = Task { [weak self] in
            do { try await agent.run() } catch { self?.handleFailure(error, sessionID: id) }
        }
    }

    func stopAgent() async {
        session.stopDispatching()
        let task = agentTask
        task?.cancel()
        await task?.value
        agentTask = nil
    }
}

/// Local feedback for operations which cannot safely proceed.
public enum SessionControlError: LocalizedError {
    case busy
    case readOnly(String)
    case chooseModel
    case paused
    case emptyInput

    /// Useful next action without a paid request.
    public var errorDescription: String? {
        switch self {
        case .busy: "Wait for the current turn before switching sessions."
        case .readOnly(let reason): reason
        case .chooseModel: "Choose a model with /model before continuing."
        case .paused: "Session saving is paused. Use /retry after fixing storage."
        case .emptyInput: "Type a message before sending."
        }
    }
}
