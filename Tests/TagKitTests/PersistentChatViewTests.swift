import Foundation
import SessionKit
import Testing

@testable import Stipple
@testable import TagKit

@MainActor
struct PersistentChatViewTests {
    @Test func durableWorkspaceShowsRecognizableSessionDraftAndReferenceState() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        controller.draft.text = "unsent parser work"
        let view = ChatView(controller: controller)
            .frame(height: 28).environment(\.terminalSize, Size(width: 100, height: 28))
        let screen = plainText(view, width: 100)
        #expect(screen.contains("New session"))
        #expect(screen.contains("unsent parser work"))
        #expect(screen.contains("^o sessions"))
        #expect(PromptKey(KeyPress(key: "o", modifiers: .control), inputIsEmpty: false) == .sessions)
        try await controller.close()
    }
}
