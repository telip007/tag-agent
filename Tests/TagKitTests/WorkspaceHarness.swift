import Foundation

@testable import Stipple
@testable import TagKit

/// A terminal for running a view in Stipple's runtime: it takes the output
/// and lets tests type.
@MainActor
final class FakeTerminal: TerminalHost {
    var size: Size
    var isTerminal: Bool { true }
    var isInteractive: Bool { true }
    var isInputTerminal: Bool { true }
    var colorDepth: ColorDepth { .trueColor }
    private var continuation: AsyncStream<TerminalEvent>.Continuation?

    init(size: Size) {
        self.size = size
    }

    func write(_ text: String) {}
    func writeError(_ text: String) {}
    func enableRawMode() -> Bool { true }
    func restore() {}
    func setBracketedPaste(_ enabled: Bool) {}
    func setMouseReporting(_ enabled: Bool) {}
    func setMouseMotionReporting(_ enabled: Bool) {}
    func pushKittyKeyboard(_ flags: KittyKeyboardFlags) {}
    func queryKittyKeyboard() {}
    func noteModes(alternateScreen: Bool, cursorHidden: Bool) {}

    func events() -> AsyncStream<TerminalEvent> {
        let (stream, continuation) = AsyncStream<TerminalEvent>.makeStream()
        self.continuation = continuation
        return stream
    }

    func suspend<T>(_ body: () async throws -> T) async throws -> T {
        try await body()
    }

    /// Sends bytes as if typed.
    func type(_ bytes: String) {
        continuation?.yield(.input(Array(bytes.utf8)))
    }
}

/// The workspace running in Stipple's runtime, typed into like a terminal.
@MainActor
struct Workspace {
    let session = ChatSession()
    let selection: ModelSelection
    let terminal: FakeTerminal
    let runtime: Runtime

    init(selection: ModelSelection = makeSelection(), size: Size = Size(width: 140, height: 40)) {
        self.selection = selection
        terminal = FakeTerminal(size: size)
        let model = ScriptedModel([])
        let session = session
        let agent = Agent(
            model: { selection.current ?? model.active }, environment: .fake,
            output: session.handle, input: session.nextMessage)
        var options = ChatView.renderOptions
        options.maxFps = 1_000
        runtime = Runtime(
            view: ChatView(session: session, agent: agent, selection: selection, copy: { _ in }), options: options,
            terminal: terminal)
    }

    /// Types `text` and lets the view catch up, until `condition` holds.
    func type(_ text: String, until condition: () -> Bool = { true }) async {
        terminal.type(text)
        await settle(until: condition)
    }

    /// Lets frames render and tasks run until `condition` holds, or a while.
    func settle(until condition: () -> Bool = { true }) async {
        let deadline = ContinuousClock.now + .seconds(5)
        repeat {
            try? await Task.sleep(for: .milliseconds(10))
            await runtime.settle()
        } while !condition() && ContinuousClock.now < deadline
    }

    /// What the screen shows now, without styling.
    var screen: String {
        runtime.produceFrame().text.replacing(/\x1B\[[0-9;?]*[A-Za-z]/, with: "")
    }

    func stop() {
        runtime.exit(with: nil)
    }
}
