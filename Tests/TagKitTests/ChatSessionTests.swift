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

    @Test func firstStatusAddsTheBanner() {
        session.handle(.status(status()))
        session.handle(.status(status()))

        #expect(session.transcript.map(\.content) == [.banner(model: "Scripted Model", folder: "/work/tag")])
        #expect(session.status == status())
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

    @Test func slowToolsShowTheirDuration() {
        session.handle(.toolStarted(name: "read_file", arguments: #"{"path":"a.swift"}"#))
        clock.advance(.milliseconds(300))
        session.handle(.toolFinished(name: "read_file", arguments: #"{"path":"a.swift"}"#, failed: false))
        session.handle(.toolStarted(name: "bash", arguments: #"{"command":"make"}"#))
        clock.advance(.seconds(4))
        session.handle(.toolFinished(name: "bash", arguments: #"{"command":"make"}"#, failed: true))

        #expect(
            session.transcript.map(\.content) == [
                .tool(name: "read_file", summary: "a.swift", failed: false, duration: nil),
                .tool(name: "bash", summary: "make", failed: true, duration: .seconds(4)),
            ]
        )
    }

    @Test func eachTurnEndsWithASummary() async {
        session.handle(.status(status()))
        session.submit("Go")
        _ = await session.nextMessage()
        session.handle(.toolStarted(name: "echo", arguments: "{}"))
        session.handle(.toolFinished(name: "echo", arguments: "{}", failed: false))
        session.handle(.reply("Done."))
        clock.advance(.milliseconds(4_100))
        session.handle(.status(status(cost: 0.0031)))

        #expect(session.transcript.last?.content == .turnSummary("1 tool · 4.1s · $0.0031"))

        session.submit("Again")
        _ = await session.nextMessage()
        session.handle(.status(status(cost: 0.0041)))
        #expect(session.transcript.last?.content == .turnSummary("0.0s · $0.001"))
    }

    @Test func toolCountIsPlural() async {
        session.submit("Go")
        _ = await session.nextMessage()
        for _ in 0..<2 {
            session.handle(.toolStarted(name: "echo", arguments: "{}"))
            session.handle(.toolFinished(name: "echo", arguments: "{}", failed: false))
        }
        session.handle(.status(status()))

        #expect(session.transcript.last?.content == .turnSummary("2 tools · 0.0s · $0.00"))
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
