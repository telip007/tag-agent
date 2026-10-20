import ArgumentParser
import Foundation
import SessionKit
import Testing

@testable import Tag
@testable import TagKit

@MainActor
struct SessionStartupTests {
    @Test(arguments: [[], ["--new"]])
    func aNewLaunchStartsFreshWithoutDiscardingThePreviousSession(arguments: [String]) async throws {
        let fixture = ControllerFixture()
        let previous = try await fixture.controller()
        try await previous.open(.new)
        let originalID = try #require(previous.active?.id)
        let providerID = try #require(previous.active?.providerSessionID)
        previous.draft = SessionDraft(text: "unfinished work")
        let pending = PendingInput(text: "accepted earlier", references: [])
        try await previous.store.accept(originalID, input: pending)
        try await previous.close()

        let launch = try Tag.parse(arguments)
        let fresh = try await fixture.controller()
        try await fresh.open(launch.startup)
        let freshID = try #require(fresh.active?.id)
        #expect(freshID != originalID)
        #expect(fresh.active?.providerSessionID != providerID)
        #expect(fresh.draft.text.isEmpty)
        #expect(fresh.pendingForReview.isEmpty)
        #expect(fresh.session.blocks.isEmpty)
        #expect(try await fresh.store.draft(originalID).text == "unfinished work")
        #expect(try await fresh.store.pending(originalID) == [pending])
        try await fresh.close()

        let resume = try Tag.parse(["--resume", String(originalID.uuidString.prefix(12))])
        let restored = try await fixture.controller()
        try await restored.open(resume.startup)
        #expect(restored.active?.id == originalID)
        #expect(restored.active?.providerSessionID == providerID)
        #expect(restored.draft.text == "unfinished work")
        #expect(restored.pendingForReview == [pending])
        #expect(restored.session.queued.isEmpty)
        #expect(
            try await restored.store.entries(freshID).allSatisfy {
                if case .context = $0.event { true } else { false }
            })
        try await restored.close()
    }
}
