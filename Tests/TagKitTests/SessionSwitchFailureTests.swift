import Foundation
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct SessionSwitchFailureTests {
    @Test func failedSlashSwitchPreservesTheInstalledDestinationsDraft() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let old = try #require(controller.active)
        let other = try await controller.store.create(workspace: controller.workspace, context: old.context)
        try await controller.store.saveDraft(other.id, draft: SessionDraft(text: "saved destination draft"))
        let fault = try await ChildSessionProbe.start(
            mode: "fault-pointer", store: controller.store, id: other.id, phase: "0")
        #expect(try await fault.wait().status == 0)
        let editor = WorkspaceEditor(session: controller.session, controller: controller)
        editor.text = "/session \(other.id)"
        await editor.submit(models: ModelFlow(selection: controller.selection), sessions: nil)
        #expect(controller.active?.id == other.id)
        #expect(editor.error != nil)
        #expect(editor.text == "saved destination draft")
        #expect(controller.draft.text == "saved destination draft")
        try await controller.close()
        #expect(try await controller.store.draft(other.id).text == "saved destination draft")
    }

    @Test func aFailedContinuationPointerPausesTheTargetUntilRetrySavesIt() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let old = try #require(controller.active)
        let other = try await controller.store.create(workspace: controller.workspace, context: old.context)
        let runner = Task { await controller.run() }
        defer { runner.cancel() }
        for _ in 0..<200 where !controller.session.isWaitingForInput { try await Task.sleep(for: .milliseconds(5)) }
        let fault = try await ChildSessionProbe.start(
            mode: "fault-pointer", store: controller.store, id: other.id, phase: "0")
        #expect(try await fault.wait().status == 0)
        await #expect(throws: (any Error).self) { try await controller.switchTo(other.id) }
        #expect(controller.active?.id == other.id)
        #expect(controller.pauseReason != nil)
        await #expect(throws: SessionControlError.self) { try await controller.submit("must not queue") }
        #expect(try await controller.store.pending(other.id).isEmpty)
        let clear = try await ChildSessionProbe.start(
            mode: "clear-pointer-fault", store: controller.store, id: other.id, phase: "0")
        #expect(try await clear.wait().status == 0)
        try await controller.retry()
        for _ in 0..<200 where !controller.session.isWaitingForInput { try await Task.sleep(for: .milliseconds(5)) }
        #expect(controller.session.isWaitingForInput)
        #expect(try await controller.store.lastSession(workspace: controller.workspace)?.id == other.id)
        try await controller.close()
        await runner.value
    }
}
