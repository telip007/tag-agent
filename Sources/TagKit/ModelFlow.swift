import Foundation
import ModelKit
import Observation
import Stipple

/// Picking a model and connecting providers, as one flow over the
/// workspace or the onboarding: the picker's Ctrl-A opens "connect a
/// provider", and Esc there goes back to the picker.
///
/// Its owner sends it key presses and pastes while it shows something, and
/// draws ``ModelFlowView``.
@MainActor
@Observable
final class ModelFlow {
    /// What the flow shows.
    enum Screen {
        case picker(ModelPickerState)
        case connect(ProviderSetupState)
    }

    @ObservationIgnored let selection: ModelSelection
    /// During onboarding, closing the picker goes back to connecting, and
    /// connecting offers to go on.
    @ObservationIgnored let isOnboarding: Bool
    /// Called once a chosen model is in use.
    @ObservationIgnored var onChosen: @MainActor () -> Void = {}
    /// How many rows the picker shows; the owner sets it from the terminal size.
    @ObservationIgnored var rowLimit = 12
    /// What's shown, or `nil` for nothing.
    private(set) var screen: Screen?
    @ObservationIgnored private var connectReturnsToPicker = false

    init(selection: ModelSelection, isOnboarding: Bool = false) {
        self.selection = selection
        self.isOnboarding = isOnboarding
    }

    /// Whether something is shown, so keys are the flow's.
    var isOpen: Bool {
        screen != nil
    }

    /// Opens the picker with `query` in its search, and refreshes the
    /// catalogue behind it.
    func openPicker(query: String = "") {
        let picker = ModelPickerState(
            query: query,
            catalogue: selection.catalogue,
            current: selection.current?.entry.ref,
            recent: selection.recent,
            effort: { [selection] in selection.effort(for: $0) },
        )
        picker.rowLimit = rowLimit
        screen = .picker(picker)
        Task {
            await selection.load()
            if let catalogue = selection.catalogue {
                picker.update(catalogue: catalogue)
            }
        }
    }

    /// Opens "connect a provider".
    func openConnect() {
        connectReturnsToPicker = isOnboarding || screen.map { if case .picker = $0 { true } else { false } } ?? false
        screen = .connect(ProviderSetupState(selection: selection, offersProceed: isOnboarding))
        if selection.catalogue == nil {
            Task { await selection.load() }
        }
    }

    /// Hides whatever is shown.
    func close() {
        screen = nil
    }

    /// Sends a key press to what's shown.
    ///
    /// - Returns: Whether the press was taken.
    func handle(_ press: KeyPress) -> Bool {
        switch screen {
        case .picker(let picker):
            let (handled, action) = picker.handle(press)
            action.map(perform)
            return handled
        case .connect(let setup):
            let (handled, action) = setup.handle(press)
            action.map(perform)
            return handled
        case nil:
            return false
        }
    }

    /// `/model` opens the picker; `/model provider/model` switches, or opens
    /// the picker searching for the text when nothing matches exactly.
    func run(_ command: ModelCommand) async {
        switch command {
        case .openPicker:
            openPicker()
        case .switchTo(let text):
            if await selection.quickSwitch(text) == nil {
                openPicker(query: text)
            } else {
                onChosen()
            }
        }
    }

    /// Keys while the flow or the ChatGPT plan notice covers the workspace:
    /// everything typed is theirs, Ctrl-C closes the flow, and Enter or Esc
    /// dismiss the notice.
    ///
    /// - Returns: `nil` when neither is shown, so the key is the workspace's.
    func handleWorkspaceKey(_ press: KeyPress) -> Bool? {
        if isOpen {
            if press.key == "c", press.modifiers.contains(.control) {
                close()
            } else {
                _ = handle(press)
            }
            return true
        }
        guard selection.isChatGPTWelcomeDue else {
            return nil
        }
        if press.phase != .up, press.key == .return || press.key == .escape {
            selection.dismissChatGPTWelcome()
        }
        return true
    }

    /// Onboarding keys: Ctrl-C quits, and on the welcome Enter goes on.
    ///
    /// - Returns: Whether the press was taken.
    func handleOnboardingKey(_ press: KeyPress, quit: () -> Void) -> Bool {
        guard press.phase != .up else {
            return false
        }
        if press.key == "c", press.modifiers.contains(.control) {
            quit()
            return true
        }
        if isOpen {
            return handle(press)
        }
        guard press.key == .return else {
            return false
        }
        start()
        return true
    }

    /// Past the welcome: to the picker when a provider is connected, else to
    /// connecting one.
    func start() {
        if selection.connected.isEmpty {
            openConnect()
        } else {
            openPicker()
        }
    }

    /// Types pasted text into what's shown.
    func paste(_ text: String) {
        switch screen {
        case .picker(let picker): picker.type(text)
        case .connect(let setup): if case .key = setup.phase { setup.type(text) }
        case nil: break
        }
    }

    func perform(_ action: PickerAction) {
        switch action {
        case .close:
            if isOnboarding {
                openConnect()
            } else {
                close()
            }
        case .connect:
            openConnect()
        case .use(let entry, let effort):
            Task { await use(entry, effort: effort) }
        }
    }

    func perform(_ action: SetupAction) {
        switch action {
        case .proceed:
            openPicker()
        case .close where isOnboarding:
            close()
        case .close:
            if connectReturnsToPicker {
                openPicker()
            } else {
                close()
            }
        }
    }

    /// Switches to `entry`, then closes; a failure stays in the picker.
    func use(_ entry: ModelEntry, effort: String?) async {
        do {
            try await selection.select(entry, effort: effort)
            close()
            onChosen()
        } catch {
            if case .picker(let picker) = screen {
                picker.error = error.localizedDescription
            }
        }
    }
}

/// What a ``ModelFlow`` shows, centred by its owner.
struct ModelFlowView: View {
    let flow: ModelFlow
    let width: Int

    var body: some View {
        switch flow.screen {
        case .picker(let picker):
            ModelPicker(state: picker, width: width) { [flow] in flow.perform($0) }
        case .connect(let setup):
            ProviderSetup(state: setup, width: width) { [flow] in flow.perform($0) }
        case nil:
            EmptyView()
        }
    }
}
