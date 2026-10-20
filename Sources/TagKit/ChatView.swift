import Foundation
import ModelKit
import SessionKit
public import Stipple

/// The full-screen workspace: the conversation on the left, the session
/// panel on the right, the input line and a footer of key hints below.
///
/// Typing goes to the input line. Esc on an empty line browses past blocks
/// (↑↓ to move, Enter to expand, c to copy); Ctrl-P opens the command
/// palette; Tab shows or hides the panel. ↑/↓ recall sent messages, typing
/// while the agent works queues the message, `/clear` on its own line starts
/// the conversation over, `/model` opens the model picker (`/model
/// provider/model` switches at once), Ctrl-C clears the line and quits when
/// pressed twice, and Ctrl-D on an empty line quits.
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
        options.mouseReporting = true
        // Rewrite only the rows that changed: a streamed word or a typed key
        // changes a few rows, not the whole screen.
        options.incrementalRendering = true
        return options
    }

    let session: ChatSession
    let agent: Agent?
    let controller: SessionController?
    let selection: ModelSelection
    let copy: @MainActor (String) -> Void

    @State private var editor: WorkspaceEditor
    @State private var sessions: SessionFlow?
    @State private var isQuitArmed = false
    @State private var quitSaveFailed = false
    @State private var browsing: Int?
    @State private var isPanelShown = true
    @State private var isPaletteOpen = false
    @State private var paletteSelection: PaletteCommand?
    @State private var scroll = ScrollPosition(edge: .bottom)
    @State private var models: ModelFlow
    @FocusState private var isInputFocused = true
    @Environment(\.exit) private var exit
    @Environment(\.terminalSize) private var terminalSize

    /// Creates the view for `agent`, whose events and input go through `session`.
    ///
    /// - Parameters:
    ///   - session: The state the view shows and the hand-off of input.
    ///   - agent: The agent loop the view starts.
    ///   - selection: The model in use, which `/model` changes; the agent
    ///     should read its ``ModelSelection/current``.
    ///   - copy: Puts text on the clipboard; defaults to the terminal's
    ///     clipboard escape (OSC 52).
    public init(
        session: ChatSession,
        agent: Agent,
        selection: ModelSelection,
        copy: @escaping @MainActor (String) -> Void = Clipboard.copy,
    ) {
        self.session = session
        self.agent = agent
        self.controller = nil
        _sessions = State(initialValue: nil)
        _editor = State(initialValue: WorkspaceEditor(session: session))
        self.selection = selection
        self.copy = copy
        _models = State(initialValue: ModelFlow(selection: selection))
    }

    /// Creates the durable workspace. The controller owns switching and task lifetime.
    public init(controller: SessionController, copy: @escaping @MainActor (String) -> Void = Clipboard.copy) {
        self.controller = controller
        self.session = controller.session
        self.agent = nil
        self.selection = controller.selection
        self.copy = copy
        let editor = WorkspaceEditor(session: controller.session, controller: controller)
        _editor = State(initialValue: editor)
        _sessions = State(initialValue: SessionFlow(controller: controller, editor: editor))
        let models = ModelFlow(selection: controller.selection)
        models.onChosen = { Task { try? await controller.modelChosen() } }
        _models = State(initialValue: models)
    }

    /// The panes, the input line and the footer.
    public var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                TranscriptPane(session: session, selected: selectedBlockID, position: $scroll, loadEarlier: loadEarlier)
                    .pane(title: controller?.active?.title ?? "tag", isActive: browsing != nil)
                if isPanelShown, terminalSize.width >= Self.panelMinimumWidth {
                    SessionPanel(session: session, selection: selection)
                        .pane(title: "session", isActive: false)
                        .frame(width: SessionPanel.width + 4)
                }
            }
            .frame(maxHeight: .infinity)
            if let controller {
                SessionStateBar(controller: controller, error: editor.error)
            }
            HStack {
                Text("› ").foregroundStyle(session.isWaitingForInput ? Theme.accent : Theme.rule)
                TextField(
                    controller?.isReadOnly == true
                        ? "read-only session" : session.isWaitingForInput ? "ask anything" : "type ahead…",
                    text: $editor.text
                )
                .focused($isInputFocused)
                .focusable(!isOverlayOpen)
            }
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .border(.rounded, color: session.isWaitingForInput && browsing == nil ? Theme.accent : Theme.rule)
            Footer(session: session, hint: hint, offersLatest: !isQuitArmed && browsing == nil, scroll: $scroll)
        }
        .overlay {
            if isPaletteOpen {
                CommandPalette(selection: $paletteSelection, offersSessions: controller != nil) { command in
                    isPaletteOpen = false
                    run(command)
                }
            } else if let sessions, sessions.isOpen {
                SessionPicker(
                    state: sessions, width: max(24, min(terminalSize.width - 4, 140)),
                    height: max(16, terminalSize.height - 2))
            } else if models.isOpen {
                ModelFlowView(flow: models, width: min(terminalSize.width - 4, 84))
            } else if selection.isChatGPTWelcomeDue {
                ChatGPTWelcomeNotice { dismissWelcome() }
            }
        }
        .onPaste { [models] text in
            if let sessions, sessions.isOpen {
                sessions.type(text)
            } else if models.isOpen {
                models.paste(text)
            }
        }
        .onChange(of: isOverlayOpen) {
            isInputFocused = !isOverlayOpen
        }
        .onChange(of: controller?.draft.pendingInputID) { editor.pendingChanged() }
        .onChange(of: controller?.active?.id) {
            editor.sessionChanged()
            leaveBrowsing()
        }
        .onSubmit { Task { await submit() } }
        .onKeyPress { press in
            handle(press)
        }
        .task {
            do {
                if let controller { await controller.run() } else if let agent { try await agent.run() }
                exit()
            } catch {
                exit(throwing: error)
            }
        }
        .task {
            // The catalogue behind the picker, so `/model` opens on a full list.
            await selection.load()
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
}

extension ChatView {
    /// Keys the text field leaves alone.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if let sessions, sessions.isOpen {
            return sessions.handle(press) ? .handled : .ignored
        }
        if isPaletteOpen {
            return handlePalette(press)
        }
        if let result = handleModelKeys(press) {
            return result
        }
        if let selected = browsing {
            // A `/clear` may have emptied the transcript under the selection.
            guard selected < session.blocks.count else {
                leaveBrowsing()
                return handle(press)
            }
            return handleBrowsing(press, selected: selected)
        }
        switch PromptKey(press, inputIsEmpty: editor.text.isEmpty) {
        case .interrupt:
            interrupt()
        case .endOfInput:
            requestQuit()
        case .older:
            editor.text = editor.history.older(in: session.history, current: editor.text) ?? editor.text
        case .newer:
            editor.text = editor.history.newer(in: session.history) ?? editor.text
        case .browse:
            startBrowsing()
        case .palette:
            isPaletteOpen = true
        case .sessions:
            openSessions()
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
            if selected == 0, session.hasEarlier {
                loadEarlier()
                return .handled
            }
            select(max(0, selected - 1))
        case .next:
            select(min(session.transcript.count - 1, selected + 1))
        case .toggle:
            session.toggle(session.blocks[selected].id)
        case .copy:
            copy(session.transcript[selected].plainText)
        case .leave, nil:
            leaveBrowsing()
            if let typed = press.typedText {
                editor.text += typed
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

    /// Ctrl-C clears the line; on an empty line, a second press quits.
    private func interrupt() {
        if !editor.text.isEmpty {
            editor.text = ""
            editor.history.reset()
        } else if isQuitArmed {
            isQuitArmed = false
            requestQuit()
        } else {
            isQuitArmed = true
        }
    }
}

extension ChatView {
    private var selectedBlockID: Int? {
        guard let browsing, session.blocks.indices.contains(browsing) else { return nil }
        return session.blocks[browsing].id
    }

    private func loadEarlier() {
        let added = session.loadEarlier()
        if let browsing { select(browsing + added) }
    }

    private func sizeSessionFlow() {
        sessions?.rowLimit = max(1, (terminalSize.height - (terminalSize.width >= 104 ? 12 : 20)) / 3)
        sessions?.referencePageSize = max(4, terminalSize.height - 12)
    }

    func openSessions(purpose: SessionFlow.Purpose = .browse) {
        sizeSessionFlow()
        Task { await sessions?.open(purpose: purpose) }
    }

    func requestQuit() {
        Task {
            if quitSaveFailed {
                await controller?.shutdown()
                exit()
                return
            }
            do {
                try await controller?.close()
                exit()
            } catch {
                quitSaveFailed = true
                editor.error =
                    "Could not save: \(error.localizedDescription). Quit again to leave without saving the draft."
            }
        }
    }

    private func submit() async {
        guard !isOverlayOpen else { return }
        models.rowLimit = max(terminalSize.height - 14, 5)
        sizeSessionFlow()
        await editor.submit(models: models, sessions: sessions)
    }

    /// What the footer's left side says: a pending quit, the browse keys, or
    /// the everyday keys.
    fileprivate var hint: Footer.Hint {
        if quitSaveFailed { return .warning("save failed · ctrl-d again quits without saving") }
        if isQuitArmed {
            return .warning("press ctrl-c again to quit")
        }
        if browsing != nil {
            return WorkspaceHints.browsing(
                toggle: { if let selectedBlockID { session.toggle(selectedBlockID) } },
                copy: {
                    if let browsing, browsing < session.blocks.count { copy(session.transcript[browsing].plainText) }
                }, back: leaveBrowsing)
        }
        // `↓ latest` is the footer's to add: it reads the scroll position,
        // which changes on every scroll, and this view should not.
        return WorkspaceHints.prompt(
            durable: controller != nil, browse: startBrowsing, sessions: { openSessions() },
            palette: { isPaletteOpen = true }, togglePanel: { isPanelShown.toggle() })
    }

    func startBrowsing() {
        guard !session.blocks.isEmpty else {
            isInputFocused = true
            return
        }
        select(session.blocks.count - 1)
    }

    /// Selects a block and scrolls it into view.
    fileprivate func select(_ id: Int) {
        browsing = id
        if session.blocks.indices.contains(id) { scroll.scrollTo(id: session.blocks[id].id) }
    }

    fileprivate func leaveBrowsing() {
        browsing = nil
        isInputFocused = true
        scroll.scrollTo(edge: .bottom)
    }
}
extension ChatView {
    func run(_ command: PaletteCommand) {
        isInputFocused = true
        switch command {
        case .switchModel:
            openModels { $0.openPicker() }
        case .connectProvider:
            openModels { $0.openConnect() }
        case .togglePanel:
            isPanelShown.toggle()
        case .copyLastReply:
            let reply = session.transcript.last { if case .reply = $0.content { true } else { false } }
            if let reply {
                copy(reply.plainText)
            }
        case .browse:
            startBrowsing()
        case .quit:
            requestQuit()
        case .sessions:
            openSessions()
        case .newSession:
            Task {
                await sessions?.create()
                editor.error = sessions?.error
            }
        case .referenceSession:
            openSessions(purpose: .reference)
        }
    }

    /// Whether the model picker, connecting a provider or the ChatGPT plan
    /// notice covers the workspace, so keys are theirs and not the input's.
    var isOverlayOpen: Bool {
        isPaletteOpen || sessions?.isOpen == true || models.isOpen || selection.isChatGPTWelcomeDue
    }

    /// Opens the picker or connecting a provider, sized for the terminal.
    /// Focus follows ``isOverlayOpen``: a `/model x/y` that switches at once
    /// opens nothing, and the input must keep its focus.
    func openModels(_ open: (ModelFlow) -> Void) {
        models.rowLimit = max(terminalSize.height - 14, 5)
        open(models)
    }

    /// Keys for the model overlays, or `nil` when none is open.
    func handleModelKeys(_ press: KeyPress) -> KeyPress.Result? {
        models.handleWorkspaceKey(press).map { _ in .handled }
    }

    func dismissWelcome() {
        selection.dismissChatGPTWelcome()
        isInputFocused = true
    }
}
