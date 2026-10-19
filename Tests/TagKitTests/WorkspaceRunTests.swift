import Foundation
import ModelKit
import Testing

@testable import Stipple
@testable import TagKit

/// The workspace driven through Stipple's runtime, keys and all.
@MainActor
@Suite(.serialized)
struct WorkspaceRunTests {
    @Test func typingWorksAfterAQuickSwitch() async {
        let workspace = Workspace()
        defer { workspace.stop() }
        await workspace.settle { workspace.session.isWaitingForInput }
        await workspace.type("/model go/kimi-k3\r") { workspace.selection.current != nil }
        #expect(workspace.selection.current?.entry == Models.kimi)
        await workspace.type("hello\r") { workspace.session.history.contains("hello") }
        #expect(workspace.session.history == ["hello"])
    }
}
