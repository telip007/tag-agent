import Foundation
import ModelKit
import SessionKit
import Testing

@testable import Stipple
@testable import TagKit

@MainActor
struct SessionPickerTests {
    @Test func keyboardCanInspectTheEndOfALongReferenceBeforeAttaching() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let active = try #require(controller.active)
        let source = try await controller.store.create(workspace: controller.workspace, context: active.context)
        let text = (0..<50).map { "evidence line \($0)" }.joined(separator: "\n")
        try await controller.store.append(
            source.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: text), usage: nil)))
        let flow = SessionFlow(controller: controller)
        try await flow.reference(source.id)
        #expect(flow.handle(KeyPress(key: .end)))
        let screen = plainText(SessionPicker(state: flow, width: 80, height: 24))
        #expect(screen.contains("evidence line 49"))
        #expect(!screen.contains("evidence line 0\n"))
        #expect(controller.draft.references.isEmpty)
        try await controller.close()
    }

    @Test func wideAndNarrowLayoutsKeepConversationAndActionRecognizable() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        try await controller.store.rename(id, title: "Fix Unicode navigation 🌳 and keep the current draft")
        try await controller.store.append(
            id,
            event: .user(
                SessionUser(raw: "Where did we leave the parser?", message: "q", date: "today", references: [])))
        try await controller.store.append(
            id,
            event: .assistant(
                SessionAssistant(
                    message: AssistantMessage(text: "The parser now preserves tool calls. Next: verify recovery."),
                    usage: nil)))
        let flow = SessionFlow(controller: controller)
        flow.rowLimit = 3
        await flow.open()
        for width in [120, 80, 44] {
            let screen = plainText(SessionPicker(state: flow, width: width, height: 28), width: width)
            if let directory = ProcessInfo.processInfo.environment["TAG_SESSION_RENDER_DIR"] {
                try screen.write(
                    to: URL(filePath: directory).appending(path: "sessions-\(width).txt"), atomically: true,
                    encoding: .utf8)
            }
            #expect(screen.contains("sessions"))
            #expect(screen.contains("Fix Unicode"))
            #expect(screen.contains("current"))
            #expect(screen.contains("continue"))
            #expect(screen.contains("esc"))
            #expect(screen.contains("parser"))
            #expect(screen.split(separator: "\n").count <= 28)
        }
        try await controller.close()
    }

    @Test func emptyLoadingAndErrorStatesHaveStableHeightAndUsefulNextSteps() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        let flow = SessionFlow(controller: controller)
        await flow.open()
        let empty = plainText(SessionPicker(state: flow, width: 72, height: 24))
        #expect(empty.contains("No saved sessions"))
        #expect(empty.contains("^n new"))
        flow.isLoading = true
        let loading = plainText(SessionPicker(state: flow, width: 72, height: 24))
        #expect(loading.contains("Loading sessions"))
        flow.isLoading = false
        flow.error = "Could not search. Check storage, then reopen."
        let error = plainText(SessionPicker(state: flow, width: 72, height: 24))
        #expect(error.contains("Check storage"))
        #expect(empty.split(separator: "\n").count == loading.split(separator: "\n").count)
        #expect(empty.split(separator: "\n").count == error.split(separator: "\n").count)
    }
}
