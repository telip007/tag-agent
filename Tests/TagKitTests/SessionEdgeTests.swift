import Foundation
import ModelKit
import SessionKit
import Testing

@testable import Stipple
@testable import TagKit

@MainActor
struct SessionEdgeTests {
    @Test func providerContextRejectionPreservesCompleteInputAndOffersRecovery() async throws {
        let fixture = ControllerFixture()
        let entry = ModelEntry(
            ref: Models.codex.ref, name: "Small", contextLength: 4000, pricing: .free, format: .responses)
        let requests = ContextRequests()
        let controller = try await contextController(fixture: fixture, entry: entry, requests: requests)
        let store = controller.store
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        let source = SessionCitation(
            sessionID: UUID(), title: "source", sequence: 1, role: "assistant", timestamp: Date())
        controller.draft.references = [
            SessionReference(source: source, text: String(repeating: "evidence ", count: 900))
        ]
        let references = controller.draft.references
        let runner = Task { await controller.run() }
        defer { runner.cancel() }
        for _ in 0..<200 where !controller.session.isWaitingForInput { try await Task.sleep(for: .milliseconds(5)) }
        try await controller.submit("compare")
        for _ in 0..<200
        where !controller.session.blocks.contains(where: {
            if case .failure = $0.content { true } else { false }
        }) { try await Task.sleep(for: .milliseconds(5)) }
        let pending = try await store.pending(id)
        #expect(pending.isEmpty)
        #expect(await requests.conversations.count == 1)
        #expect(controller.pauseReason == nil)
        try await assertRejectedInput(id, controller: controller, references: references)
        try await controller.close()
        await runner.value
    }

    @Test func aModelChoiceIsSavedWithoutRequiringAnInference() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        try await controller.selection.select(Models.kimi, effort: nil)
        try await controller.modelChosen()
        #expect(try await controller.store.summary(id).context.model == Models.kimi.ref)
        try await controller.close()
        let reopened = try await fixture.controller()
        try await reopened.open(.continueLast)
        #expect(reopened.selection.current?.entry.ref == Models.kimi.ref)
        try await reopened.close()
    }

    @Test func cleanExitSavesADeferredModelChoice() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        try await controller.selection.select(Models.kimi, effort: nil)
        try await controller.close()
        #expect(try await controller.store.summary(id).context.model == Models.kimi.ref)
    }

    @Test func openingLargeHistoryWaitsForInputAndStartingANewSessionStillWorks() async throws {
        let fixture = ControllerFixture()
        let entry = ModelEntry(
            ref: Models.codex.ref, name: "Small", contextLength: 100, pricing: .free, format: .responses)
        let selection = ModelSelection(
            registry: ProviderRegistry(providers: [FakeProvider(id: .codex, entries: [entry])]),
            settings: SettingsStore(directory: fixture.directory),
            credentials: CredentialStore(directory: fixture.directory, environment: [:]))
        try await selection.select(entry, effort: nil)
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let controller = SessionController(
            store: store, selection: selection,
            environment: SessionEnvironment(
                workingDirectory: fixture.directory, operatingSystem: "test", architecture: "test", isMacOS: true,
                shell: "test", isGitRepository: false), tools: [])
        try await controller.open(.new)
        let runner = Task { await controller.run() }
        defer { runner.cancel() }
        for _ in 0..<200 where !controller.session.isWaitingForInput { try await Task.sleep(for: .milliseconds(5)) }
        #expect(controller.pauseReason == nil)
        #expect(controller.session.isWaitingForInput)
        #expect(!controller.isBusy)
        let previous = controller.active?.id
        try await controller.newSession()
        #expect(controller.active?.id != previous)
        try await controller.close()
        await runner.value
    }

    @Test func repeatedBackspaceEditsSearchImmediately() async throws {
        let fixture = ControllerFixture()
        let flow = SessionFlow(controller: try await fixture.controller())
        await flow.open()
        flow.type("abc")
        _ = flow.handle(KeyPress(key: .backspace))
        _ = flow.handle(KeyPress(key: .backspace))
        #expect(flow.query == "a")
        flow.close()
    }

    @Test func directModelChoiceRunsTheContinuationCallback() async {
        let selection = makeSelection()
        let flow = ModelFlow(selection: selection)
        var chosen = false
        flow.onChosen = { chosen = true }
        await flow.run(.switchTo(Models.codex.ref.description))
        #expect(chosen)
        #expect(selection.current?.entry == Models.codex)
    }

    @Test func restoredHistoryIsSentWholeWhenTheProviderAcceptsIt() async throws {
        let fixture = PersistentAgentFixture()
        let (store, summary) = try await fixture.prepare()
        try await store.append(
            summary.id,
            event: .user(
                SessionUser(raw: "large", message: String(repeating: "x", count: 10_000), date: "today", references: [])
            ))
        let small = ModelEntry(
            ref: fixture.model.entry.ref, name: fixture.model.entry.name, contextLength: 8000, pricing: .free,
            format: .responses)
        let active = ActiveModel(entry: small, chatModel: fixture.model, effort: nil)
        let terminal = Terminal(["continue"])
        let agent = Agent(
            model: { active }, environment: .fake,
            journal: AgentJournal(store: store, snapshot: try await store.load(summary.id)), output: terminal.record,
            input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        await #expect(throws: Never.self) { try await agent.run() }
        #expect(fixture.model.conversations.count == 1)
        #expect(fixture.model.conversations.first?.contains(.user(String(repeating: "x", count: 10_000))) == true)
        #expect(
            try await store.entries(summary.id).contains {
                if case .user(let user) = $0.event { user.message.utf8.count == 10_000 } else { false }
            })
    }

    private func assertRejectedInput(
        _ id: UUID, controller: SessionController, references: [SessionReference]
    ) async throws {
        let store = controller.store
        #expect(
            try await store.entries(id).contains {
                if case .user(let user) = $0.event {
                    user.raw == "compare" && user.references == references
                        && user.message.contains(SessionReferences.render(references))
                } else {
                    false
                }
            })
        #expect(
            controller.session.blocks.contains {
                if case .failure(_, let recovery) = $0.content {
                    recovery?.contains("/model") == true && recovery?.contains("/new") == true
                } else {
                    false
                }
            })
    }

    private func contextController(
        fixture: ControllerFixture, entry: ModelEntry, requests: ContextRequests
    ) async throws -> SessionController {
        let selection = ModelSelection(
            registry: ProviderRegistry(providers: [ContextTestProvider(entry: entry, requests: requests)]),
            settings: SettingsStore(directory: fixture.directory),
            credentials: CredentialStore(directory: fixture.directory, environment: [:]))
        try await selection.select(entry, effort: nil)
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        return SessionController(
            store: store, selection: selection,
            environment: SessionEnvironment(
                workingDirectory: fixture.directory, operatingSystem: "test", architecture: "test", isMacOS: true,
                shell: "test", isGitRepository: false), tools: [])
    }
}

private actor ContextRequests {
    private(set) var conversations: [[Message]] = []
    func record(_ conversation: [Message]) { conversations.append(conversation) }
}

private struct ContextTestProvider: Provider {
    let entry: ModelEntry
    let requests: ContextRequests
    let id = ProviderID.codex
    let connectMethod = ConnectMethod.browser
    func isConnected() -> Bool { true }
    func models() -> [ModelEntry] { [entry] }
    func chatModel(for entry: ModelEntry) -> any ModelKit.ChatModel { ContextTestModel(requests: requests) }
}

private struct ContextTestModel: ModelKit.ChatModel, Sendable {
    let requests: ContextRequests
    func reply(
        to conversation: [Message], tools: [ToolSpec], options: ReplyOptions, onDelta: (ReplyDelta) -> Void
    ) async throws -> ModelReply {
        await requests.record(conversation)
        throw ProviderError.http(.codex, status: 400, detail: "context_length_exceeded")
    }
}
