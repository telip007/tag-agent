import Foundation
import SessionKit
import Stipple
import Testing

@testable import TagKit

@MainActor
struct SessionPickerIntentTests {
    @Test func longQueriesKeepTheirEditableTailVisible() {
        let query = String(repeating: "prefix ", count: 40) + "needle tail"
        let screen = plainText(SearchLine(query: query, placeholder: "search").frame(width: 40, height: 1), width: 44)
        #expect(screen.contains("needle tail"))
    }

    @Test func longUntrustedTitlesStayOnTheBorderAndPreserveTheBody() {
        let title = "\u{1B}[2J" + String(repeating: "long title ", count: 40)
        let screen = plainText(Text("draft body").frame(height: 4).pane(title: title, isActive: false), width: 44)
        #expect(screen.contains("␛"))
        #expect(screen.contains("draft body"))
        #expect(screen.split(separator: "\n").count <= 6)
    }

    @Test func enterKeepsTheSessionHighlightedWhenTheKeyWasPressed() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let original = try #require(controller.active)
        let intended = try await controller.store.create(workspace: controller.workspace, context: original.context)
        let flow = SessionFlow(controller: controller)
        await flow.open()
        flow.highlight(intended.id)
        #expect(flow.handle(KeyPress(key: .return)))
        flow.highlight(original.id)
        for _ in 0..<200 where flow.isOpen { try await Task.sleep(for: .milliseconds(5)) }
        #expect(controller.active?.id == intended.id)
        try await controller.close()
    }

    @Test func renameKeepsItsOriginalTargetWhenTheHighlightMoves() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let original = try #require(controller.active)
        let other = try await controller.store.create(workspace: controller.workspace, context: original.context)
        let flow = SessionFlow(controller: controller)
        await flow.open()
        flow.highlight(original.id)
        flow.beginRename()
        flow.highlight(other.id)
        flow.renameText = "Renamed original"
        await flow.activate()
        #expect(try await controller.store.summary(original.id).title == "Renamed original")
        #expect(controller.active?.title == "Renamed original")
        #expect(try await controller.store.summary(other.id).title == other.title)
        flow.close()
        try await controller.close()
    }

    @Test func controlUClearsTheRenameWithoutChangingTheSearch() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let flow = SessionFlow(controller: controller)
        await flow.open()
        flow.beginRename()
        #expect(flow.handle(KeyPress(key: "u", modifiers: .control)))
        flow.type("New title")
        #expect(flow.renameText == "New title")
        #expect(flow.query.isEmpty)
        flow.close()
        try await controller.close()
    }
}
