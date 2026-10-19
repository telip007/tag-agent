import Foundation
import Testing

@testable import Stipple
@testable import TagKit

/// Writes the workspace the README banner shows, as ANSI, to the path in
/// `TAG_BANNER_SCREEN`. Off unless that is set; see
/// `.github/assets/render-assets.swift`.
@MainActor
struct BannerScreenTests {
    nonisolated static let path = ProcessInfo.processInfo.environment["TAG_BANNER_SCREEN"]

    let clock = ManualClock()
    let session: ChatSession

    init() {
        let clock = clock
        session = ChatSession(now: { clock.instant })
    }

    @Test(.enabled(if: path != nil)) func writeBannerScreen() async throws {
        status(tokens: 18_400, cost: 0)
        await waitForInput()
        session.submit("fizzbuzz.js should stop at 10. Fix it and run it")
        while session.blocks.isEmpty {
            await Task.yield()
        }
        session.handle(.thinking)
        session.handle(.reasoningDelta("The bound is probably in the loop. Read the file first."))
        clock.advance(.seconds(2.4))
        tool("read_file", #"{"path":"fizzbuzz.js"}"#, "for (let i = 1; i <= 15; i++) {", seconds: 0.1)
        tool("code_search", #"{"pattern":"<= 15"}"#, "fizzbuzz.js:1", seconds: 0.2)
        session.handle(.reply("The loop runs to 15. Changing the bound:"))
        tool("edit_file", editArguments("fizzbuzz.js", "i <= 15", "i <= 10"), "OK", seconds: 0.1)
        tool("bash", #"{"command":"node fizzbuzz.js"}"#, "1\n2\nFizz\n4\nBuzz\nFizz\n7\n8\nFizz\nBuzz", seconds: 0.4)
        session.handle(.reply("Done. It now counts from 1 to 10 and ends with **Buzz**."))
        clock.advance(.seconds(249))
        status(tokens: 124_000, cost: 0.0031)
        await waitForInput()

        let size = Size(width: 100, height: 26)
        let view = ChatView(
            session: session, agent: Terminal([]).agent(model: ScriptedModel([])), selection: makeSelection(),
            copy: { _ in }
        )
        .frame(height: size.height)
        .environment(\.terminalSize, size)
        let screen = Stipple.renderToString(view, width: size.width)
        try screen.write(toFile: try #require(Self.path), atomically: true, encoding: .utf8)
    }

    private func status(tokens: Int, cost: Double) {
        let model = ModelDescription(name: "DeepSeek V4.1 Flash", contextLength: 1_000_000)
        let directory = URL(filePath: "/work/fizzbuzz", directoryHint: .isDirectory)
        session.handle(.status(StatusLine(directory: directory, model: model, contextTokens: tokens, cost: cost)))
    }

    private func waitForInput() async {
        _ = Task { await session.nextMessage() }
        while !session.isWaitingForInput {
            await Task.yield()
        }
    }

    private func tool(_ name: String, _ arguments: String, _ output: String, seconds: Double) {
        session.handle(.toolStarted(name: name, arguments: arguments))
        clock.advance(.seconds(seconds))
        session.handle(.toolFinished(name: name, arguments: arguments, output: output, failed: false))
    }
}
