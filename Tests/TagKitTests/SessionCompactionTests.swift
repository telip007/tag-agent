import Foundation
import ModelKit
import SessionKit
import Testing

@testable import Stipple
@testable import TagKit

@MainActor
struct SessionCompactionTests {
    @Test func explicitCompactionPreservesDraftQueueAndCanonicalHistory() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        for index in 1...12 {
            try await controller.store.append(
                id,
                event: .assistant(
                    SessionAssistant(
                        message: AssistantMessage(text: String(repeating: "reply \(index) ", count: 150)), usage: nil)))
        }
        controller.draft = SessionDraft(text: "unsent", references: [])
        let pending = PendingInput(text: "review later", references: [])
        try await controller.store.accept(id, input: pending)
        let before = try await controller.store.entries(id)
        try await controller.setCompaction(true)
        #expect(controller.active?.contextProjection != nil)
        #expect(controller.draft.text == "unsent")
        #expect(controller.pendingForReview == [pending])
        #expect(Array(try await controller.store.entries(id).prefix(before.count)) == before)
        #expect(try await controller.store.pending(id) == [pending])
        try await controller.setCompaction(false)
        #expect(controller.active?.contextProjection == nil)
        #expect(controller.draft.text == "unsent")
        try await controller.close()
    }

    @Test func localCommandChangesTheRenderedStateWithoutBecomingModelInput() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        for index in 1...12 {
            try await controller.store.append(
                id,
                event: .assistant(
                    SessionAssistant(
                        message: AssistantMessage(text: String(repeating: "reply \(index) ", count: 150)), usage: nil)))
        }
        let workspace = DurableWorkspace(controller: controller)
        defer { workspace.stop() }
        await workspace.settle { controller.session.isWaitingForInput }
        await workspace.type("/compact\r") {
            controller.active?.contextProjection != nil && workspace.screen.contains("Context compacted")
        }
        #expect(workspace.screen.contains("Context compacted"))
        #expect(workspace.screen.contains("/compact off"))
        await workspace.type("/compact off\r") {
            controller.active?.contextProjection == nil && !controller.isTransitioning
        }
        #expect(controller.active?.contextProjection == nil)
        #expect(
            try await controller.store.entries(id).allSatisfy {
                if case .user(let value) = $0.event { return !value.raw.contains("/compact") }
                return true
            })
        try await controller.close()
    }
}

extension SessionCompactionTests {
    @Test func compactionCannotInterruptAnActiveTaskOrModifyAReadOnlySession() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        controller.agentTask = Task { try? await Task.sleep(for: .seconds(60)) }
        let before = try await controller.store.entries(id)
        await #expect(throws: SessionControlError.self) { try await controller.setCompaction(true) }
        #expect(controller.agentTask != nil)
        #expect(try await controller.store.entries(id) == before)
        await controller.stopAgent()
        controller.readOnlyReason = "Read-only inspection"
        await #expect(throws: SessionControlError.self) { try await controller.setCompaction(true) }
        #expect(try await controller.store.entries(id) == before)
        controller.readOnlyReason = nil
        try await controller.close()
    }
}
