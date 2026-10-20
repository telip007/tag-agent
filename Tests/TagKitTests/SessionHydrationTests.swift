import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct SessionHydrationTests {
    @Test func aPausedSessionDoesNotLeaveAnUncommittedToolLookingActive() {
        let session = ChatSession()
        session.handle(.toolStarted(name: "write", arguments: "{}"))
        session.handle(.failure(message: "Could not save the result.", recovery: "Retry storage."))
        guard case .tools(let runs) = session.transcript.first?.content else {
            Issue.record("Expected a tool run")
            return
        }
        #expect(runs.first?.state == .unresolved)
        #expect(session.activity == nil)
    }

    @Test func anUnfinishedSnapshotDoesNotPretendToRunAToolLocally() async throws {
        let fixture = PersistentAgentFixture()
        let (store, summary) = try await fixture.prepare()
        let call = ToolCall(id: "unfinished", name: "read_file", arguments: "{}")
        try await store.append(
            summary.id, event: .assistant(SessionAssistant(message: AssistantMessage(toolCalls: [call]), usage: nil)))
        try await store.append(summary.id, event: .toolStarted(call))
        let before = try await store.entries(summary.id)
        let session = ChatSession()
        session.restore(SessionHydration.project(try await store.load(summary.id)))
        guard case .tools(let runs) = session.transcript.last?.content else {
            Issue.record("Expected a tool snapshot")
            return
        }
        #expect(runs.first?.state != .running)
        #expect(plainText(ToolTray(runs: runs, isExpanded: false)).contains("no saved result"))
        #expect(session.activity == nil)
        #expect(try await store.entries(summary.id) == before)
    }

    @Test func restoredViewsUseRawInputAndRetainEditsAndToolDurations() async throws {
        let fixture = PersistentAgentFixture()
        let (store, summary) = try await fixture.prepare()
        try await store.append(
            summary.id,
            event: .user(
                SessionUser(
                    raw: "show this", message: "dated provider-only prefix\nshow this", date: "2026-10-20",
                    references: [])))
        let call = ToolCall(id: "edit", name: "edit_file", arguments: editArguments("a.swift", "old", "new"))
        try await store.append(
            summary.id,
            event: .assistant(
                SessionAssistant(
                    message: AssistantMessage(text: "editing", reasoning: "checking", toolCalls: [call]), usage: nil)))
        try await store.append(summary.id, event: .toolStarted(call))
        try await store.append(
            summary.id,
            event: .toolFinished(
                SessionToolResult(
                    call: call, output: "OK", failed: false, durationMilliseconds: 1_250)))
        let projection = SessionHydration.project(try await store.load(summary.id))
        let session = ChatSession()
        session.restore(projection)
        #expect(session.history == ["show this"])
        #expect(session.transcript.first?.content == .user("show this"))
        #expect(session.files == [FileChange(path: "a.swift", added: 1, removed: 1)])
        let tools = session.transcript.compactMap { block -> [ToolRun]? in
            if case .tools(let tools) = block.content { return tools }
            return nil
        }.flatMap { $0 }
        #expect(tools.first?.duration == .milliseconds(1_250))
        #expect(tools.first?.state == .succeeded)
        #expect(session.activity == nil)
        #expect(session.queued.isEmpty)
        let reasoning = session.transcript.compactMap { block -> Reasoning? in
            if case .reasoning(let value) = block.content { return value }
            return nil
        }
        #expect(reasoning.first?.isStreaming == false)
    }

    @Test func olderPagesKeepAnActiveReplyAttachedToItsOriginalBlock() async throws {
        let fixture = PersistentAgentFixture()
        let (store, summary) = try await fixture.prepare()
        for index in 0..<150 {
            try await store.append(
                summary.id,
                event: .assistant(
                    SessionAssistant(
                        message: AssistantMessage(text: "reply \(index)"), usage: nil)))
        }
        let session = ChatSession()
        session.restore(SessionHydration.project(try await store.load(summary.id)))
        #expect(session.blocks.count == 100)
        #expect(session.blocks.first?.id == 50)
        #expect(session.hasEarlier)
        session.handle(.replyDelta("new"))
        #expect(session.loadEarlier() == 50)
        session.handle(.replyDelta(" reply"))
        #expect(session.blocks.last?.content == .reply("new reply"))
        #expect(session.blocks.last?.id == 150)
        #expect(!session.hasEarlier)
    }

    @Test func storedInputsKeepIdentityAndAreNotDrainedOnPersistentStop() async throws {
        let session = ChatSession()
        let input = PendingInput(text: "accepted", references: [])
        session.submitStored(input)
        #expect(await session.nextMessage() == .stored(input))
        #expect(session.transcript.map(\.content) == [.user("accepted")])
        session.submitStored(PendingInput(text: "keep on disk", references: []))
        session.stopDispatching()
        #expect(await session.nextMessage() == nil)
    }
}
