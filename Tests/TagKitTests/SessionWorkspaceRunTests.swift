import Foundation
import SessionKit
import Testing

@testable import Stipple
@testable import TagKit

@MainActor
@Suite(.serialized)
struct SessionWorkspaceRunTests {
    @Test(arguments: ["\u{03}", "\u{05}" + String(repeating: "\u{7F}", count: 8)])
    func clearingAReviewedInputKeepsItsAcceptedPayload(clear: String) async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        let original = PendingInput(text: "accepted", references: [])
        try await controller.store.accept(id, input: original)
        controller.pendingForReview = [original]
        try controller.reviewPending()
        let workspace = DurableWorkspace(controller: controller)
        defer { workspace.stop() }
        await workspace.type(clear) { controller.draft.text.isEmpty }
        try #require(controller.draft.text.isEmpty)
        #expect(controller.draft.pendingInputID == nil)
        await workspace.type("unrelated") { controller.draft.text == "unrelated" }
        await workspace.type("\r") { controller.draft.text.isEmpty }
        #expect(try await controller.store.pending(id).contains(original))
        try await controller.close()
    }

    @Test(arguments: [false, true])
    func aSecondQuitCanExitAfterAnUnsaveableDraft(holdAgentStop: Bool) async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        try await controller.store.saveDraft(id, draft: SessionDraft(text: "previously saved"))
        let stopGate = WorkspaceProbeGate(environment: controller.environment)
        stopGate.hold = holdAgentStop
        defer { stopGate.release() }
        if holdAgentStop { controller.agentTask = Task { _ = await stopGate.probe() } }
        let workspace = DurableWorkspace(controller: controller)
        defer { workspace.stop() }
        await workspace.settle { controller.isRunning && (!holdAgentStop || stopGate.isWaiting) }
        try #require(controller.isRunning && (!holdAgentStop || stopGate.isWaiting))
        let fault = try await ChildSessionProbe.start(
            mode: "fault-draft", store: controller.store, id: id, phase: "0")
        try #require(try await fault.wait().status == 0)
        workspace.terminal.type("\u{04}")
        await workspace.settle(timeout: .seconds(3)) { controller.pauseReason != nil }
        try #require(
            controller.pauseReason != nil,
            Comment(rawValue: workspace.diagnostics(controller: controller)))
        #expect(!controller.isClosed)
        let warning = "ctrl-d again quits without saving"
        if holdAgentStop {
            #expect(controller.isTransitioning)
            #expect(!workspace.screen.contains(warning))
        }
        stopGate.release()
        await workspace.settle(timeout: .seconds(3)) { workspace.screen.contains(warning) }
        try #require(workspace.screen.contains(warning))
        #expect(!controller.isTransitioning)
        workspace.terminal.type("\u{04}")
        await workspace.settle(timeout: .seconds(3)) { controller.isClosed }
        #expect(controller.isClosed)
        #expect(try await controller.store.draft(id).text == "previously saved")
        await controller.shutdown()
    }

    @Test(arguments: [false, true])
    func typingDuringPickerAndPaletteSwitchesBelongsOnlyToTheDestination(palette: Bool) async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let original = try #require(controller.active?.id)
        let workspace = DurableWorkspace(controller: controller)
        defer { workspace.stop() }
        await workspace.type("source draft") { controller.draft.text == "source draft" }
        let blocker = try await ChildSessionProbe.start(
            mode: "hold-input-save", store: controller.store, id: original, phase: "0")
        if palette {
            await workspace.type("\u{10}") { workspace.screen.contains("Start a new session") }
            await workspace.type(String(repeating: "\u{1B}[B", count: 8) + "\r") { controller.isTransitioning }
        } else {
            await workspace.type("\u{0F}") { workspace.screen.contains("search titles") }
            await workspace.type("\u{0E}") { controller.isTransitioning }
            await workspace.type("\u{1B}") { !workspace.screen.contains("search titles") }
        }
        try #require(controller.isTransitioning)
        await workspace.type("destination draft") { workspace.screen.contains("destination draft") }
        #expect(try await blocker.killAndWait().status == 137)
        await workspace.settle { controller.active?.id != original && !controller.isTransitioning }
        #expect(controller.draft.text == "destination draft")
        #expect(try await controller.store.draft(original).text == "source draft")
        try await controller.close()
    }

    @Test func typingDuringASlashSwitchBelongsOnlyToTheDestination() async throws {
        let fixture = ControllerFixture()
        let base = try await fixture.controller()
        let gate = WorkspaceProbeGate(environment: base.environment)
        defer { gate.release() }
        let controller = SessionController(
            store: base.store, selection: base.selection, environment: base.environment,
            tools: [], probe: { _ in await gate.probe() })
        try await controller.open(.new)
        let original = try #require(controller.active?.id)
        let workspace = DurableWorkspace(controller: controller)
        defer { workspace.stop() }
        await workspace.type("/new") { controller.draft.text == "/new" }
        gate.hold = true
        await workspace.type("\r") { gate.isWaiting }
        try #require(gate.isWaiting)
        await workspace.type("for new task") { workspace.screen.contains("for new task") }
        #expect(controller.draft.text.isEmpty)
        #expect(try await controller.store.draft(original).text.isEmpty)
        gate.release()
        await workspace.settle { controller.draft.text == "for new task" }
        #expect(controller.draft.text == "for new task")
        #expect(try await controller.store.draft(original).text.isEmpty)
        try await controller.close()
    }

    @Test func slashNewDoesNotSaveTheCommandAsTheOldSessionsDraft() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let original = try #require(controller.active?.id)
        let workspace = DurableWorkspace(controller: controller)
        defer { workspace.stop() }
        await workspace.type("/new") { controller.draft.text == "/new" }
        await workspace.type("\r") { controller.active?.id != original }
        #expect(controller.active?.id != original)
        #expect(try await controller.store.draft(original).text.isEmpty)
        try await controller.close()
    }

    @Test func typingWhileARenameSavesRemainsInTheEditor() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        let workspace = DurableWorkspace(controller: controller)
        defer { workspace.stop() }
        await workspace.type("/rename Recognizable title") { controller.draft.text == "/rename Recognizable title" }
        let blocker = try await ChildSessionProbe.start(
            mode: "hold-input-save", store: controller.store, id: id, phase: "0")
        await workspace.type("\r") { controller.draft.text.isEmpty }
        await workspace.type("next draft") { controller.draft.text.contains("next draft") }
        #expect(try await blocker.killAndWait().status == 137)
        await workspace.settle { controller.active?.title == "Recognizable title" }
        #expect(controller.draft.text == "next draft")
        #expect(workspace.screen.contains("next draft"))
        try await controller.close()
    }

    @Test func pickerKeysReturnToTheDraftAndNewSessionKeepsThePreviousDraft() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let original = try #require(controller.active?.id)
        let workspace = DurableWorkspace(controller: controller)
        defer { workspace.stop() }
        await workspace.type("unsent draft") { controller.draft.text == "unsent draft" }
        await workspace.type("\u{0F}") { workspace.screen.contains("search titles") }
        #expect(workspace.screen.contains("search titles"))
        await workspace.type("\u{1B}") { !workspace.screen.contains("search titles") }
        #expect(controller.draft.text == "unsent draft")
        await workspace.type("\u{10}") { workspace.screen.contains("Select a saved session") }
        #expect(workspace.screen.contains("Select a saved session"))
        await workspace.type("\u{1B}") { !workspace.screen.contains("Switch model") }
        await workspace.type("\u{0F}") { workspace.screen.contains("search titles") }
        await workspace.type("\u{0E}") { controller.active?.id != original }
        #expect(controller.active?.id != original)
        #expect(controller.draft.text.isEmpty)
        #expect(try await controller.store.draft(original).text == "unsent draft")
        #expect(
            try await controller.store.entries(original).allSatisfy {
                if case .context = $0.event { true } else { false }
            })
        try await controller.close()
    }

    @Test func typingDuringAStorageAcknowledgmentSurvivesAsTheNextDraft() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        let workspace = DurableWorkspace(controller: controller)
        defer { workspace.stop() }
        await workspace.type("first") { controller.draft.text == "first" }
        let blocker = try await ChildSessionProbe.start(
            mode: "hold-input-save", store: controller.store, id: id, phase: "0")
        await workspace.type("\r") { controller.isTransitioning }
        #expect(controller.isTransitioning)
        await workspace.type("next draft") { controller.draft.text.contains("next draft") }
        #expect(try await blocker.killAndWait().status == 137)
        await workspace.settle { !controller.isTransitioning }
        #expect(controller.draft.text == "next draft")
        #expect(workspace.screen.contains("next draft"))
        try await controller.close()
    }
}

@MainActor
struct DurableWorkspace {
    let terminal: FakeTerminal
    let runtime: Runtime

    init(controller: SessionController) {
        controller.selection.dismissChatGPTWelcome()
        terminal = FakeTerminal(size: Size(width: 120, height: 32))
        var options = ChatView.renderOptions
        options.maxFps = 1_000
        runtime = Runtime(view: ChatView(controller: controller), options: options, terminal: terminal)
    }

    func type(_ bytes: String, until condition: () -> Bool) async {
        terminal.type(bytes)
        await settle(until: condition)
    }

    func settle(timeout: Duration = .seconds(1), until condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        repeat {
            try? await Task.sleep(for: .milliseconds(5))
            await runtime.settle()
        } while !condition() && ContinuousClock.now < deadline
    }

    var screen: String { runtime.produceFrame().text.replacing(/\x1B\[[0-9;?]*[A-Za-z]/, with: "") }

    func diagnostics(controller: SessionController) -> String {
        return """
            transition=\(controller.isTransitioning) closed=\(controller.isClosed) \
            waiting=\(controller.session.isWaitingForInput) welcome=\(controller.selection.isChatGPTWelcomeDue) \
            loading=\(controller.selection.isLoading) draftBytes=\(controller.draft.text.utf8.count)
            """
    }

    func stop() { runtime.exit(with: nil) }
}

@MainActor
private final class WorkspaceProbeGate {
    let environment: SessionEnvironment
    var hold = false
    var isWaiting: Bool { waiter != nil }
    private var waiter: CheckedContinuation<Void, Never>?

    init(environment: SessionEnvironment) { self.environment = environment }
    func probe() async -> SessionEnvironment {
        if hold { await withCheckedContinuation { waiter = $0 } }
        return environment
    }
    func release() {
        hold = false
        waiter?.resume()
        waiter = nil
    }
}
