import Foundation
import ModelKit
import OpenRouter
import SessionKit
import Testing

@testable import TagKit

@MainActor
final class PersistentAgentFixture {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let model = ScriptedModel([AssistantMessage(text: "continued")])

    deinit { try? FileManager.default.removeItem(at: directory) }

    func prepare(tools: [ToolDefinition] = []) async throws -> (SQLiteSessionStore, SessionSummary) {
        let store = try await SQLiteSessionStore.open(directory: directory)
        let context = SessionContext(
            prompt: SystemPrompt.render(tools: tools, environment: .fake, model: model.active.description.name),
            model: model.entry.ref, effort: model.active.effort)
        let summary = try await store.create(workspace: "/work/tag", context: context)
        return (store, summary)
    }

    func agent(journal: AgentJournal, terminal: Terminal, tools: [ToolDefinition] = []) -> Agent {
        Agent(
            model: { self.model.active }, tools: tools, environment: .fake,
            now: { Date(timeIntervalSince1970: 1_792_497_600) },
            journal: journal, output: terminal.record,
            input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
    }
}

@MainActor
struct PersistentAgentTests {
    @Test func duplicateToolCallIDsNeverPoisonHistoryOrRunEffects() async throws {
        let fixture = PersistentAgentFixture()
        let (store, summary) = try await fixture.prepare()
        let call = ToolCall(id: "duplicate", name: "write", arguments: "{}")
        fixture.model.replies = [AssistantMessage(toolCalls: [call, call])]
        let calls = ToolCallCounter()
        let tool = ToolDefinition(name: "write", description: "effect", parameters: [:]) { _ in await calls.run() }
        let terminal = Terminal(["do it"])
        try await fixture.agent(
            journal: AgentJournal(store: store, snapshot: try await store.load(summary.id)),
            terminal: terminal, tools: [tool]
        ).run()
        #expect(await calls.invocations == 0)
        #expect(
            try await store.entries(summary.id).allSatisfy { if case .assistant = $0.event { false } else { true } })
        await #expect(throws: Never.self) { _ = try await store.recover(summary.id) }
    }

    @Test func cancellingInferenceLeavesRecoveryToDescribeTheInterruption() async throws {
        let fixture = PersistentAgentFixture()
        let (store, summary) = try await fixture.prepare()
        fixture.model.failure = CancellationError()
        let terminal = Terminal(["ask"])
        await #expect(throws: CancellationError.self) {
            try await fixture.agent(
                journal: AgentJournal(store: store, snapshot: try await store.load(summary.id)), terminal: terminal
            ).run()
        }
        #expect(try await store.entries(summary.id).last?.event == .inferenceStarted)
        let recovered = try await store.recover(summary.id)
        #expect(
            recovered.entries.contains {
                if case .failure(let failure) = $0.event { failure.message.contains("interrupted") } else { false }
            })
    }

    @Test func reopeningWaitsWithoutCallingTheModelAndPreservesUsage() async throws {
        let fixture = PersistentAgentFixture()
        let (store, summary) = try await fixture.prepare()
        try await store.append(
            summary.id,
            event: .assistant(
                SessionAssistant(
                    message: AssistantMessage(text: "saved"), usage: Usage(inputTokens: 3, outputTokens: 2, cost: 0.5)))
        )
        let terminal = Terminal([])
        let journal = AgentJournal(store: store, snapshot: try await store.load(summary.id))
        try await fixture.agent(journal: journal, terminal: terminal).run()
        #expect(fixture.model.conversations.isEmpty)
        guard case .status(let line) = terminal.events.first else {
            Issue.record("Restoration must announce the saved session metrics")
            return
        }
        #expect(line.cost == 0.5)
        #expect(line.contextTokens == 5)
        #expect(line.usage == Usage(inputTokens: 3, outputTokens: 2, cost: 0.5))
        #expect(try await store.entries(summary.id).count == 2)
    }

    @Test func continuationKeepsDatedHistoryReplayAndProviderID() async throws {
        let fixture = PersistentAgentFixture()
        let (store, summary) = try await fixture.prepare()
        let old = SessionUser(
            raw: "previous", message: "exact previous date annotation", date: "2026-10-20", references: [])
        try await store.append(summary.id, event: .user(old))
        let assistant = AssistantMessage(
            text: "saved", reasoning: "retained",
            replay: WireFormat.allCases.map {
                ReplayItem(format: $0, payload: ["opaque": "preserve exactly", "nested": [1, nil, true]])
            })
        try await store.append(summary.id, event: .assistant(SessionAssistant(message: assistant, usage: nil)))
        let input = PendingInput(text: "continue", references: [])
        try await store.accept(summary.id, input: input)
        let terminal = Terminal([])
        terminal.inputs = [.stored(input)]
        let journal = AgentJournal(store: store, snapshot: try await store.load(summary.id))
        try await fixture.agent(journal: journal, terminal: terminal).run()
        #expect(
            fixture.model.conversations == [
                [
                    .system(summary.context.prompt), .user(old.message), .assistant(assistant), .user("continue"),
                ]
            ])
        #expect(fixture.model.options.first?.sessionID == summary.providerSessionID)
        #expect(try await store.pending(summary.id).isEmpty)
    }

    @Test func theToolStartIsDurableBeforeItsSideEffect() async throws {
        let fixture = PersistentAgentFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory)
        let call = ToolCall(id: "write", name: "write", arguments: "{}")
        let summary = try await store.create(
            workspace: "/work/tag",
            context: SessionContext(
                prompt: "old", model: fixture.model.entry.ref, effort: nil))
        let tool = ToolDefinition(name: "write", description: "test side effect", parameters: [:]) { _ in
            let latest = try await store.entries(summary.id).last?.event
            #expect(latest == .toolStarted(call))
            return "changed"
        }
        fixture.model.replies = [AssistantMessage(toolCalls: [call]), AssistantMessage(text: "done")]
        let journal = AgentJournal(store: store, snapshot: try await store.load(summary.id))
        let terminal = Terminal(["do it"])
        try await fixture.agent(journal: journal, terminal: terminal, tools: [tool]).run()
        let events = try await store.entries(summary.id).map(\.event)
        let results = events.compactMap { event -> String? in
            if case .toolFinished(let result) = event { return result.output }
            return nil
        }
        #expect(results == ["changed"])
        #expect(fixture.model.conversations.count == 2)
        #expect(fixture.model.conversations[1].last == .tool(callID: "write", name: "write", content: "changed"))
    }

    @Test(arguments: ["inference", "assistant", "start", "result"])
    func failingToSaveAJournalBoundaryStopsSubsequentExternalWork(boundary: String) async throws {
        let fixture = PersistentAgentFixture()
        let (store, summary) = try await fixture.prepare()
        let failedStore = RejectAssistantStore(base: store, boundary: boundary)
        fixture.model.replies = [
            AssistantMessage(toolCalls: [
                ToolCall(id: "first", name: "write", arguments: "{}"),
                ToolCall(id: "second", name: "write", arguments: "{}"),
            ])
        ]
        let calls = ToolCallCounter()
        let tool = ToolDefinition(name: "write", description: "side effect", parameters: [:]) { _ in await calls.run() }
        let journal = AgentJournal(store: failedStore, snapshot: try await store.load(summary.id))
        let terminal = Terminal(["do it"])
        await #expect(throws: SessionError.invalidEvent) {
            try await fixture.agent(journal: journal, terminal: terminal, tools: [tool]).run()
        }
        #expect(await calls.invocations == (boundary == "result" ? 1 : 0))
        #expect(fixture.model.conversations.count == (boundary == "inference" ? 0 : 1))
        let entries = try await store.entries(summary.id)
        #expect(!entries.contains { if case .toolFinished = $0.event { true } else { false } })
    }

    @Test func anUpgradedTrustedPromptDiscardsOldUsageWithoutDiscardingHistory() async throws {
        let fixture = PersistentAgentFixture()
        let (store, summary) = try await fixture.prepare()
        var oldContext = summary.context
        oldContext.prompt = "historical policy"
        try await store.append(summary.id, event: .context(oldContext))
        let oldMessage = String(repeating: "old exact dated message ", count: 500)
        try await store.append(
            summary.id, event: .user(SessionUser(raw: "old", message: oldMessage, date: "yesterday", references: [])))
        try await store.append(
            summary.id,
            event: .assistant(
                SessionAssistant(
                    message: AssistantMessage(text: "old answer"),
                    usage: Usage(inputTokens: 1, outputTokens: 1, cost: 0.5, cachedInputTokens: 1))))
        let snapshot = try await store.load(summary.id)
        let state = ConversationState(
            active: fixture.model.active, prompt: { _ in summary.context.prompt }, snapshot: snapshot)
        #expect(state.latestUsage == nil)
        #expect(state.cost == 0.5)
        #expect(
            state.conversation == [
                .system(summary.context.prompt), .user(oldMessage), .assistant(AssistantMessage(text: "old answer")),
            ])
        let terminal = Terminal(["continue"])
        await #expect(throws: Never.self) {
            try await fixture.agent(journal: AgentJournal(store: store, snapshot: snapshot), terminal: terminal).run()
        }
        #expect(fixture.model.conversations.first?.contains(.user(oldMessage)) == true)
        #expect(fixture.model.conversations.first?.first == .system(summary.context.prompt))
        #expect(try await store.entries(summary.id).contains { $0.event == .context(summary.context) })
    }
}

private actor ToolCallCounter {
    private(set) var invocations = 0
    func run() -> String {
        invocations += 1
        return "changed"
    }
}

private struct RejectAssistantStore: SessionStore {
    let base: SQLiteSessionStore
    let boundary: String

    func load(_ id: UUID) async throws -> SessionSnapshot { try await base.load(id) }
    func accept(_ id: UUID, input: PendingInput) async throws { try await base.accept(id, input: input) }
    func consume(_ id: UUID, inputID: UUID, user: SessionUser) async throws {
        try await base.consume(id, inputID: inputID, user: user)
    }

    func append(_ id: UUID, event: SessionEvent) async throws {
        switch (boundary, event) {
        case ("inference", .inferenceStarted), ("assistant", .assistant), ("start", .toolStarted),
            ("result", .toolFinished):
            throw SessionError.invalidEvent
        default: break
        }
        try await base.append(id, event: event)
    }
}
