import Foundation
import Testing

@testable import TagKit

/// A clock the test moves by hand.
@MainActor
final class ManualClock {
    var instant = ContinuousClock.now

    func advance(_ duration: Duration) {
        instant += duration
    }
}

@MainActor
func status(cost: Double = 0, tokens: Int = 0) -> StatusLine {
    StatusLine(
        directory: URL(filePath: "/work/tag", directoryHint: .isDirectory),
        model: ModelDescription(name: "Scripted Model", contextLength: 8_000),
        contextTokens: tokens,
        cost: cost,
    )
}

/// `edit_file` arguments replacing `old` with `new` in `path`.
func editArguments(_ path: String, _ old: String, _ new: String) -> String {
    let object = ["path": path, "old_str": old, "new_str": new]
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    return String(bytes: data, encoding: .utf8) ?? ""
}

@MainActor
struct ChatSessionTests {
    let clock = ManualClock()
    let session: ChatSession

    init() {
        let clock = clock
        session = ChatSession(now: { clock.instant })
    }

    /// Waits until the agent's side is blocked in `nextMessage()`.
    private func waitForInputRequest() async {
        while !session.isWaitingForInput {
            await Task.yield()
        }
    }

    private func runTool(_ name: String, _ arguments: String = "{}", output: String = "ok", failed: Bool = false) {
        session.handle(.toolStarted(name: name, arguments: arguments))
        session.handle(.toolFinished(name: name, arguments: arguments, output: output, failed: failed))
    }

    @Test func statusIsKeptForThePanel() {
        session.handle(.status(status(cost: 0.5)))
        #expect(session.status == status(cost: 0.5))
        #expect(session.transcript.isEmpty)
    }

    @Test func submittedMessageReachesTheWaitingAgent() async {
        let reply = Task { await session.nextMessage() }
        await waitForInputRequest()

        #expect(session.submit("Hello"))
        #expect(await reply.value == "Hello")
        #expect(!session.isWaitingForInput)
        #expect(session.transcript.map(\.content) == [.user("Hello")])
        #expect(session.history == ["Hello"])
    }

    @Test func blankMessagesAreIgnored() {
        #expect(!session.submit("  \n"))
        #expect(session.history.isEmpty)
        #expect(session.queued.isEmpty)
    }

    @Test func messagesTypedAheadWaitInTheQueue() async {
        session.submit("first")
        session.submit("second")
        #expect(session.queued == ["first", "second"])
        // Queued messages join the transcript only when the agent takes them.
        #expect(session.transcript.isEmpty)

        #expect(await session.nextMessage() == "first")
        #expect(session.queued == ["second"])
        #expect(session.transcript.map(\.content) == [.user("first")])
    }

    @Test func endingReleasesTheWaitingAgent() async {
        let reply = Task { await session.nextMessage() }
        await waitForInputRequest()
        session.end()

        #expect(await reply.value == nil)
        #expect(await session.nextMessage() == nil)
    }

    @Test func cancellingTheAgentEndsTheSession() async {
        let reply = Task { await session.nextMessage() }
        await waitForInputRequest()
        reply.cancel()

        #expect(await reply.value == nil)
        #expect(await session.nextMessage() == nil)
    }

    @Test func activityFollowsTheAgent() {
        session.handle(.thinking)
        #expect(session.activity == "thinking")
        #expect(session.activityStart == clock.instant)

        session.handle(.toolStarted(name: "bash", arguments: #"{"command":"swift build"}"#))
        #expect(session.activity == "bash  swift build")

        session.handle(.status(status()))
        #expect(session.activity == nil)
        #expect(session.activityStart == nil)
    }

    @Test func toolCallsBetweenRepliesShareATray() {
        session.handle(.toolStarted(name: "read_file", arguments: #"{"path":"a.swift"}"#))
        #expect(
            session.transcript.map(\.content) == [
                .tools([ToolRun(name: "read_file", summary: "a.swift", state: .running, output: "")])
            ]
        )
        clock.advance(.milliseconds(300))
        session.handle(
            .toolFinished(name: "read_file", arguments: #"{"path":"a.swift"}"#, output: "text", failed: false))
        session.handle(.toolStarted(name: "bash", arguments: #"{"command":"make"}"#))
        clock.advance(.seconds(4))
        session.handle(.toolFinished(name: "bash", arguments: #"{"command":"make"}"#, output: "boom", failed: true))

        let read = ToolRun(
            name: "read_file", summary: "a.swift", state: .succeeded, duration: .milliseconds(300), output: "text")
        let bash = ToolRun(name: "bash", summary: "make", state: .failed, duration: .seconds(4), output: "boom")
        #expect(session.transcript.map(\.content) == [.tools([read, bash])])
    }

    @Test func aReplyClosesTheTray() {
        runTool("echo")
        session.handle(.reply("Done."))
        runTool("echo")

        #expect(session.transcript.count == 3)
        guard case .tools(let runs) = session.transcript[2].content else {
            Issue.record("expected a tray")
            return
        }
        #expect(runs.count == 1)
    }

    @Test func deltasGrowOneReplyUntilItIsFinished() {
        session.handle(.thinking)
        session.handle(.replyDelta("Look"))
        #expect(session.activity == "writing")
        session.handle(.replyDelta("ing."))
        #expect(session.transcript.map(\.content) == [.reply("Looking.")])

        session.handle(.reply("Looking."))
        session.handle(.replyDelta("Next"))
        #expect(session.transcript.map(\.content) == [.reply("Looking."), .reply("Next")])
    }

    @Test func aStreamedReplyClosesTheTray() {
        runTool("echo")
        session.handle(.replyDelta("Done"))
        session.handle(.reply("Done."))
        runTool("echo")

        #expect(session.transcript.count == 3)
        #expect(session.transcript[1].content == .reply("Done."))
    }

    @Test func successfulEditsBecomeDiffsAndCountTowardsFiles() {
        runTool("edit_file", editArguments("a.swift", "x\nold\ny", "x\nnew\nmore\ny"))
        runTool("edit_file", editArguments("a.swift", "", "created"))
        runTool("edit_file", editArguments("b.swift", "1", "2"), failed: true)

        let edits = session.transcript.compactMap { block -> FileEdit? in
            guard case .edit(let edit) = block.content else { return nil }
            return edit
        }
        #expect(
            edits == [
                FileEdit(path: "a.swift", lines: [.removed("old"), .added("new"), .added("more")]),
                FileEdit(path: "a.swift", lines: [.added("created")]),
            ]
        )
        #expect(session.files == [FileChange(path: "a.swift", added: 3, removed: 1)])
    }

    @Test func blocksExpandAndCollapse() {
        session.toggle(3)
        #expect(session.expanded == [3])
        session.toggle(3)
        #expect(session.expanded.isEmpty)
    }

    @Test func elapsedCountsFromTheStart() {
        clock.advance(.seconds(90))
        #expect(session.elapsed == .seconds(90))
    }

    @Test(arguments: [
        (Duration.milliseconds(400), "0.4s"),
        (.milliseconds(12_340), "12.3s"),
        (.seconds(125), "2m 05s"),
        (.seconds(600), "10m 00s"),
    ])
    func formatsDurations(duration: Duration, expected: String) {
        #expect(ChatSession.seconds(duration) == expected)
    }
}

struct FileEditTests {
    @Test func trimsSharedLinesAtBothEnds() {
        #expect(FileEdit.diff(old: "a\nb\nc", new: "a\nB\nc") == [.removed("b"), .added("B")])
        #expect(FileEdit.diff(old: "", new: "x\ny") == [.added("x"), .added("y")])
        #expect(FileEdit.diff(old: "same", new: "same").isEmpty)
    }

    @Test func readsEditArguments() {
        let edit = FileEdit.from(arguments: editArguments("p.swift", "a", "b"))
        #expect(edit == FileEdit(path: "p.swift", lines: [.removed("a"), .added("b")]))
        #expect(edit?.added == 1)
        #expect(edit?.removed == 1)
        #expect(FileEdit.from(arguments: #"{"path":"p"}"#) == nil)
        #expect(FileEdit.from(arguments: "nope") == nil)
    }
}
