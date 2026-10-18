import Foundation
import Observation
import Synchronization
import Testing

@testable import TagKit

/// How the transcript's blocks start over (`/clear`) and change while the
/// model writes, which decides what the workspace redraws.
@MainActor
struct TranscriptBlockTests {
    let session = ChatSession()

    /// Waits until the agent's side is blocked in `nextMessage()`.
    private func waitForInputRequest() async {
        while !session.isWaitingForInput {
            await Task.yield()
        }
    }

    @Test func clearingEmptiesTheTranscriptAndTellsTheAgent() async {
        session.handle(.reply("Done."))
        session.toggle(0)
        let reply = Task { await session.nextMessage() }
        await waitForInputRequest()

        #expect(session.submit(" /clear "))
        #expect(await reply.value == .clear)
        #expect(session.transcript.isEmpty)
        // Block ids start over, so nothing may stay expanded.
        #expect(session.expanded.isEmpty)
        // The command isn't a message, so ↑ can't recall it.
        #expect(session.history.isEmpty)

        session.handle(.reply("Fresh."))
        #expect(session.transcript.map(\.content) == [.reply("Fresh.")])
    }

    @Test func aQueuedClearWaitsForTheAgent() async {
        // With the agent busy the clear is queued like a message would be.
        session.submit("/clear")
        #expect(session.queued == ["/clear"])

        #expect(await session.nextMessage() == .clear)
        #expect(session.transcript.isEmpty)
        #expect(session.queued.isEmpty)
    }

    @Test func streamingChangesItsBlockNotTheList() {
        session.handle(.replyDelta("Hel"))
        let block = session.blocks[0]
        let listChanged = Mutex(false)
        let blockChanged = Mutex(false)
        withObservationTracking {
            _ = session.blocks
        } onChange: {
            listChanged.withLock { $0 = true }
        }
        withObservationTracking {
            _ = block.content
        } onChange: {
            blockChanged.withLock { $0 = true }
        }

        // The workspace redraws only the block that grew.
        session.handle(.replyDelta("lo"))
        #expect(blockChanged.withLock { $0 })
        #expect(!listChanged.withLock { $0 })
        #expect(session.transcript.map(\.content) == [.reply("Hello")])
    }

    @Test func longReasoningIsCutToItsTailWhileStreaming() {
        let long = String(repeating: "word ", count: 1_000) + "end"
        let tail = ReasoningView.tail(of: long)
        #expect(tail.count == BlockView.reasoningLines * 400)
        #expect(tail.hasSuffix("end"))
        #expect(ReasoningView.tail(of: "short") == "short")
    }

    @Test func rowsAreEqualForTheSameBlockAndFlags() {
        let session = ChatSession()
        session.handle(.reply("a"))
        session.handle(.reply("b"))
        let first = session.blocks[0]
        let row = BlockRow(block: first, isExpanded: false, isSelected: false, isHovered: false)
        #expect(row == BlockRow(block: first, isExpanded: false, isSelected: false, isHovered: false))
        #expect(row != BlockRow(block: first, isExpanded: true, isSelected: false, isHovered: false))
        #expect(row != BlockRow(block: session.blocks[1], isExpanded: false, isSelected: false, isHovered: false))
        // A hovered row lights up only when a click would change it.
        let hovered = BlockRow(block: first, isExpanded: false, isSelected: false, isHovered: true)
        #expect(plainText(hovered) == plainText(row))
    }
}
