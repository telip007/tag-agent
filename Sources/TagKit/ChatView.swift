public import Stipple

/// The full-screen workspace: the conversation on the left, the session
/// panel on the right, the input line and a footer of key hints below.
///
/// Typing goes to the input line. Esc on an empty line browses past blocks
/// (↑↓ to move, Enter to expand, c to copy); Ctrl-P opens the command
/// palette; Tab shows or hides the panel. ↑/↓ recall sent messages, typing
/// while the agent works queues the message, Ctrl-C clears the line and quits
/// when pressed twice, and Ctrl-D on an empty line quits.
///
/// The view starts the agent when it appears and exits the app when the
/// agent's loop ends, rethrowing its error.
public struct ChatView: View {
    /// How long a first Ctrl-C on an empty line waits for the second.
    static let quitWindow = Duration.seconds(2)
    /// Narrower terminals hide the session panel.
    static let panelMinimumWidth = 90

    /// The options to run the view with: full screen, and Ctrl-C is the
    /// view's to handle.
    public static var renderOptions: RenderOptions {
        var options = RenderOptions()
        options.exitOnCtrlC = false
        options.alternateScreen = true
        return options
    }

    let session: ChatSession
    let agent: Agent
    let copy: @MainActor (String) -> Void

    @State private var input = ""
    @State private var history = InputHistory()
    @State private var isQuitArmed = false
    @State private var browsing: Int?
    @State private var isPanelShown = true
    @State private var isPaletteOpen = false
    @State private var paletteSelection: PaletteCommand?
    @FocusState private var isInputFocused = true
    @Environment(\.exit) private var exit
    @Environment(\.terminalSize) private var terminalSize

    /// Creates the view for `agent`, whose events and input go through `session`.
    ///
    /// - Parameters:
    ///   - session: The state the view shows and the hand-off of input.
    ///   - agent: The agent loop the view starts.
    ///   - copy: Puts text on the clipboard; defaults to the terminal's
    ///     clipboard escape (OSC 52).
    public init(session: ChatSession, agent: Agent, copy: @escaping @MainActor (String) -> Void = Clipboard.copy) {
        self.session = session
        self.agent = agent
        self.copy = copy
    }

    /// The panes, the input line and the footer.
    public var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                TranscriptPane(session: session, selected: browsing)
                    .pane(title: "tag", isActive: browsing != nil)
                if isPanelShown, terminalSize.width >= Self.panelMinimumWidth {
                    SessionPanel(session: session)
                        .pane(title: "session", isActive: false)
                        .frame(width: SessionPanel.width + 4)
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                Text("› ").foregroundStyle(session.isWaitingForInput ? Theme.accent : Theme.rule)
                TextField(session.isWaitingForInput ? "ask anything" : "type ahead…", text: $input)
                    .focused($isInputFocused)
            }
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .border(.rounded, color: session.isWaitingForInput && browsing == nil ? Theme.accent : Theme.rule)
            Footer(session: session, hint: hint)
        }
        .overlay {
            if isPaletteOpen {
                CommandPalette(selection: $paletteSelection) { command in
                    isPaletteOpen = false
                    run(command)
                }
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

    /// What the footer's left side says: a pending quit, the browse keys, or
    /// the everyday ones.
    private var hint: Footer.Hint {
        if isQuitArmed {
            return .warning("press ctrl-c again to quit")
        }
        if browsing != nil {
            return .keys([("↑↓", "move"), ("⏎", "expand"), ("c", "copy"), ("esc", "back")])
        }
        return .keys([("esc", "browse"), ("^p", "commands"), ("tab", "panel")])
    }

    /// Keys the text field leaves alone.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if isPaletteOpen {
            return handlePalette(press)
        }
        if let selected = browsing {
            return handleBrowsing(press, selected: selected)
        }
        switch PromptKey(press, inputIsEmpty: input.isEmpty) {
        case .interrupt:
            interrupt()
        case .endOfInput:
            exit()
        case .older:
            input = history.older(in: session.history, current: input) ?? input
        case .newer:
            input = history.newer(in: session.history) ?? input
        case .browse:
            browsing = session.transcript.last?.id
            if browsing == nil {
                isInputFocused = true
            }
        case .palette:
            isPaletteOpen = true
        case .togglePanel:
            isPanelShown.toggle()
        case nil:
            return .ignored
        }
        return .handled
    }

    private func handleBrowsing(_ press: KeyPress, selected: Int) -> KeyPress.Result {
        switch BrowseKey(press) {
        case .previous:
            browsing = max(0, selected - 1)
        case .next:
            browsing = min(session.transcript.count - 1, selected + 1)
        case .toggle:
            session.toggle(selected)
        case .copy:
            copy(session.transcript[selected].plainText)
        case .leave, nil:
            browsing = nil
            isInputFocused = true
            if let typed = press.typedText {
                input += typed
            }
        }
        return .handled
    }

    private func handlePalette(_ press: KeyPress) -> KeyPress.Result {
        guard press.key == .escape else {
            return .ignored
        }
        isPaletteOpen = false
        isInputFocused = true
        return .handled
    }

    private func run(_ command: PaletteCommand) {
        isInputFocused = true
        switch command {
        case .togglePanel:
            isPanelShown.toggle()
        case .copyLastReply:
            let reply = session.transcript.last { if case .reply = $0.content { true } else { false } }
            if let reply {
                copy(reply.plainText)
            }
        case .browse:
            browsing = session.transcript.last?.id
        case .quit:
            exit()
        }
    }

    /// Ctrl-C clears the line; on an empty line, a second press quits.
    private func interrupt() {
        if !input.isEmpty {
            input = ""
            history.reset()
        } else if isQuitArmed {
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
    /// Esc on an empty line: browse past blocks.
    case browse
    /// Ctrl-P: the command palette.
    case palette
    /// Tab: show or hide the session panel.
    case togglePanel

    init?(_ press: KeyPress, inputIsEmpty: Bool) {
        guard press.phase != .up else {
            return nil
        }
        switch (press.key, press.modifiers.subtracting([.capsLock, .numLock])) {
        case ("c", .control):
            self = .interrupt
        case ("d", .control) where inputIsEmpty:
            self = .endOfInput
        case ("p", .control):
            self = .palette
        case (.upArrow, []):
            self = .older
        case (.downArrow, []):
            self = .newer
        case (.escape, []) where inputIsEmpty:
            self = .browse
        case (.tab, []):
            self = .togglePanel
        default:
            return nil
        }
    }
}

/// What a key press means while browsing past blocks.
enum BrowseKey: Equatable {
    case previous
    case next
    case toggle
    case copy
    /// Back to the input line; a typed character goes into it.
    case leave

    init?(_ press: KeyPress) {
        guard press.phase != .up else {
            return nil
        }
        switch (press.key, press.modifiers.subtracting([.capsLock, .numLock])) {
        case (.upArrow, []), ("k", []):
            self = .previous
        case (.downArrow, []), ("j", []):
            self = .next
        case (.return, []), (.space, []):
            self = .toggle
        case ("c", []), ("y", []):
            self = .copy
        case (.escape, _), (.character, _):
            self = .leave
        default:
            return nil
        }
    }
}

extension KeyPress {
    /// The text a press types, if it types any: a plain character without
    /// Control, Option or Command.
    var typedText: String? {
        guard case .character(let character) = key,
            modifiers.isDisjoint(with: [.control, .option, .command])
        else {
            return nil
        }
        return characters.isEmpty ? String(character) : characters
    }
}
