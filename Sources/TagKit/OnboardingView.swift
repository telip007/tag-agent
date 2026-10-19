import ModelKit
public import Stipple

/// The first start: a welcome, connecting one or more providers, and
/// picking the first model. It exits once a model is in use, so the caller
/// can start the chat with ``ModelSelection/current``; Ctrl-C exits without
/// one.
///
/// ```swift
/// let selection = ModelSelection(registry: registry, signIn: signIn)
/// if await !selection.restoreLastModel() {
///     try await Stipple.run(OnboardingView(selection: selection), options: OnboardingView.renderOptions)
///     guard selection.current != nil else { return }  // the user quit
/// }
/// ```
///
/// When a provider is already connected (an API key in the environment, or
/// the last model has gone), Enter on the welcome goes straight to the picker.
public struct OnboardingView: View {
    /// Full screen, with the mouse, and Ctrl-C handled by the view.
    public static var renderOptions: RenderOptions {
        var options = RenderOptions()
        options.exitOnCtrlC = false
        options.alternateScreen = true
        options.mouseReporting = true
        return options
    }

    let selection: ModelSelection
    /// Whether a model was used before but couldn't be restored.
    let hasLostModel: Bool
    @State private var flow: ModelFlow
    @Environment(\.exit) private var exit
    @Environment(\.terminalSize) private var terminalSize

    /// Creates the onboarding for `selection`.
    ///
    /// - Parameter selection: Where providers are connected and the first
    ///   model is chosen.
    public init(selection: ModelSelection) {
        self.selection = selection
        hasLostModel = selection.settings.load().lastModel != nil
        _flow = State(initialValue: ModelFlow(selection: selection, isOnboarding: true))
    }

    /// The welcome, or the step the flow shows, in the middle of the screen.
    public var body: some View {
        let width = min(max(terminalSize.width - 4, 40), 76)
        VStack {
            if flow.isOpen {
                ModelFlowView(flow: flow, width: width)
            } else {
                Welcome(hasLostModel: hasLostModel, width: width) { [flow] in flow.start() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onKeyPress { [flow, exit] press in flow.handleOnboardingKey(press) { exit() } ? .handled : .ignored }
        .onPaste { [flow] in flow.paste($0) }
        .task {
            flow.rowLimit = max(terminalSize.height - 14, 5)
            flow.onChosen = { exit() }
            await selection.load()
        }
    }
}

/// The first screen: what Tag needs and how to go on.
struct Welcome: View {
    let hasLostModel: Bool
    let width: Int
    let start: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("Welcome to Tag Agent.").bold()
            Text(" ")
            if hasLostModel {
                Text("The model you used last isn't available any more. Pick another one to go on.")
            } else {
                Text(
                    "Tag talks to models through the providers you connect: "
                        + "your ChatGPT plan, OpenCode Go or OpenRouter.")
                Text(" ")
                Text("Connect one or more, then pick the model to start with. /model switches later.")
            }
            Text(" ")
            HStack {
                KeyHints(keys: [Footer.Key(key: "↵", label: "get started", action: start)])
                Text(" · ^c quit").dim()
            }
        }
        .modal(title: "tag", width: width)
    }
}
