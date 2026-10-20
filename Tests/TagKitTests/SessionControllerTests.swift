import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct SessionControllerTests {
    @Test func startupContinuationAndSwitchPreserveDraftAndQueueWithoutInference() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let first = try #require(controller.active?.id)
        controller.draft = SessionDraft(text: "first draft")
        try await controller.newSession()
        let second = try #require(controller.active?.id)
        #expect(second != first)
        controller.draft = SessionDraft(text: "second draft")
        try await controller.switchTo(first)
        #expect(controller.draft.text == "first draft")
        try await controller.close()
        let next = try await fixture.controller()
        try await next.open(.continueLast)
        #expect(next.active?.id == first)
        #expect(next.draft.text == "first draft")
        #expect(next.session.queued.isEmpty)
        #expect(try await next.store.entries(first).allSatisfy { if case .context = $0.event { true } else { false } })
        try await next.switchTo(second)
        #expect(next.draft.text == "second draft")
        try await next.close()
    }

    @Test func ownershipAndForeignWorkspaceInspectWithoutRecoveryOrDispatch() async throws {
        let fixture = ControllerFixture()
        let first = try await fixture.controller()
        try await first.open(.new)
        let id = try #require(first.active?.id)
        try await first.store.append(id, event: .inferenceStarted)
        let second = try await fixture.controller()
        try await second.open(.resume(id.uuidString))
        #expect(second.isReadOnly)
        await #expect(throws: (any Error).self) { try await second.submit("no") }
        #expect(try await second.store.entries(id).count == 2)
        try await second.close()
        try await first.close()
        let beforeInspection = try await first.store.entries(id)
        let foreign = try await fixture.controller(workspace: URL(filePath: "/work/other"))
        try await foreign.open(.resume(id.uuidString))
        #expect(foreign.isReadOnly)
        #expect(try await foreign.store.entries(id) == beforeInspection)
        try await foreign.close()
    }

    @Test func unavailableSavedModelNeedsExplicitChoiceAndAcceptedQueueWaits() async throws {
        let fixture = ControllerFixture()
        let first = try await fixture.controller()
        try await first.open(.new)
        let id = try #require(first.active?.id)
        let pending = PendingInput(text: "accepted before crash", references: [])
        try await first.store.accept(id, input: pending)
        try await first.close()
        let unavailable = try await fixture.controller(connected: false)
        try await unavailable.open(.continueLast)
        #expect(unavailable.needsModel)
        #expect(unavailable.selection.current == nil)
        #expect(unavailable.pendingForReview == [pending])
        #expect(unavailable.session.queued.isEmpty)
        await #expect(throws: (any Error).self) { try await unavailable.submit("no provider") }
        try await unavailable.close()
    }
}

@MainActor
final class ControllerFixture {
    let directory = temporaryConfigDirectory()

    deinit { try? FileManager.default.removeItem(at: directory) }

    func controller(workspace: URL? = nil, connected: Bool = true) async throws -> SessionController {
        let selection = makeSelection(directory: directory, connected: connected)
        if connected { try await selection.select(Models.codex, effort: "high") }
        let store = try await SQLiteSessionStore.open(directory: directory.appending(path: "sessions"))
        return SessionController(
            store: store, selection: selection,
            environment: SessionEnvironment(
                workingDirectory: workspace ?? directory, operatingSystem: "test", architecture: "test",
                isMacOS: true, shell: "test", isGitRepository: false), tools: [])
    }
}
