import Foundation
public import Observation

/// The state the workspace shows, fed by the ``Agent``'s events, and the
/// hand-off of submitted messages back to the agent.
///
/// The agent reads input with ``nextMessage()``. Messages submitted while it
/// is busy wait in a queue, so the user can type ahead. `/clear` starts the
/// conversation over instead of sending anything: the transcript empties and
/// the agent drops what the model was told.
@MainActor
@Observable
public final class ChatSession {
    /// Tool calls quicker than this don't show their duration.
    static let noticeableDuration = Duration.seconds(1)

    /// The conversation so far, oldest first, each block observed on its own:
    /// a reply growing changes its block, not the list, so the workspace
    /// redraws that block alone.
    public private(set) var blocks: [LiveBlock] = []
    /// Blocks the user expanded (tool trays, long edits), by id.
    public private(set) var expanded: Set<Int> = []
    /// The latest status line: model, context and cost.
    public private(set) var status: StatusLine?
    /// Files changed this session, in the order first touched.
    public private(set) var files: [FileChange] = []
    /// What the agent is busy with (`"thinking"`, a tool call), or `nil`.
    public private(set) var activity: String?
    /// When the current ``activity`` started.
    public private(set) var activityStart: ContinuousClock.Instant?
    /// When the session started, for its running time.
    public let start: ContinuousClock.Instant
    /// Messages submitted while the agent was busy, oldest first.
    public private(set) var queued: [String] = []
    /// Every message sent, oldest first, for recalling with the arrow keys.
    public private(set) var history: [String] = []

    /// Whether the agent is waiting for the user's next message.
    public var isWaitingForInput: Bool {
        pendingMessage != nil
    }

    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    private var pendingMessage: CheckedContinuation<String?, Never>?
    @ObservationIgnored private var isEnded = false
    /// The tray collecting the current run of tool calls, if one is open.
    @ObservationIgnored private var openTray: Int?
    /// The reply block the model is still writing, if any.
    @ObservationIgnored private var openReply: Int?
    /// The reasoning block the model is still writing, and when it started.
    @ObservationIgnored private var openReasoning: (block: Int, start: ContinuousClock.Instant)?

    /// Creates an empty session.
    ///
    /// - Parameter now: The clock that times the session and tool calls.
    public init(now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
        start = now()
    }

    /// The time since the session started.
    public var elapsed: Duration {
        now() - start
    }

    /// Updates the state for an event from the agent loop.
    public func handle(_ event: AgentEvent) {
        switch event {
        case .status(let line):
            status = line
            openTray = nil
            finishReasoning()
            setActivity(nil)
        case .thinking:
            setActivity("thinking")
        case .reasoningDelta(let text):
            streamReasoning(text)
        case .replyDelta(let text):
            finishReasoning()
            streamReply(text)
        case .reply(let text):
            finishReasoning()
            finishReply(text)
        case .toolCallWriting(let name):
            finishReasoning()
            setActivity("writing \(name)")
        case .toolStarted(let name, let arguments):
            finishReasoning()
            startTool(name: name, summary: ToolSummary.summarize(arguments))
            setActivity("\(name)  \(ToolSummary.summarize(arguments))")
        case .toolFinished(let name, let arguments, let output, let failed):
            finishTool(output: output, failed: failed)
            if name == "edit_file", !failed, let edit = FileEdit.from(arguments: arguments) {
                record(edit)
            }
            setActivity(nil)
        case .failure(let message, let recovery):
            reportFailure(message, recovery: recovery)
        }
    }

    /// Expands a collapsed block or collapses an expanded one.
    public func toggle(_ id: Int) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    /// Waits for what the user does next, taking queued lines first. Returns
    /// `nil` once the session has ended or the waiting task is cancelled.
    public func nextMessage() async -> AgentInput? {
        if !queued.isEmpty {
            return take(queued.removeFirst())
        }
        guard !isEnded else {
            return nil
        }
        let line = await withTaskCancellationHandler {
            await withCheckedContinuation { pendingMessage = $0 }
        } onCancel: {
            Task { @MainActor in self.end() }
        }
        return line.map(take)
    }

    /// Hands `text` to the agent, or queues it while the agent is busy.
    ///
    /// - Returns: Whether the message was taken: `false` when it is blank.
    @discardableResult
    public func submit(_ text: String) -> Bool {
        guard text.contains(where: { !$0.isWhitespace }) else {
            return false
        }
        // A command runs the conversation rather than joining it, so ↑
        // won't recall it as a message.
        if !isClearCommand(text) {
            history.append(text)
        }
        guard let pendingMessage else {
            queued.append(text)
            return true
        }
        self.pendingMessage = nil
        pendingMessage.resume(returning: text)
        return true
    }

    /// Ends the session: the current and every later ``nextMessage()``
    /// returns `nil` once the queue is empty.
    public func end() {
        isEnded = true
        pendingMessage?.resume(returning: nil)
        pendingMessage = nil
    }

    /// Takes a line the user entered: the clear command, or a message that
    /// joins the transcript.
    private func take(_ line: String) -> AgentInput {
        if isClearCommand(line) {
            clear()
            return .clear
        }
        openTray = nil
        append(.user(line))
        return .message(line)
    }

    /// Empties the transcript: the agent is told to forget the conversation,
    /// so nothing here may keep pointing into the old one. The files changed
    /// and the session's run time stay, they aren't the conversation's.
    private func clear() {
        blocks = []
        expanded = []
        openTray = nil
        openReply = nil
        openReasoning = nil
    }

    /// Grows the reasoning being written, or starts it.
    private func streamReasoning(_ text: String) {
        if let openReasoning, case .reasoning(var reasoning) = blocks[openReasoning.block].content {
            reasoning.text += text
            blocks[openReasoning.block].content = .reasoning(reasoning)
        } else {
            openTray = nil
            openReasoning = (blocks.count, now())
            append(.reasoning(Reasoning(text: text)))
        }
    }

    /// Records how long the model reasoned, once it moves on.
    private func finishReasoning() {
        guard let openReasoning, case .reasoning(var reasoning) = blocks[openReasoning.block].content else {
            return
        }
        reasoning.duration = now() - openReasoning.start
        blocks[openReasoning.block].content = .reasoning(reasoning)
        self.openReasoning = nil
    }

    /// Grows the reply being written, or starts one.
    private func streamReply(_ text: String) {
        if let openReply, case .reply(let written) = blocks[openReply].content {
            blocks[openReply].content = .reply(written + text)
        } else {
            openTray = nil
            openReply = blocks.count
            append(.reply(text))
            setActivity("writing")
        }
    }

    /// Settles the reply on its full text; a reply that wasn't streamed
    /// appears whole.
    private func finishReply(_ text: String) {
        if let openReply {
            blocks[openReply].content = .reply(text)
        } else {
            openTray = nil
            append(.reply(text))
        }
        openReply = nil
    }

    private func startTool(name: String, summary: String) {
        let run = ToolRun(name: name, summary: summary, state: .running, output: "")
        if let openTray, case .tools(let runs) = blocks[openTray].content {
            blocks[openTray].content = .tools(runs + [run])
        } else {
            openTray = blocks.count
            append(.tools([run]))
        }
    }

    private func finishTool(output: String, failed: Bool) {
        guard let openTray, case .tools(var runs) = blocks[openTray].content, !runs.isEmpty else {
            return
        }
        let last = runs.count - 1
        runs[last].state = failed ? .failed : .succeeded
        runs[last].output = output
        runs[last].duration = activityStart.map { now() - $0 }
        blocks[openTray].content = .tools(runs)
    }

    private func record(_ edit: FileEdit) {
        openTray = nil
        append(.edit(edit))
        if let index = files.firstIndex(where: { $0.path == edit.path }) {
            files[index].added += edit.added
            files[index].removed += edit.removed
        } else {
            files.append(FileChange(path: edit.path, added: edit.added, removed: edit.removed))
        }
    }

    private func setActivity(_ text: String?) {
        activity = text
        activityStart = text == nil ? nil : now()
    }

    private func append(_ content: TranscriptBlock.Content) {
        blocks.append(LiveBlock(id: blocks.count, content: content))
    }

    /// `0.4s`, `12.3s`, `2m 05s`.
    static func seconds(_ duration: Duration) -> String {
        let tenths = Int(duration / .milliseconds(100))
        guard tenths >= 600 else {
            return "\(tenths / 10).\(tenths % 10)s"
        }
        let seconds = tenths / 10
        let remainder = seconds % 60
        return "\(seconds / 60)m " + (remainder < 10 ? "0" : "") + "\(remainder)s"
    }
}

extension ChatSession {
    /// Shows a failed model call in the transcript, with what to do next.
    private func reportFailure(_ message: String, recovery: String?) {
        finishReasoning()
        openReply = nil
        openTray = nil
        append(.failure(message: message, recovery: recovery))
        setActivity(nil)
    }

    /// The conversation so far, oldest first, as values.
    public var transcript: [TranscriptBlock] {
        blocks.map { TranscriptBlock(id: $0.id, content: $0.content) }
    }
}

/// One block of the transcript as the session holds it, observable by
/// itself so that a change to one block redraws only that block.
@MainActor
@Observable
public final class LiveBlock: Identifiable {
    /// The block's position in the transcript.
    public let id: Int
    /// What the block shows.
    public fileprivate(set) var content: TranscriptBlock.Content

    init(id: Int, content: TranscriptBlock.Content) {
        self.id = id
        self.content = content
    }
}

/// Lines that run the conversation rather than joining it, typed at the
/// prompt after a `/`.
private let clearCommand = "/clear"

/// Whether `line` is ``clearCommand``, ignoring whitespace around it.
private func isClearCommand(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces) == clearCommand
}
