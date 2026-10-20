import Foundation
import ModelKit
import OpenRouter
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct ConversationProjectionTests {
    @Test func requestViewPinsUsersFailuresAndCompleteReplayGroups() async throws {
        let fixture = PersistentAgentFixture()
        let (store, session) = try await fixture.prepare()
        try await user(store, session.id, "original constraint")
        let old = try await group(store, session.id, id: "old", failed: false)
        let failure = try await group(store, session.id, id: "failed", failed: true)
        try await user(store, session.id, "correction: use the new plan")
        let recent = try await group(store, session.id, id: "recent", failed: false)
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "done"), usage: nil)))
        let original = try await store.load(session.id)
        let projection = try await store.compactContext(session.id, keepRecentGroups: 2)
        let restored = try await store.load(session.id)
        var state = ConversationState(active: fixture.model.active, prompt: { $0.name }, snapshot: restored)
        #expect(state.conversation.contains(.assistant(old)))
        #expect(!state.requestConversation.contains(.assistant(old)))
        #expect(state.requestConversation.contains(.assistant(failure)))
        #expect(state.requestConversation.contains(.assistant(recent)))
        assertCompleteToolGroups(state.requestConversation)
        #expect(state.requestConversation.contains(.user("original constraint")))
        #expect(state.requestConversation.contains(.user("correction: use the new plan")))
        #expect(
            state.requestConversation.contains {
                if case .user(let value) = $0 { return value.contains(projection.archiveID ?? "missing") }
                return false
            })
        let switched = ScriptedModel([])
        switched.entry.ref = ModelRef(provider: .codex, model: "other")
        switched.entry.name = "Other model"
        state.follow(switched.active)
        #expect(state.requestConversation.first == .system("Other model"))
        #expect(state.requestConversation.contains(.assistant(recent)))
        state.conversation.append(.user("later input"))
        #expect(state.requestConversation.last == .user("later input"))
        #expect(Array(restored.entries.prefix(original.entries.count)) == original.entries)
        try await store.restoreFullContext(session.id)
        let full = ConversationState(
            active: fixture.model.active, prompt: { $0.name }, snapshot: try await store.load(session.id))
        #expect(full.requestConversation == full.conversation)
    }

    @Test func anAgentActuallyUsesTheProjectionAndDoesNotInferWhileReopening() async throws {
        let fixture = PersistentAgentFixture()
        let (store, session) = try await fixture.prepare()
        _ = try await group(store, session.id, id: "old", failed: false)
        _ = try await group(store, session.id, id: "recent", failed: false)
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "done"), usage: nil)))
        _ = try await store.compactContext(session.id, keepRecentGroups: 1)
        let snapshot = try await store.load(session.id)
        let idle = Terminal([])
        try await projectedAgent(fixture, store: store, snapshot: snapshot, terminal: idle).run()
        #expect(fixture.model.conversations.isEmpty)
        let terminal = Terminal(["continue"])
        try await projectedAgent(fixture, store: store, snapshot: snapshot, terminal: terminal).run()
        let sent = try #require(fixture.model.conversations.first)
        #expect(
            !sent.contains {
                if case .assistant(let reply) = $0 { return reply.toolCalls.contains { $0.id == "old" } }
                return false
            })
        #expect(sent.contains(.assistant(AssistantMessage(text: "done"))))
    }

    private func assertCompleteToolGroups(_ messages: [Message]) {
        let calls = Set(
            messages.flatMap {
                if case .assistant(let value) = $0 { return value.toolCalls.map(\.id) }
                return []
            })
        let results = Set(
            messages.compactMap {
                if case .tool(let id, _, _) = $0 { return id }
                return nil
            })
        #expect(calls == results)
    }

    private func projectedAgent(
        _ fixture: PersistentAgentFixture, store: SQLiteSessionStore, snapshot: SessionSnapshot, terminal: Terminal
    ) -> Agent {
        Agent(
            model: { fixture.model.active }, environment: .fake,
            journal: AgentJournal(store: store, snapshot: snapshot),
            context: NativeContext(store: store, sessionID: snapshot.summary.id, workingDirectory: fixture.directory),
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
    }

    private func user(_ store: SQLiteSessionStore, _ id: UUID, _ text: String) async throws {
        try await store.append(id, event: .user(SessionUser(raw: text, message: text, date: "date", references: [])))
    }

    private func group(
        _ store: SQLiteSessionStore, _ id: UUID, id callID: String, failed: Bool
    ) async throws -> AssistantMessage {
        let call = ToolCall(id: callID, name: "bash", arguments: "{}")
        let reply = AssistantMessage(
            text: "decision \(callID)",
            replay: [
                ReplayItem(
                    format: .responses,
                    payload: ["type": "reasoning", "encrypted_content": .string("opaque \(callID)")]),
                ReplayItem(
                    format: .anthropicMessages,
                    payload: [
                        "type": "thinking", "thinking": "readable reasoning", "signature": .string("signed \(callID)"),
                    ]),
            ],
            toolCalls: [call])
        try await store.append(id, event: .assistant(SessionAssistant(message: reply, usage: nil)))
        try await store.append(
            id,
            event: .toolFinished(
                SessionToolResult(
                    call: call, output: String(repeating: "evidence \(callID)\n", count: 200), failed: failed,
                    durationMilliseconds: nil)))
        return reply
    }
}

extension ConversationProjectionTests {
    @Test func anAgentWithoutRetrievalCapabilityKeepsTheFullHistory() async throws {
        let fixture = PersistentAgentFixture()
        let (store, session) = try await fixture.prepare()
        let old = try await group(store, session.id, id: "old", failed: false)
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "recent"), usage: nil)))
        _ = try await store.compactContext(session.id, keepRecentGroups: 1)
        let terminal = Terminal(["continue"])
        try await fixture.agent(
            journal: AgentJournal(store: store, snapshot: try await store.load(session.id)), terminal: terminal
        ).run()
        #expect(fixture.model.conversations.first?.contains(.assistant(old)) == true)
    }
}
