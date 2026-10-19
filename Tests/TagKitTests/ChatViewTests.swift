import Foundation
import Testing

@testable import Stipple
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
    private func block(_ content: TranscriptBlock.Content, expanded: Bool = false, selected: Bool = false) -> String {
        plainText(
            BlockView(block: TranscriptBlock(id: 0, content: content), isExpanded: expanded, isSelected: selected))
    }

    private func workspace(width: Int = 100, height: Int = 24, configure: (ChatSession) -> Void = { _ in }) -> String {
        let session = ChatSession()
        configure(session)
        let agent = Terminal([]).agent(model: ScriptedModel([]))
        let view = ChatView(session: session, agent: agent, copy: { _ in })
            .frame(height: height)
            .environment(\.terminalSize, Size(width: width, height: height))
        return plainText(view, width: width)
    }

    @Test func userMessagesHaveAGoldBar() {
        #expect(block(.user("Hello")) == "\n▌ Hello")
        let rendered = Stipple.renderToString(
            BlockView(block: TranscriptBlock(id: 0, content: .user("Hi")), isExpanded: false, isSelected: false))
        #expect(rendered.contains("38;2;227;179;65m▌"))
    }

    @Test func repliesAreIndentedMarkdown() {
        #expect(block(.reply("Use `make`.")) == "\n  Use make.")
    }

    @Test func reasoningShowsItsLatestLinesThenCollapses() {
        let text = "one\ntwo\nthree\nfour"
        #expect(block(.reasoning(Reasoning(text: text))) == "\n  ◌ thinking\n    …two\n    three\n    four")
        let done = Reasoning(text: text, duration: .milliseconds(3100))
        #expect(block(.reasoning(done)) == "\n  ▸ thought · 3.1s")
        #expect(
            block(.reasoning(done), expanded: true) == "\n  ▸ thought · 3.1s\n    one\n    two\n    three\n    four")
        #expect(TranscriptBlock(id: 0, content: .reasoning(done)).plainText == text)
    }

    @Test func aFinishedTrayCollapsesToOneLine() {
        let runs = [
            ToolRun(name: "read_file", summary: "a", state: .succeeded, duration: .seconds(1), output: "x"),
            ToolRun(name: "bash", summary: "make", state: .succeeded, duration: .seconds(2), output: "y"),
        ]
        #expect(block(.tools(runs)) == "\n  ▸ 2 tools · 3.0s  read_file · bash")
    }

    @Test func aRunningOrExpandedTrayListsEachCall() {
        let running = [
            ToolRun(name: "read_file", summary: "a", state: .succeeded, duration: .milliseconds(10), output: "x"),
            ToolRun(name: "bash", summary: "make", state: .running, output: ""),
        ]
        #expect(block(.tools(running)) == "\n  ✓ read_file  a\n  ◌ bash  make")

        let failed = [ToolRun(name: "bash", summary: "make", state: .failed, duration: .seconds(4), output: "1\n2")]
        #expect(block(.tools(failed), expanded: true) == "\n  ✗ bash  make  4.0s\n      1\n      2")
        #expect(Stipple.renderToString(ToolTray(runs: failed, isExpanded: false)).contains("31m▸"))
    }

    @Test func toolOutputPreviewsAreCut() {
        let output = (1...10).map(String.init).joined(separator: "\n")
        #expect(ToolTray.preview(output) == "1\n2\n3\n4\n5\n6\n… 4 more lines")
        #expect(ToolTray.preview("short") == "short")
    }

    @Test func editsAreDiffCards() {
        let edit = FileEdit(path: "a.swift", lines: [.removed("old"), .added("new")])
        let card = block(.edit(edit)).split(separator: "\n").map(String.init)
        #expect(card.count == 4)
        #expect(card[0].hasPrefix("  ┌ a.swift ─") && card[0].hasSuffix("─ +1 −1 ┐"))
        #expect(card[1].hasPrefix("  │ - old ") && card[1].hasSuffix("│"))
        #expect(card[2].hasPrefix("  │ + new ") && card[2].hasSuffix("│"))
        #expect(card[3].hasPrefix("  └─") && card[3].hasSuffix("─┘"))
        #expect(Set(card.map(\.count)).count == 1)
        let long = FileEdit(path: "b", lines: (1...10).map { FileEdit.Line.added("\($0)") })
        #expect(block(.edit(long)).contains("… 2 more lines"))
        #expect(!block(.edit(long), expanded: true).contains("more lines"))
        #expect(block(.edit(FileEdit(path: "c", lines: []))).contains("no line changes"))
    }

    @Test func theSelectedBlockIsHighlighted() {
        let rendered = Stipple.renderToString(
            BlockView(block: TranscriptBlock(id: 0, content: .reply("x")), isExpanded: false, isSelected: true))
        #expect(rendered.contains("48;2;58;62;80m"))
    }

    @Test func workspaceShowsPanesInputAndFooter() {
        let screen = workspace { session in
            session.handle(.status(status(cost: 0.0012, tokens: 2_000)))
            session.submit("queued one")
        }
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 24)
        #expect(lines[0].hasPrefix("╭─ tag ─"))
        #expect(lines[0].contains("╭─ session ─"))
        #expect(screen.contains("Scripted Model"))
        #expect(screen.contains("2k/8k tokens"))
        #expect(screen.contains("$0.0012 · 0s"))
        #expect(screen.contains("no changes yet"))
        #expect(screen.contains("· queued one"))
        #expect(lines[lines.count - 3].contains("› type ahead…"))
        #expect(lines.last == " esc browse · ^p commands · tab panel")
    }

    @Test func panelKeepsItsWidthWithAnEmptyTranscript() {
        let top = workspace().split(separator: "\n").first.map(String.init) ?? ""
        let panelStart = top.distance(
            from: top.startIndex, to: top.firstRange(of: "╭─ session")?.lowerBound ?? top.endIndex)
        #expect(panelStart == 100 - (SessionPanel.width + 4))
        #expect(workspace().contains("│ connecting…"))
    }

    @Test func aShortConversationStartsAtTheTop() {
        let lines = workspace { session in
            session.handle(.reply("first reply"))
        }
        .split(separator: "\n", omittingEmptySubsequences: false)
        // Line 0 is the top border; the reply's blank line comes before it.
        #expect(lines[2].hasPrefix("│   first reply"))
    }

    @Test func narrowTerminalsHideThePanel() {
        let screen = workspace(width: 60)
        #expect(!screen.contains("session"))
        #expect(screen.contains("╭─ tag ─"))
    }

    @Test func panelListsChangedFilesAndAGauge() {
        let screen = workspace { session in
            session.handle(.status(status(tokens: 6_000)))
            session.handle(.toolStarted(name: "edit_file", arguments: editArguments("Sources/A.swift", "a", "b\nc")))
            session.handle(
                .toolFinished(
                    name: "edit_file", arguments: editArguments("Sources/A.swift", "a", "b\nc"), output: "OK",
                    failed: false))
        }
        #expect(screen.contains("A.swift") && screen.contains("+2 −1"))
        #expect(screen.contains("75%"))
    }

    @Test func panelBeforeTheFirstStatusSaysConnecting() {
        #expect(workspace().contains("connecting…"))
    }

    @Test(arguments: [
        (Duration.zero, "0s"),
        (.seconds(42), "42s"),
        (.seconds(252), "4m 12s"),
        (.seconds(3_780), "1h 03m"),
    ])
    func formatsTheSessionClock(duration: Duration, expected: String) {
        #expect(SessionPanel.clock(duration) == expected)
    }

    @Test func panelShowsFileNamesOnly() {
        #expect(SessionPanel.fileName("Sources/TagKit/A.swift") == "A.swift")
        #expect(SessionPanel.fileName("A.swift") == "A.swift")
    }

    @Test func paletteListsTheCommands() {
        let palette = plainText(CommandPalette(selection: .constant(nil)) { _ in }, width: 60)
        for command in PaletteCommand.allCases {
            #expect(palette.contains(command.rawValue))
        }
        #expect(palette.contains("commands"))
    }

    @Test func chatViewRunsFullScreenWithTheMouseAndWithoutCtrlCExiting() {
        #expect(!ChatView.renderOptions.exitOnCtrlC)
        #expect(ChatView.renderOptions.alternateScreen)
        #expect(ChatView.renderOptions.mouseReporting)
    }

    @Test func aLongTranscriptScrollsToTheNewestBlock() {
        let session = ChatSession()
        let agent = Terminal([]).agent(model: ScriptedModel([]))
        for index in 1...20 {
            session.handle(.reply("reply \(index)"))
        }
        let view = ChatView(session: session, agent: agent, copy: { _ in })
            .frame(height: 16)
            .environment(\.terminalSize, Size(width: 100, height: 16))
        let text = plainText(view, width: 100)
        #expect(text.contains("reply 20"))
        #expect(!text.contains("reply 1\n") && !text.contains("reply 1 "))
        // The scroll indicator's thumb shows the content overflows.
        #expect(text.contains("┃"))
    }

    @Test func onlyTraysEditsAndReasoningExpand() {
        #expect(TranscriptBlock(id: 0, content: .tools([])).isExpandable)
        #expect(TranscriptBlock(id: 0, content: .reasoning(Reasoning(text: "t"))).isExpandable)
        #expect(TranscriptBlock(id: 0, content: .edit(FileEdit(path: "p", lines: []))).isExpandable)
        #expect(!TranscriptBlock(id: 0, content: .user("u")).isExpandable)
        #expect(!TranscriptBlock(id: 0, content: .reply("r")).isExpandable)
    }

    @Test func footerKeysReadAsKeyAndLabel() {
        #expect(plainText(FooterKey(key: Footer.Key(key: "tab", label: "panel") {})) == "tab panel")
    }

    @Test func blocksCopyAsPlainText() {
        #expect(TranscriptBlock(id: 0, content: .user("hi")).plainText == "hi")
        let tools = TranscriptBlock(
            id: 0, content: .tools([ToolRun(name: "bash", summary: "ls", state: .succeeded, output: "a")]))
        #expect(tools.plainText == "bash ls\na")
        let edit = TranscriptBlock(id: 0, content: .edit(FileEdit(path: "p", lines: [.removed("a"), .added("b")])))
        #expect(edit.plainText == "p\n- a\n+ b")
    }

    @Test func clipboardUsesOSC52() {
        #expect(Clipboard.sequence(for: "hi") == "\u{1B}]52;c;aGk=\u{07}")
    }
}

struct KeyMapTests {
    @Test(arguments: [
        (KeyPress(key: "c", modifiers: .control), false, PromptKey.interrupt),
        (KeyPress(key: "c", modifiers: [.control, .capsLock]), false, .interrupt),
        (KeyPress(key: "d", modifiers: .control), true, .endOfInput),
        (KeyPress(key: "p", modifiers: .control), false, .palette),
        (KeyPress(key: .upArrow), false, .older),
        (KeyPress(key: .downArrow), false, .newer),
        (KeyPress(key: .escape), true, .browse),
        (KeyPress(key: .tab), false, .togglePanel),
    ])
    func mapsPromptKeys(press: KeyPress, inputIsEmpty: Bool, expected: PromptKey) {
        #expect(PromptKey(press, inputIsEmpty: inputIsEmpty) == expected)
    }

    @Test(arguments: [
        (KeyPress(key: "d", modifiers: .control), false),
        (KeyPress(key: .escape), false),
        (KeyPress(key: "c"), true),
        (KeyPress(key: .upArrow, modifiers: .shift), true),
        (KeyPress(key: "c", modifiers: .control, phase: .up), true),
    ])
    func leavesOtherKeysToTheTextField(press: KeyPress, inputIsEmpty: Bool) {
        #expect(PromptKey(press, inputIsEmpty: inputIsEmpty) == nil)
    }

    @Test(arguments: [
        (KeyPress(key: .upArrow), BrowseKey.previous),
        (KeyPress(key: "k"), .previous),
        (KeyPress(key: .downArrow), .next),
        (KeyPress(key: "j"), .next),
        (KeyPress(key: .return), .toggle),
        (KeyPress(key: .space), .toggle),
        (KeyPress(key: "c"), .copy),
        (KeyPress(key: .escape), .leave),
        (KeyPress(key: "x"), .leave),
    ])
    func mapsBrowseKeys(press: KeyPress, expected: BrowseKey) {
        #expect(BrowseKey(press) == expected)
    }

    @Test func browseIgnoresReleasesAndOtherKeys() {
        #expect(BrowseKey(KeyPress(key: "j", phase: .up)) == nil)
        #expect(BrowseKey(KeyPress(key: .pageUp)) == nil)
    }

    @Test func typedTextComesFromPlainCharacters() {
        #expect(KeyPress(key: "x").typedText == "x")
        #expect(KeyPress(key: "x", characters: "X").typedText == "X")
        #expect(KeyPress(key: "x", modifiers: .control).typedText == nil)
        #expect(KeyPress(key: .escape).typedText == nil)
    }
}

@MainActor
struct MarkdownTests {
    private func render(_ markdown: String) -> String {
        Stipple.renderToString(Markdown.view(markdown))
    }

    @Test func codeIsTurquoiseAndBoldIsBold() {
        #expect(plainText(Markdown.view("use `make` **now**")) == "use make now")
        #expect(render("use `make`").contains("38;2;64;184;175mmake"))
        #expect(render("**now**").contains("1mnow"))
    }

    @Test func unclosedOrEmptyMarkersStayAsWritten() {
        #expect(plainText(Markdown.view("a `b and ** c")) == "a `b and ** c")
        #expect(plainText(Markdown.view("empty `` pair")) == "empty `` pair")
    }

    @Test func headingsAreBoldWithoutTheirHashes() {
        #expect(plainText(Markdown.view("## Plan\nstep")) == "Plan\nstep")
        #expect(render("# Title").contains("1mTitle"))
        #expect(plainText(Markdown.view("#hashtag")) == "#hashtag")
    }

    @Test func blankLinesKeepTheirRow() {
        #expect(plainText(Markdown.view("one\n\ntwo")) == "one\n\ntwo")
    }

    @Test func fencedCodeIsIndentedWithoutFences() {
        #expect(plainText(Markdown.view("Run:\n```sh\nmake check\n```\nDone.")) == "Run:\n  make check\nDone.")
    }
}

@MainActor
struct FooterTests {
    @Test func footerShowsWarningsAndActivity() {
        let session = ChatSession()
        session.handle(.thinking)
        let footer = plainText(
            Footer(session: session, hint: .warning("press ctrl-c again to quit"), scroll: .constant(ScrollPosition())),
            width: 60)
        #expect(footer.hasPrefix(" press ctrl-c again to quit"))
        #expect(footer.hasSuffix("⠋ thinking"))
        let keys = plainText(
            Footer(
                session: ChatSession(),
                hint: .keys([Footer.Key(key: "a", label: "b") {}, Footer.Key(key: "c", label: "d") {}]),
                scroll: .constant(ScrollPosition())))
        #expect(keys == " a b · c d")
    }

    @Test func footerOffersTheLatestBlockWhenScrolledAway() {
        let away = ScrollPosition.resting(at: 0, maxOffset: 10, byUser: true)
        let keys = Footer.Hint.keys([Footer.Key(key: "a", label: "b") {}])
        #expect(
            plainText(Footer(session: ChatSession(), hint: keys, offersLatest: true, scroll: .constant(away)))
                == " ↓ latest · a b")
        // Browsing or a pending quit keep their own hints.
        #expect(
            plainText(Footer(session: ChatSession(), hint: keys, offersLatest: false, scroll: .constant(away)))
                == " a b")
    }
}
