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
            VStack(alignment: .leading) {
                if let activity = session.activity, let start = session.activityStart {
                    ActivityLine(text: activity, start: start)
                }
                Divider().foregroundStyle(Theme.rule)
                HStack {
                    Text("› ").foregroundStyle(session.isWaitingForInput ? Theme.accent : Theme.rule)
                    TextField(session.isWaitingForInput ? "" : "type ahead…", text: $input)
                        .focused($isInputFocused)
                }
                .padding(.horizontal, 1)
                Divider().foregroundStyle(Theme.rule)
                VStack(alignment: .leading) {
                    if let status = session.status {
                        StatusBar(status: status)
                    }
                    if let hint {
                        Text(hint).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 1)
            }
            .padding(.horizontal, Theme.margin)
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

    /// A line under the status bar, only while there is something to say.
    private var hint: String? {
        if isQuitArmed {
            return "press ctrl-c again to quit"
        }
        let queued = session.queued.count
        return queued == 0 ? nil : queued == 1 ? "1 message queued" : "\(queued) messages queued"
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

/// The look: the terminal's own colours with two from Ottoman art — the gold
/// of illuminated manuscripts as the accent and İznik tile turquoise for
/// code — dim rules, and one tinted band for the user's messages.
enum Theme {
    static let accent = Color(red: 227, green: 179, blue: 65)
    static let tile = Color(red: 64, green: 184, blue: 175)
    static let rule = Color.gray
    static let userBand = Color(red: 58, green: 62, blue: 80)
    /// Columns kept free on the left and right.
    static let margin = 1
    /// Where text starts inside the margin: after a band's padding and the `› ` prompt,
    /// so replies line up with the message they answer.
    static let indent = 3
}

/// One transcript entry. The user's messages sit on a tinted band; agent
/// text and tool calls are indented under them.
struct TranscriptLine: View {
    let entry: TranscriptEntry

    var body: some View {
        content.padding(.horizontal, Theme.margin)
    }

    @ViewBuilder private var content: some View {
        switch entry.content {
        case .banner(let model, let folder):
            Banner(model: model, folder: folder).padding(.leading, 1)
        case .user(let text):
            (Text("› ").foregroundStyle(Theme.accent) + Text(text))
                .padding(.horizontal, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.userBand)
                .padding(.bottom, 1)
        case .agent(let text):
            Markdown.text(text)
                .padding(.leading, Theme.indent)
                .padding(.top, entry.followsTool ? 1 : 0)
                .padding(.bottom, 1)
        case .tool(let name, let summary, let failed, let duration):
            (Text(failed ? "✗ " : "▸ ").foregroundStyle(failed ? .red : Theme.accent)
                + Text(name)
                + Text(summary.isEmpty ? "" : "  \(summary)").dim()
                + Text(duration.map { "  \(ChatSession.seconds($0))" } ?? "").foregroundStyle(Theme.accent))
                .padding(.leading, Theme.indent)
        case .turnSummary(let text):
            Text(text).dim().padding(.leading, Theme.indent).padding(.bottom, 1)
        }
    }
}

/// The header at the top of a session: the mascot, and what is running where.
struct Banner: View {
    let model: ModelDescription
    let folder: String

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            VStack(alignment: .leading) {
                ForEach(Array(Mascot.turban.lines.enumerated()), id: \.offset) { $0.element }
            }
            VStack(alignment: .leading) {
                Text("Tag Agent").bold()
                Text(model.contextLength.map { "\(model.name) · \(StatusLine.tokens($0)) context" } ?? model.name).dim()
                Text(folder).dim()
            }
        }
        .padding(.vertical, 1)
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
            Text("\(Self.frames[context.frame % Self.frames.count]) ").foregroundStyle(Theme.accent)
                + Text(text).dim()
                + Text(elapsed >= ChatSession.noticeableDuration ? "  \(ChatSession.seconds(elapsed))" : "").dim()
        }
        .padding(.leading, Theme.indent)
    }
}

/// The status line under the input: where and with what on the left, how
/// full the context is and what it cost on the right. The context turns amber
/// past half and red past 80%, and the left side gives way on narrow
/// terminals: the folder goes first, then the model.
struct StatusBar: View {
    /// What the bar can show.
    enum Field: Equatable {
        case folder, model, context, cost
    }

    static let separator = " · "
    /// The least space kept between the two sides.
    static let gap = 2

    let status: StatusLine
    @Environment(\.terminalSize) private var terminalSize

    var body: some View {
        let fields = Self.fields(for: status, width: terminalSize.width - 2 * Theme.margin - 2)
        HStack {
            joined(fields.filter { $0 == .folder || $0 == .model }.map(text))
            Spacer(minLength: Self.gap)
            joined([text(.context), text(.cost)])
        }
    }

    /// The fields that fit in `width` columns, dropping the folder first,
    /// then the model.
    static func fields(for status: StatusLine, width: Int) -> [Field] {
        var fields: [Field] = [.folder, .model, .context, .cost]
        for dropped in [Field.folder, .model] where width < self.width(of: fields, status) {
            fields.removeAll { $0 == dropped }
        }
        return fields
    }

    private static func width(of fields: [Field], _ status: StatusLine) -> Int {
        let left = fields.filter { $0 == .folder || $0 == .model }
        let right = fields.filter { $0 == .context || $0 == .cost }
        func length(_ side: [Field]) -> Int {
            side.map { plain($0, status).count }.reduce(0, +) + separator.count * max(0, side.count - 1)
        }
        return length(left) + gap + length(right)
    }

    static func plain(_ field: Field, _ status: StatusLine) -> String {
        switch field {
        case .folder: status.folder
        case .model: status.model.name
        case .context: contextText(status)
        case .cost: status.money
        }
    }

    /// `831/1M`, with the percentage once the window is half full.
    private static func contextText(_ status: StatusLine) -> String {
        guard let fraction = status.contextFraction, fraction >= 0.5 else {
            return status.contextUsage
        }
        return "\(status.contextUsage) (\(Int((fraction * 100).rounded()))%)"
    }

    private func text(_ field: Field) -> Text {
        let text = Text(Self.plain(field, status))
        guard field == .context, let fraction = status.contextFraction, fraction >= 0.5 else {
            return text.foregroundStyle(Theme.rule)
        }
        return text.foregroundStyle(fraction < 0.8 ? Theme.accent : .red)
    }

    private func joined(_ texts: [Text]) -> Text {
        texts.enumerated().reduce(Text("")) { line, item in
            item.offset == 0 ? item.element : line + Text(Self.separator).foregroundStyle(Theme.rule) + item.element
        }
    }
}
