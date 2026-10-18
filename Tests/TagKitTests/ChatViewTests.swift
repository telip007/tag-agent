import Foundation
import Stipple
import Testing

@testable import TagKit

/// Renders `view` and strips its styling, leaving what the user reads.
@MainActor
func plainText(_ view: some View, width: Int = 80) -> String {
    Stipple.renderToString(view, width: width)
        .replacing(/\x1B\[[0-9;?]*[A-Za-z]/, with: "")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingSuffix(while: \.isWhitespace) }
        .joined(separator: "\n")
}

extension Substring {
    fileprivate func trimmingSuffix(while predicate: (Character) -> Bool) -> String {
        var text = String(self)
        while let last = text.last, predicate(last) {
            text.removeLast()
        }
        return text
    }
}

@MainActor
struct ChatViewTests {
    private func line(_ content: TranscriptEntry.Content, width: Int = 80) -> String {
        plainText(TranscriptLine(entry: TranscriptEntry(id: 0, content: content)), width: width)
    }

    @Test func rendersEachKindOfTranscriptLine() {
        #expect(line(.banner(model: "Scripted Model", folder: "~/tag")) == " TAG   Scripted Model · ~/tag\n")
        #expect(line(.user("Hello")) == "› Hello")
        #expect(line(.agent("Hi!")) == "  Hi!")
        #expect(line(.tool(name: "bash", summary: "make", failed: false, duration: nil)) == "  ▸ bash  make")
        #expect(
            line(.tool(name: "bash", summary: "make", failed: true, duration: .seconds(4))) == "  ✗ bash  make  4.0s"
        )
        #expect(line(.tool(name: "list_files", summary: "", failed: false, duration: nil)) == "  ▸ list_files")
        #expect(line(.turnSummary("1 tool · 4.1s · $0.0031")) == "  ─ 1 tool · 4.1s · $0.0031\n")
    }

    @Test func agentTextHangsIndentedWhenItWraps() {
        #expect(line(.agent("one two three four"), width: 12) == "  one two\n  three four")
    }

    @Test func failedToolsAreRed() {
        let entry = TranscriptEntry(id: 0, content: .tool(name: "bash", summary: "", failed: true, duration: nil))
        #expect(Stipple.renderToString(TranscriptLine(entry: entry)).contains("\u{1B}[31m✗"))
    }

    @Test func activityShowsASpinnerAndWhatIsGoingOn() {
        #expect(plainText(ActivityLine(text: "thinking", start: .now)) == "  ⠋ thinking")
        #expect(plainText(ActivityLine(text: "thinking", start: .now - .seconds(3))) == "  ⠋ thinking  3.0s")
    }

    @Test func statusBarShowsAMeterAndDropsFieldsWhenNarrow() {
        let line = status(cost: 0.0012, tokens: 2_000)
        #expect(
            plainText(StatusBar(status: line, queued: 0)) == "/work/tag · Scripted Model · ▰▰▱▱▱▱▱▱ · 2k/8k · $0.0012"
        )
        #expect(StatusBar.fields(for: line, queued: 0, width: 45) == [.model, .meter, .context, .cost])
        #expect(StatusBar.fields(for: line, queued: 0, width: 30) == [.meter, .context, .cost])
        #expect(StatusBar.fields(for: line, queued: 2, width: 10) == [.context, .cost, .queued])
    }

    @Test func statusBarWithoutAContextWindowHasNoMeter() {
        let line = StatusLine(directory: URL(filePath: "/w"), model: ModelDescription(name: "M"), contextTokens: 10)
        #expect(plainText(StatusBar(status: line, queued: 1)) == "/w · M · 10 · $0.00 · 1 queued")
    }

    @Test(arguments: [
        (0, "▱▱▱▱▱▱▱▱", nil),
        (100, "▰▱▱▱▱▱▱▱", "32m▰"),
        (5_000, "▰▰▰▰▰▱▱▱", "38;2;255;176;0m▰"),
        (7_000, "▰▰▰▰▰▰▰▱", "31m▰"),
        (9_000, "▰▰▰▰▰▰▰▰", "31m▰"),
    ])
    func meterWarmsUpAsTheContextFills(tokens: Int, cells: String, colored: String?) {
        let bar = StatusBar(status: status(tokens: tokens), queued: 0)
        #expect(plainText(bar).contains(cells))
        // The filled cells' colour is the last parameter before them.
        if let colored {
            #expect(Stipple.renderToString(bar).contains(colored))
        }
    }

    @Test func chatViewShowsTheTranscriptPromptAndStatus() {
        let session = ChatSession()
        session.handle(.status(status()))
        session.submit("queued")
        session.handle(.thinking)
        let agent = Terminal([]).agent(model: ScriptedModel([]))

        let screen = plainText(ChatView(session: session, agent: agent))

        #expect(
            screen == """
                 TAG   Scripted Model · /work/tag

                  ⠋ thinking
                › type ahead…
                /work/tag · Scripted Model · ▱▱▱▱▱▱▱▱ · 0/8k · $0.00 · 1 queued
                """
        )
    }

    @Test func chatViewRunsWithoutCtrlCExiting() {
        #expect(!ChatView.renderOptions.exitOnCtrlC)
    }

    @Test(arguments: [
        (KeyPress(key: "c", modifiers: .control), false, PromptKey.interrupt),
        (KeyPress(key: "c", modifiers: [.control, .capsLock]), false, .interrupt),
        (KeyPress(key: "d", modifiers: .control), true, .endOfInput),
        (KeyPress(key: .upArrow), false, .older),
        (KeyPress(key: .downArrow), false, .newer),
    ])
    func mapsPromptKeys(press: KeyPress, inputIsEmpty: Bool, expected: PromptKey) {
        #expect(PromptKey(press, inputIsEmpty: inputIsEmpty) == expected)
    }

    @Test(arguments: [
        (KeyPress(key: "d", modifiers: .control), false),
        (KeyPress(key: "c"), true),
        (KeyPress(key: .upArrow, modifiers: .shift), true),
        (KeyPress(key: "c", modifiers: .control, phase: .up), true),
    ])
    func leavesOtherKeysToTheTextField(press: KeyPress, inputIsEmpty: Bool) {
        #expect(PromptKey(press, inputIsEmpty: inputIsEmpty) == nil)
    }
}
