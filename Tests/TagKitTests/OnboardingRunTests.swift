import Foundation
import ModelKit
import Testing

@testable import Stipple
@testable import TagKit

/// The onboarding driven through Stipple's runtime, keys and all.
@MainActor
@Suite(.serialized)
struct OnboardingRunTests {
    @Test func arrowsMoveThroughTheProviders() async {
        let selection = makeSelection(connected: false)
        let terminal = FakeTerminal(size: Size(width: 100, height: 30))
        var options = OnboardingView.renderOptions
        options.maxFps = 1_000
        let runtime = Runtime(view: OnboardingView(selection: selection), options: options, terminal: terminal)
        defer { runtime.exit(with: nil) }
        func screen() -> String { runtime.produceFrame().text.replacing(/\x1B\[[0-9;?]*[A-Za-z]/, with: "") }
        func settle(until condition: () -> Bool) async {
            let deadline = ContinuousClock.now + .seconds(5)
            repeat {
                try? await Task.sleep(for: .milliseconds(10))
                await runtime.settle()
            } while !condition() && ContinuousClock.now < deadline
        }
        await settle { screen().contains("get started") }
        terminal.type("\r")
        await settle { screen().contains("connect a provider") }
        let first = screen().split(separator: "\n").first { $0.contains("› ") }.map(String.init)
        terminal.type("\u{1B}[B")
        await settle { screen().split(separator: "\n").first { $0.contains("› ") }.map(String.init) != first }
        let moved = screen().split(separator: "\n").first { $0.contains("› ") }.map(String.init)
        #expect(first?.contains("ChatGPT") == true)
        #expect(moved?.contains("OpenCode Go") == true)
    }
}
