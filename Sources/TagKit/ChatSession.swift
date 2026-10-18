public import Observation

/// The state the workspace shows, fed by the ``Agent``'s events, and the
/// hand-off of submitted messages back to the agent.
///
/// The agent reads input with ``nextMessage()``. Messages submitted while it
/// is busy wait in a queue, so the user can type ahead.
@MainActor
@Observable
public final class ChatSession {
    /// Tool calls quicker than this don't show their duration.
    static let noticeableDuration = Duration.seconds(1)

    /// The conversation so far, oldest first.
    public private(set) var transcript: [TranscriptBlock] = []
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

    /// Waits for the user's next message, taking queued ones first. Returns
    /// `nil` once the session has ended or the waiting task is cancelled.
    public func nextMessage() async -> String? {
        if !queued.isEmpty {
            return send(queued.removeFirst())
        }
        guard !isEnded else {
            return nil
        }
        let message = await withTaskCancellationHandler {
            await withCheckedContinuation { pendingMessage = $0 }
        } onCancel: {
            Task { @MainActor in self.end() }
        }
        return message.map(send)
    }

    /// Hands `text` to the agent, or queues it while the agent is busy.
    ///
    /// - Returns: Whether the message was taken: `false` when it is blank.
    @discardableResult
    public func submit(_ text: String) -> Bool {
        guard text.contains(where: { !$0.isWhitespace }) else {
            return false
        }
        history.append(text)
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

    /// Records `text` as sent.
    private func send(_ text: String) -> String {
        openTray = nil
        append(.user(text))
        return text
    }

    /// Grows the reasoning being written, or starts it.
    private func streamReasoning(_ text: String) {
        if let openReasoning, case .reasoning(var reasoning) = transcript[openReasoning.block].content {
            reasoning.text += text
            transcript[openReasoning.block].content = .reasoning(reasoning)
        } else {
            openTray = nil
            openReasoning = (transcript.count, now())
            append(.reasoning(Reasoning(text: text)))
        }
    }

    /// Records how long the model reasoned, once it moves on.
    private func finishReasoning() {
        guard let openReasoning, case .reasoning(var reasoning) = transcript[openReasoning.block].content else {
            return
        }
        reasoning.duration = now() - openReasoning.start
        transcript[openReasoning.block].content = .reasoning(reasoning)
        self.openReasoning = nil
    }

    /// Grows the reply being written, or starts one.
    private func streamReply(_ text: String) {
        if let openReply, case .reply(let written) = transcript[openReply].content {
            transcript[openReply].content = .reply(written + text)
        } else {
            openTray = nil
            openReply = transcript.count
            append(.reply(text))
            setActivity("writing")
        }
    }

    /// Settles the reply on its full text; a reply that wasn't streamed
    /// appears whole.
    private func finishReply(_ text: String) {
        if let openReply {
            transcript[openReply].content = .reply(text)
        } else {
            openTray = nil
            append(.reply(text))
        }
        openReply = nil
    }

    private func startTool(name: String, summary: String) {
        let run = ToolRun(name: name, summary: summary, state: .running, output: "")
        if let openTray, case .tools(let runs) = transcript[openTray].content {
            transcript[openTray].content = .tools(runs + [run])
        } else {
            openTray = transcript.count
            append(.tools([run]))
        }
    }

    private func finishTool(output: String, failed: Bool) {
        guard let openTray, case .tools(var runs) = transcript[openTray].content, !runs.isEmpty else {
            return
        }
        let last = runs.count - 1
        runs[last].state = failed ? .failed : .succeeded
        runs[last].output = output
        runs[last].duration = activityStart.map { now() - $0 }
        transcript[openTray].content = .tools(runs)
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
        transcript.append(TranscriptBlock(id: transcript.count, content: content))
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
