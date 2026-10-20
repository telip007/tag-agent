import Foundation
import ModelKit
import SessionKit
import Testing

@testable import Stipple
@testable import TagKit

@MainActor
struct ContextDiagnosticsToolTests {
    @Test func modelDiagnosticsAreBoundedAndNeverArchiveTheirOwnResponses() async throws {
        let fixture = PersistentAgentFixture()
        let (store, session) = try await fixture.prepare()
        _ = try await store.saveOutput(session.id, text: "data", source: "fixture")
        let context = NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory)
        for name in ["context_stats", "context_doctor"] {
            let tool = try #require(context.tools.first { $0.name == name })
            let response = try await tool.function("{}")
            #expect(response.utf8.count <= 512)
            #expect(!response.contains(store.directory.path))
            #expect(try JSONSerialization.jsonObject(with: Data(response.utf8)) is [String: Any])
        }
        #expect(try await store.outputStatistics(session.id).outputCount == 1)
    }

    @Test(arguments: [44, 80, 120])
    func localStatsAndDoctorRenderWithoutBecomingModelInput(width: Int) async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let id = try #require(controller.active?.id)
        _ = try await controller.store.saveOutput(id, text: "data", source: "fixture")
        let workspace = DurableWorkspace(controller: controller, width: width)
        defer { workspace.stop() }
        await workspace.settle { controller.session.isWaitingForInput }
        await workspace.type("/context\r") { workspace.screen.contains("Retained: 1") }
        #expect(workspace.screen.contains("4 bytes"))
        await workspace.type("/context doctor\r") { workspace.screen.contains("Database OK") }
        #expect(workspace.screen.contains("Journal OK"))
        await workspace.type("/context off\r") { controller.contextReport == nil }
        #expect(controller.contextReport == nil)
        #expect(
            try await controller.store.entries(id).allSatisfy {
                if case .user = $0.event { return false }
                return true
            })
        try await controller.close()
    }
}
