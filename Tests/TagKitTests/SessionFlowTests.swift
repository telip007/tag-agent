import Foundation
import ModelKit
import SessionKit
import Stipple
import Testing

@testable import TagKit

@MainActor
struct SessionFlowTests {
    @Test(arguments: [false, true])
    func referenceEscapeReturnsToItsActualOrigin(fromPicker: Bool) async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let active = try #require(controller.active)
        let source = try await controller.store.create(workspace: controller.workspace, context: active.context)
        try await controller.store.append(
            source.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "evidence"), usage: nil)))
        let flow = SessionFlow(controller: controller)
        if fromPicker { await flow.open(purpose: .reference) }
        try await flow.reference(source.id)
        #expect(flow.isOpen)
        #expect(flow.handle(KeyPress(key: .escape)))
        #expect(flow.referencePreview == nil)
        #expect(flow.isOpen == fromPicker)
        if fromPicker { #expect(!flow.rows.isEmpty) }
        flow.close()
        try await controller.close()
    }

    @Test func selfAndNoMatchReferencesNeverWidenTheSourceOrChangeTheDraft() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let active = try #require(controller.active)
        let source = try await controller.store.create(workspace: controller.workspace, context: active.context)
        try await controller.store.append(
            active.id,
            event: .assistant(SessionAssistant(message: AssistantMessage(text: "unrelated unique token"), usage: nil)))
        let flow = SessionFlow(controller: controller)
        await #expect(throws: SessionControlError.self) { try await flow.reference(active.id) }
        await #expect(throws: SessionControlError.self) {
            try await flow.reference(source.id, query: "unrelated unique token")
        }
        #expect(flow.referencePreview == nil)
        #expect(controller.draft.references.isEmpty)
        #expect(controller.active?.id == active.id)
        try await controller.close()
    }

    @Test func enterCannotOpenAnOldResultWhileTheNewQueryIsPending() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let original = try #require(controller.active)
        let other = try await controller.store.create(workspace: controller.workspace, context: original.context)
        let flow = SessionFlow(controller: controller)
        await flow.open()
        flow.highlight(other.id)
        flow.type("no matching conversation")
        await flow.activate()
        #expect(controller.active?.id == original.id)
        #expect(flow.isOpen)
        flow.close()
        try await controller.close()
    }

    @Test func searchFindsOlderSessionsAndEscapePreservesTheCurrentDraft() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let original = try #require(controller.active)
        controller.draft = SessionDraft(text: "keep this draft")
        for index in 0..<52 {
            let item = try await controller.store.create(workspace: controller.workspace, context: original.context)
            try await controller.store.rename(item.id, title: "task \(index)")
        }
        let flow = SessionFlow(controller: controller)
        await flow.open()
        #expect(flow.rows.count == 50)
        await flow.search("task 0")
        #expect(flow.rows.count == 1)
        #expect(flow.selected?.title == "task 0")
        #expect(flow.handle(KeyPress(key: .escape)))
        #expect(!flow.isOpen)
        #expect(controller.draft.text == "keep this draft")
        #expect(controller.active?.id == original.id)
        try await controller.close()
    }

    @Test func keyboardSelectionAndScopeStayStableAndReferencesNeedConfirmation() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let original = try #require(controller.active)
        let source = try await controller.store.create(workspace: controller.workspace, context: original.context)
        try await controller.store.append(
            source.id, event: .user(SessionUser(raw: "previous question", message: "q", date: "today", references: [])))
        try await controller.store.append(
            source.id,
            event: .assistant(SessionAssistant(message: AssistantMessage(text: "recognizable answer"), usage: nil)))
        #expect(try await controller.store.summary(source.id).preview == "recognizable answer")
        let flow = SessionFlow(controller: controller)
        await flow.open(purpose: .reference)
        flow.highlight(source.id)
        await flow.refresh()
        #expect(flow.selected?.id == source.id)
        #expect(flow.handle(KeyPress(key: .downArrow)))
        #expect(flow.selected?.id != source.id)
        flow.highlight(source.id)
        await flow.activate()
        #expect(flow.referencePreview?.count == 2)
        #expect(controller.draft.references.isEmpty)
        flow.attach()
        #expect(!flow.isOpen)
        #expect(controller.draft.references.last?.text == "recognizable answer")
        #expect(controller.active?.id == original.id)
        #expect(try await controller.store.entries(original.id).count == 1)
        try await controller.close()
    }
}
