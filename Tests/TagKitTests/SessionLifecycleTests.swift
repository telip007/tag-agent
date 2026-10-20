import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct SessionLifecycleTests {
    @Test func closeReleasesOwnershipEvenWhenTheOwnershipObjectOutlivesTheController() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        let retainedOwnership = try #require(controller.ownership)
        try await controller.close()
        let next = try SessionOwnership(directory: controller.store.directory, sessionID: id)
        retainedOwnership.release()
        withExtendedLifetime(retainedOwnership) {}
        #expect(throws: SessionError.sessionInUse) {
            try SessionOwnership(directory: controller.store.directory, sessionID: id)
        }
        withExtendedLifetime(next) {}
    }

    @Test func rejectedTypeAheadLeavesTheActiveRequestRunning() async throws {
        let fixture = ControllerFixture()
        let gate = ReplyGate()
        let controller = try await gatedController(fixture: fixture, gate: gate, tools: [])
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        let runner = Task { await controller.run() }
        try await waitUntil { controller.session.isWaitingForInput }
        try await controller.submit("active request")
        try await waitUntil { await gate.calls == 1 }
        let fault = try await ChildSessionProbe.start(mode: "fault-input", store: controller.store, id: id, phase: "0")
        #expect(try await fault.wait().status == 0)
        controller.draft.text = "unsaved type-ahead"
        var finished = false
        let submitting = Task {
            defer { finished = true }
            await #expect(throws: (any Error).self) { try await controller.submit("unsaved type-ahead") }
        }
        try await waitUntil {
            let cancelled = await gate.cancellationObserved
            return finished || cancelled
        }
        #expect(!(await gate.cancellationObserved))
        #expect(controller.pauseReason == nil)
        #expect(controller.isBusy)
        #expect(controller.draft.text == "unsaved type-ahead")
        await gate.release(ModelReply(message: AssistantMessage(text: "completed active request")))
        await submitting.value
        try await waitUntil { controller.session.isWaitingForInput }
        #expect(try await controller.store.pending(id).isEmpty)
        #expect(
            try await controller.store.entries(id).contains { entry in
                if case .assistant(let reply) = entry.event { return reply.message.text == "completed active request" }
                return false
            })
        let clear = try await ChildSessionProbe.start(
            mode: "clear-input-fault", store: controller.store, id: id, phase: "0")
        #expect(try await clear.wait().status == 0)
        try await controller.close()
        await runner.value
    }

    @Test func closeKeepsOwnershipUntilTheActualRequestExitsAndNeverRunsItsLateTool() async throws {
        let fixture = ControllerFixture()
        let gate = ReplyGate()
        let effects = EffectCounter()
        let tool = ToolDefinition(name: "write", description: "test effect", parameters: [:]) { _ in await effects.run()
        }
        let controller = try await gatedController(fixture: fixture, gate: gate, tools: [tool])
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        let runner = Task { await controller.run() }
        try await waitUntil { controller.session.isWaitingForInput }
        try await controller.submit("do work")
        try await waitUntil { await gate.calls == 1 }
        await #expect(throws: SessionControlError.self) { try await controller.newSession() }
        let closing = Task { try await controller.close() }
        try await waitUntil { await gate.cancellationObserved }
        #expect(throws: SessionError.sessionInUse) {
            try SessionOwnership(directory: controller.store.directory, sessionID: id)
        }
        await gate.release(
            ModelReply(message: AssistantMessage(toolCalls: [ToolCall(id: "late", name: "write", arguments: "{}")])))
        try await closing.value
        await runner.value
        #expect(await effects.calls == 0)
        let owner = try SessionOwnership(directory: controller.store.directory, sessionID: id)
        withExtendedLifetime(owner) {}
    }

    @Test func cancellingTheViewDuringASwitchStillStopsAndReleasesTheTarget() async throws {
        let fixture = ControllerFixture()
        let probe = ProbeGate()
        let controller = try await gatedController(fixture: fixture, gate: ReplyGate(), tools: [], probe: probe)
        try await controller.open(.new)
        let active = try #require(controller.active)
        let other = try await controller.store.create(workspace: controller.workspace, context: active.context)
        let runner = Task { await controller.run() }
        try await waitUntil { controller.session.isWaitingForInput }
        probe.hold = true
        let switching = Task { try await controller.switchTo(other.id) }
        try await waitUntil { probe.isWaiting }
        runner.cancel()
        probe.release()
        try await switching.value
        var released: SessionOwnership?
        for _ in 0..<200 {
            released = try? SessionOwnership(directory: controller.store.directory, sessionID: other.id)
            if released != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(released != nil)
        released = nil
        try await controller.close()
        await runner.value
    }

    @Test func concurrentRetriesLeaveOneLiveInputWaiter() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let runner = Task { await controller.run() }
        try await waitUntil { controller.session.isWaitingForInput }
        let retries = (0..<8).map { _ in
            Task { () -> Result<Void, any Error> in
                do {
                    try await controller.retry()
                    return .success(())
                } catch { return .failure(error) }
            }
        }
        for task in retries {
            if case .failure(let error) = await task.value {
                if let control = error as? SessionControlError, case .busy = control { continue }
                Issue.record("Retry failed: \(error)")
            }
        }
        for _ in 0..<200 where !controller.session.isWaitingForInput { try await Task.sleep(for: .milliseconds(5)) }
        #expect(controller.session.isWaitingForInput)
        #expect(!controller.isBusy)
        try await controller.close()
        await runner.value
    }

    private func gatedController(
        fixture: ControllerFixture, gate: ReplyGate, tools: [ToolDefinition], probe: ProbeGate? = nil
    ) async throws -> SessionController {
        let selection = ModelSelection(
            registry: ProviderRegistry(providers: [GatedProvider(gate: gate)]),
            settings: SettingsStore(directory: fixture.directory),
            credentials: CredentialStore(directory: fixture.directory, environment: [:]))
        try await selection.select(Models.codex, effort: "high")
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let environment = ProbeGate.environment(fixture.directory)
        let probe = probe ?? ProbeGate()
        return SessionController(
            store: store, selection: selection, environment: environment, tools: tools, probe: probe.probe)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await condition())
    }
}

private actor ReplyGate {
    private(set) var calls = 0
    private(set) var cancellationObserved = false
    private var waiter: CheckedContinuation<ModelReply, Never>?

    func reply() async -> ModelReply {
        calls += 1
        return await withCheckedContinuation { waiter = $0 }
    }
    func cancelled() { cancellationObserved = true }
    func release(_ reply: ModelReply) {
        waiter?.resume(returning: reply)
        waiter = nil
    }
}

private actor EffectCounter {
    private(set) var calls = 0
    func run() -> String {
        calls += 1
        return "effect"
    }
}

private struct GatedProvider: Provider {
    let gate: ReplyGate
    let id = ProviderID.codex
    let connectMethod = ConnectMethod.browser
    func isConnected() -> Bool { true }
    func models() -> [ModelEntry] { [Models.codex] }
    func chatModel(for entry: ModelEntry) -> any ModelKit.ChatModel { GatedModel(gate: gate) }
}

private struct GatedModel: ModelKit.ChatModel, Sendable {
    let gate: ReplyGate
    func reply(
        to conversation: [Message], tools: [ToolSpec], options: ReplyOptions, onDelta: (ReplyDelta) -> Void
    ) async throws -> ModelReply {
        await withTaskCancellationHandler {
            await gate.reply()
        } onCancel: {
            Task { await gate.cancelled() }
        }
    }
}

@MainActor
private final class ProbeGate {
    var hold = false
    private(set) var isWaiting = false
    private var waiter: CheckedContinuation<SessionEnvironment, Never>?
    private var directory = URL(filePath: "/")

    func probe(_ directory: URL) async -> SessionEnvironment {
        guard hold else { return Self.environment(directory) }
        self.directory = directory
        isWaiting = true
        return await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        hold = false
        isWaiting = false
        waiter?.resume(returning: Self.environment(directory))
        waiter = nil
    }
    static func environment(_ directory: URL) -> SessionEnvironment {
        SessionEnvironment(
            workingDirectory: directory, operatingSystem: "test", architecture: "test", isMacOS: true, shell: "test",
            isGitRepository: false)
    }
}
