public import Observation

/// One finished line of the conversation. Once shown it moves into the
/// terminal's scrollback and never changes.
public struct TranscriptEntry: Identifiable, Sendable, Equatable {
    /// What the line shows.
    public enum Content: Sendable, Equatable {
        /// The header at the top of a session.
        case banner(model: String, folder: String)
        /// A message the user sent.
        case user(String)
        /// Text the model wrote.
        case agent(String)
        /// A finished tool call: its name, the gist of its arguments, whether
        /// it failed, and how long it took when that was long enough to notice.
        case tool(name: String, summary: String, failed: Bool, duration: Duration?)
        /// The line closing a turn: tools run, time taken, what it cost.
        case turnSummary(String)
    }

    /// The entry's position in the transcript.
    public let id: Int
    /// What the line shows.
    public let content: Content
}

/// The state the chat view shows, fed by the ``Agent``'s events, and the
/// hand-off of submitted messages back to the agent.
///
/// The agent reads input with ``nextMessage()``. Messages submitted while it
/// is busy wait in a queue, so the user can type ahead.
@MainActor
@Observable
public final class ChatSession {
    /// Tool calls quicker than this don't show their duration.
    static let noticeableDuration = Duration.seconds(1)

    /// Everything said so far, oldest first.
    public private(set) var transcript: [TranscriptEntry] = []
    /// The latest status line, shown below the input.
    public private(set) var status: StatusLine?
    /// What the agent is busy with (`"thinking"`, a tool call), or `nil`.
    public private(set) var activity: String?
    /// When the current ``activity`` started.
    public private(set) var activityStart: ContinuousClock.Instant?
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
    @ObservationIgnored private var turn: Turn?

    /// What the current turn has done so far, for its summary line.
    private struct Turn {
        var start: ContinuousClock.Instant
        var startCost: Double
        var tools = 0
    }

    /// Creates an empty session.
    ///
    /// - Parameter now: The clock that times turns and tool calls.
    public init(now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.now = now
    }

    /// Updates the state for an event from the agent loop.
    public func handle(_ event: AgentEvent) {
        switch event {
        case .status(let line):
            if status == nil {
                append(.banner(model: line.model.name, folder: line.folder))
            }
            finishTurn(cost: line.cost)
            status = line
            setActivity(nil)
        case .thinking:
            setActivity("thinking")
        case .reply(let text):
            append(.agent(text))
        case .toolStarted(let name, let arguments):
            setActivity("\(name)  \(ToolSummary.summarize(arguments))")
        case .toolFinished(let name, let arguments, let failed):
            let elapsed = activityStart.map { now() - $0 }
            let duration = elapsed.flatMap { $0 >= Self.noticeableDuration ? $0 : nil }
            append(.tool(name: name, summary: ToolSummary.summarize(arguments), failed: failed, duration: duration))
            turn?.tools += 1
            setActivity(nil)
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

    /// Records `text` as sent and starts timing its turn.
    private func send(_ text: String) -> String {
        append(.user(text))
        turn = Turn(start: now(), startCost: status?.cost ?? 0)
        return text
    }

    private func finishTurn(cost: Double) {
        guard let turn else {
            return
        }
        self.turn = nil
        var parts: [String] = []
        if turn.tools > 0 {
            parts.append(turn.tools == 1 ? "1 tool" : "\(turn.tools) tools")
        }
        parts.append(Self.seconds(now() - turn.start))
        parts.append(StatusLine.money(cost - turn.startCost))
        append(.turnSummary(parts.joined(separator: " · ")))
    }

    private func setActivity(_ text: String?) {
        activity = text
        activityStart = text == nil ? nil : now()
    }

    private func append(_ content: TranscriptEntry.Content) {
        transcript.append(TranscriptEntry(id: transcript.count, content: content))
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
