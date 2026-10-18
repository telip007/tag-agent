import Foundation
import Stipple
import Testing

@testable import TagKit

/// Renders `view` and strips its styling and trailing spaces, leaving what
/// the user reads.
@MainActor
func plainText(_ view: some View, width: Int = 80) -> String {
    Stipple.renderToString(view, width: width)
        .replacing(/\x1B\[[0-9;?]*[A-Za-z]/, with: "")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0.reversed().drop(while: \.isWhitespace).reversed()) }
        .joined(separator: "\n")
}

@MainActor
struct ChatViewTests {
    private func line(_ content: TranscriptEntry.Content, followsTool: Bool = false, width: Int = 80) -> String {
        var entry = TranscriptEntry(id: 0, content: content)
        entry.followsTool = followsTool
        return plainText(TranscriptLine(entry: entry), width: width)
    }

    @Test func bannerShowsTheMascotNameModelAndFolder() {
        let banner = line(
            .banner(model: ModelDescription(name: "Scripted Model", contextLength: 8_000), folder: "~/tag"))
        let rows = banner.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(rows.count == 7)
        #expect(rows.first?.isEmpty == true && rows.last?.isEmpty == true)
        #expect(rows[2].hasSuffix("   Tag Agent"))
        #expect(rows[3].hasSuffix("   Scripted Model · 8k context"))
        #expect(rows[4].hasSuffix("   ~/tag"))
        #expect(line(.banner(model: ModelDescription(name: "M"), folder: "~")).contains("   M\n"))
    }

    @Test func userMessagesSitOnATintedBand() {
        #expect(line(.user("Hello")) == "  › Hello\n")
        let rendered = Stipple.renderToString(TranscriptLine(entry: TranscriptEntry(id: 0, content: .user("Hi"))))
        #expect(rendered.contains("48;2;58;62;80m"))
    }

    @Test func repliesAndToolsLineUpWithTheMessageText() {
        #expect(line(.agent("Hi!")) == "    Hi!\n")
        #expect(line(.agent("Done."), followsTool: true) == "\n    Done.\n")
        #expect(line(.tool(name: "bash", summary: "make", failed: false, duration: nil)) == "    ▸ bash  make")
        #expect(
            line(.tool(name: "bash", summary: "make", failed: true, duration: .seconds(4))) == "    ✗ bash  make  4.0s"
        )
        #expect(line(.tool(name: "list_files", summary: "", failed: false, duration: nil)) == "    ▸ list_files")
        #expect(line(.turnSummary("1 tool · 4.1s · $0.0031")) == "    1 tool · 4.1s · $0.0031\n")
    }

    @Test func agentTextHangsIndentedWhenItWraps() {
        #expect(line(.agent("one two three four"), width: 16) == "    one two\n    three four\n")
    }

    @Test func failedToolsAreRed() {
        let entry = TranscriptEntry(id: 0, content: .tool(name: "bash", summary: "", failed: true, duration: nil))
        #expect(Stipple.renderToString(TranscriptLine(entry: entry)).contains("\u{1B}[31m✗"))
    }

    @Test func activityShowsASpinnerAndWhatIsGoingOn() {
        #expect(plainText(ActivityLine(text: "thinking", start: .now)) == "   ⠋ thinking")
        #expect(plainText(ActivityLine(text: "thinking", start: .now - .seconds(3))) == "   ⠋ thinking  3.0s")
    }

    @Test func statusBarSplitsIntoTwoSides() {
        let bar = StatusBar(status: status(cost: 0.0012, tokens: 2_000)).environment(
            \.terminalSize, Size(width: 60, height: 10))
        #expect(plainText(bar, width: 60) == "/work/tag · Scripted Model                   2k/8k · $0.0012")
    }

    @Test func statusBarDropsTheFolderThenTheModelWhenNarrow() {
        let line = status(cost: 0.0012, tokens: 2_000)
        #expect(StatusBar.fields(for: line, width: 60) == [.folder, .model, .context, .cost])
        #expect(StatusBar.fields(for: line, width: 32) == [.model, .context, .cost])
        #expect(StatusBar.fields(for: line, width: 15) == [.context, .cost])
    }

    @Test(arguments: [
        (2_000, "2k/8k", "90m"),
        (4_000, "4k/8k (50%)", "38;2;227;179;65m"),
        (7_000, "7k/8k (88%)", "31m"),
    ])
    func contextWarmsUpAsItFills(tokens: Int, text: String, color: String) {
        let bar = StatusBar(status: status(tokens: tokens))
        #expect(plainText(bar).hasSuffix("\(text) · $0.00"))
        #expect(Stipple.renderToString(bar).contains("\(color)\(text)"))
    }

    @Test func statusBarWithoutAContextWindowShowsTokensOnly() {
        let line = StatusLine(directory: URL(filePath: "/w"), model: ModelDescription(name: "M"), contextTokens: 10)
        #expect(plainText(StatusBar(status: line)).hasSuffix("10 · $0.00"))
    }

    @Test func chatViewShowsTheTranscriptInputAndStatus() async {
        let session = ChatSession()
        session.handle(.status(status()))
        session.submit("Hello")
        _ = await session.nextMessage()
        session.submit("queued")
        session.handle(.thinking)
        let agent = Terminal([]).agent(model: ScriptedModel([]))

        let screen = plainText(
            ChatView(session: session, agent: agent).environment(\.terminalSize, Size(width: 50, height: 20)), width: 50
        )

        #expect(
            screen.hasSuffix(
                """
                  › Hello

                    ⠋ thinking
                 ────────────────────────────────────────────────
                  › type ahead…
                 ────────────────────────────────────────────────
                  /work/tag · Scripted Model        0/8k · $0.00
                  1 message queued
                """
            )
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

@MainActor
struct MarkdownTests {
    private func render(_ markdown: String) -> String {
        Stipple.renderToString(Markdown.text(markdown))
    }

    @Test func codeIsTurquoiseAndBoldIsBold() {
        #expect(plainText(Markdown.text("use `make` **now**")) == "use make now")
        #expect(render("use `make`").contains("38;2;64;184;175mmake"))
        #expect(render("**now**").contains("1mnow"))
    }

    @Test func unclosedOrEmptyMarkersStayAsWritten() {
        #expect(plainText(Markdown.text("a `b and ** c")) == "a `b and ** c")
        #expect(plainText(Markdown.text("empty `` pair")) == "empty `` pair")
    }

    @Test func headingsAreBoldWithoutTheirHashes() {
        #expect(plainText(Markdown.text("## Plan\nstep")) == "Plan\nstep")
        #expect(render("# Title").contains("1mTitle"))
        #expect(plainText(Markdown.text("#hashtag")) == "#hashtag")
    }

    @Test func fencedCodeIsIndentedWithoutFences() {
        #expect(plainText(Markdown.text("Run:\n```sh\nmake check\n```\nDone.")) == "Run:\n  make check\nDone.")
    }
}

@MainActor
struct PixelArtTests {
    private let red = Color.red
    private let blue = Color.blue

    private func render(_ rows: [String]) -> [String] {
        PixelArt(rows: rows, palette: ["r": red, "b": blue]).lines.map { Stipple.renderToString($0) }
    }

    @Test func stacksTwoPixelRowsPerLine() {
        let lines = render(["r.r.", "r..b"])
        #expect(lines.count == 1)
        #expect(plainText(PixelArt(rows: ["r.r.", "r..b"], palette: ["r": red, "b": blue]).lines[0]) == "█ ▀▄")
    }

    @Test func twoColoursShareACellAsForegroundAndBackground() {
        let line = render(["r", "b"])[0]
        #expect(line.contains("▀"))
        #expect(line.contains("31"))
        #expect(line.contains("44"))
    }

    @Test func padsShortRowsAndAnOddLastRow() {
        let art = PixelArt(rows: ["rr", "r", "r"], palette: ["r": red])
        #expect(art.lines.map { plainText($0) } == ["█▀", "▀"])
    }

    @Test(arguments: [Mascot.turban, Mascot.fez])
    func mascotsUseOnlyTheirPalette(mascot: PixelArt) {
        let used = Set(mascot.rows.joined()).subtracting(["."])
        #expect(used.isSubset(of: Set(mascot.palette.keys)))
        #expect(mascot.lines.count == 5)
    }
}
