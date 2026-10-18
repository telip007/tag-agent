public import Stipple

/// The terminal UI: finished lines scroll into the terminal's history, while
/// a live area below shows what the agent is doing, the input line and the
/// status bar.
///
/// It looks like a plain prompt; the rest is found by using it. ↑ and ↓
/// recall sent messages, typing while the agent works queues the message,
/// Ctrl-C clears the line and quits when pressed twice, and Ctrl-D on an
/// empty line quits.
///
/// The view starts the agent when it appears and exits the app when the
/// agent's loop ends, rethrowing its error.
public struct ChatView: View {
    /// How long a first Ctrl-C on an empty line waits for the second.
    static let quitWindow = Duration.seconds(2)

    /// The options to run the view with: Ctrl-C is the view's to handle.
    public static var renderOptions: RenderOptions {
        var options = RenderOptions()
        options.exitOnCtrlC = false
        return options
    }

    let session: ChatSession
    let agent: Agent

    @State private var input = ""
    @State private var history = InputHistory()
    @State private var isQuitArmed = false
    @FocusState private var isInputFocused = true
    @Environment(\.exit) private var exit

    /// Creates the view for `agent`, whose events and input go through `session`.
    public init(session: ChatSession, agent: Agent) {
        self.session = session
        self.agent = agent
    }

    /// The transcript, the live area and the status bar.
    public var body: some View {
        VStack(alignment: .leading) {
            Static(session.transcript) { entry in
                TranscriptLine(entry: entry)
            }
            if let activity = session.activity, let start = session.activityStart {
                ActivityLine(text: activity, start: start)
            }
            HStack {
                Text("› ").foregroundStyle(session.isWaitingForInput ? Theme.accent : .gray)
                TextField(session.isWaitingForInput ? "" : "type ahead…", text: $input)
                    .focused($isInputFocused)
            }
            if isQuitArmed {
                Text("press ctrl-c again to quit").foregroundStyle(Theme.accent)
            } else if let status = session.status {
                StatusBar(status: status, queued: session.queued.count)
            }
        }
        .onSubmit {
            if session.submit(input) {
                input = ""
                history.reset()
            }
        }
        .onKeyPress { press in
            handle(press)
        }
        .task {
            do {
                try await agent.run()
                exit()
            } catch {
                exit(throwing: error)
            }
        }
        .task(id: isQuitArmed) {
            guard isQuitArmed else {
                return
            }
            try? await Task.sleep(for: Self.quitWindow)
            if !Task.isCancelled {
                isQuitArmed = false
            }
        }
    }

    /// The keys the text field leaves alone: history, Ctrl-C and Ctrl-D.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch PromptKey(press, inputIsEmpty: input.isEmpty) {
        case .interrupt:
            interrupt()
        case .endOfInput:
            exit()
        case .older:
            input = history.older(in: session.history, current: input) ?? input
        case .newer:
            input = history.newer(in: session.history) ?? input
        case nil:
            return .ignored
        }
        return .handled
    }

    /// Ctrl-C clears the line; on an empty line, a second press quits.
    private func interrupt() {
        if !input.isEmpty {
            input = ""
            history.reset()
        } else if isQuitArmed {
            // Leaves the status bar, not the hint, in the final frame.
            isQuitArmed = false
            exit()
        } else {
            isQuitArmed = true
        }
    }
}

/// What a key press means at the prompt, beyond editing the line.
enum PromptKey: Equatable {
    /// Ctrl-C.
    case interrupt
    /// Ctrl-D on an empty line, as end-of-file in a shell.
    case endOfInput
    /// ↑: an older message from the history.
    case older
    /// ↓: a newer message, or back to the line being typed.
    case newer

    init?(_ press: KeyPress, inputIsEmpty: Bool) {
        guard press.phase != .up else {
            return nil
        }
        let modifiers = press.modifiers.subtracting([.capsLock, .numLock])
        switch (press.key, modifiers) {
        case ("c", .control):
            self = .interrupt
        case ("d", .control) where inputIsEmpty:
            self = .endOfInput
        case (.upArrow, []):
            self = .older
        case (.downArrow, []):
            self = .newer
        default:
            return nil
        }
    }
}

/// The few colours the UI uses: amber phosphor, as on old terminals.
enum Theme {
    static let accent = Color(red: 255, green: 176, blue: 0)
}

/// One transcript entry. Agent text and tool calls hang two columns in, so
/// the user's messages stand out at the margin.
struct TranscriptLine: View {
    let entry: TranscriptEntry

    var body: some View {
        switch entry.content {
        case .banner(let model, let folder):
            (Text(" TAG ").foregroundStyle(.black).background(Theme.accent).bold()
                + Text("  \(model)")
                + Text(" · \(folder)").dim())
                .padding(.bottom, 1)
        case .user(let text):
            (Text("› ").foregroundStyle(Theme.accent) + Text(text).bold())
        case .agent(let text):
            HStack {
                Text("  ")
                Text(text)
            }
        case .tool(let name, let summary, let failed, let duration):
            HStack {
                Text("  ")
                Text(failed ? "✗ " : "▸ ").foregroundStyle(failed ? .red : Theme.accent)
                    + Text(name)
                    + Text(summary.isEmpty ? "" : "  \(summary)").dim()
                    + Text(duration.map { "  \(ChatSession.seconds($0))" } ?? "").foregroundStyle(Theme.accent)
            }
        case .turnSummary(let text):
            Text("  ─ \(text)").dim().padding(.bottom, 1)
        }
    }
}

/// A spinner with what the agent is doing, and for how long once it's been
/// more than a second.
struct ActivityLine: View {
    static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    let text: String
    let start: ContinuousClock.Instant

    var body: some View {
        TimelineView(.periodic(every: .milliseconds(80))) { context in
            let elapsed = ContinuousClock.now - start
            Text("  \(Self.frames[context.frame % Self.frames.count]) ").foregroundStyle(Theme.accent)
                + Text(text).dim()
                + Text(elapsed >= ChatSession.noticeableDuration ? "  \(ChatSession.seconds(elapsed))" : "").dim()
        }
    }
}

/// The status line, styled, with a context meter that warms up as the window
/// fills. Fields drop out, least useful first, when the terminal is narrow.
struct StatusBar: View {
    /// What the bar can show, in display order.
    enum Field: Equatable {
        case folder, model, meter, context, cost, queued
    }

    static let meterCells = 8
    static let separator = " · "

    let status: StatusLine
    let queued: Int
    @Environment(\.terminalSize) private var terminalSize

    var body: some View {
        Self.fields(for: status, queued: queued, width: terminalSize.width)
            .map(text)
            .enumerated()
            .reduce(Text("")) { line, field in
                field.offset == 0 ? field.element : line + Text(Self.separator).dim() + field.element
            }
    }

    /// The fields that fit in `width` columns, dropping the folder first,
    /// then the model, then the meter.
    static func fields(for status: StatusLine, queued: Int, width: Int) -> [Field] {
        var fields: [Field] = [.folder, .model, .meter, .context, .cost]
        if status.contextFraction == nil {
            fields.removeAll { $0 == .meter }
        }
        if queued > 0 {
            fields.append(.queued)
        }
        for dropped in [Field.folder, .model, .meter] where width < self.width(of: fields, status, queued) {
            fields.removeAll { $0 == dropped }
        }
        return fields
    }

    private static func width(of fields: [Field], _ status: StatusLine, _ queued: Int) -> Int {
        let texts = fields.map { plain($0, status, queued) }
        return texts.map(\.count).reduce(0, +) + separator.count * max(0, texts.count - 1)
    }

    private static func plain(_ field: Field, _ status: StatusLine, _ queued: Int) -> String {
        switch field {
        case .folder: status.folder
        case .model: status.model.name
        case .meter: String(repeating: "▱", count: meterCells)
        case .context: status.contextUsage
        case .cost: status.money
        case .queued: "\(queued) queued"
        }
    }

    private func text(_ field: Field) -> Text {
        switch field {
        case .meter:
            meter
        case .queued:
            Text(Self.plain(field, status, queued)).foregroundStyle(Theme.accent)
        default:
            Text(Self.plain(field, status, queued)).dim()
        }
    }

    /// `▰▰▱▱▱▱▱▱`: green while there is room, amber past half, red past 80%.
    private var meter: Text {
        let fraction = min(max(status.contextFraction ?? 0, 0), 1)
        let cells = Self.meterCells
        let filled = fraction > 0 ? max(1, Int((fraction * Double(cells)).rounded())) : 0
        let color: Color = fraction < 0.5 ? .green : fraction < 0.8 ? Theme.accent : .red
        return Text(String(repeating: "▰", count: filled)).foregroundStyle(color)
            + Text(String(repeating: "▱", count: cells - filled)).dim()
    }
}
