import Foundation
import GRDB
import Testing

@testable import SessionKit

struct SessionQueryTests {
    @Test func anAmbiguousShortPrefixRequiresMoreCharacters() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        var sessions: [SessionSummary] = []
        for _ in 0..<17 {
            sessions.append(try await store.create(workspace: "/work/project", context: fixture.context))
        }
        let groups = Dictionary(grouping: sessions) { String($0.id.uuidString.prefix(1)) }
        let collision = try #require(groups.first { $0.value.count > 1 })
        await #expect(throws: SessionError.ambiguousID) { try await store.resolve(collision.key) }
        let exact = try #require(collision.value.first)
        #expect(try await store.resolve(exact.id.uuidString).id == exact.id)
    }

    @Test func workspacePointersAndDraftsStayWithTheirSession() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let first = try await store.create(workspace: "/work/first", context: fixture.context)
        let other = try await store.create(workspace: "/work/other", context: fixture.context)
        try await store.markOpened(first.id)
        try await store.saveDraft(first.id, draft: SessionDraft(text: "unsent"))
        #expect(try await store.lastSession(workspace: "/work/first")?.id == first.id)
        #expect(try await store.lastSession(workspace: "/work/other")?.id == other.id)
        #expect(try await store.draft(first.id).text == "unsent")
        #expect(try await store.draft(other.id).text.isEmpty)
        #expect(try await store.resolve(String(first.id.uuidString.prefix(12))).id == first.id)
        await #expect(throws: SessionError.notFound) { try await store.resolve("%") }
    }

    @Test func keysetPagesAreDisjointAndHonorWorkspaceAndTitleSearch() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        var sessions: [SessionSummary] = []
        for index in 0..<5 {
            let session = try await store.create(workspace: "/work/first", context: fixture.context)
            try await store.rename(session.id, title: "Topic \(index)")
            sessions.append(session)
        }
        _ = try await store.create(workspace: "/work/other", context: fixture.context)
        let page = try await store.list(workspace: "/work/first", limit: 2)
        let last = try #require(page.last)
        let next = try await store.list(workspace: "/work/first", after: SessionCursor(last), limit: 5)
        #expect(page.count == 2)
        #expect(next.count == 3)
        #expect(Set((page + next).map(\.id)) == Set(sessions.map(\.id)))
        #expect(try await store.list(workspace: nil, query: "Topic 3").count == 1)
    }

    @Test func twoOwnersExcludeEachOtherAndReleaseAllowsReopening() throws {
        let fixture = SessionStoreFixture()
        let id = UUID()
        var owner: SessionOwnership? = try SessionOwnership(directory: fixture.directory, sessionID: id)
        #expect(throws: SessionError.sessionInUse) {
            try SessionOwnership(directory: fixture.directory, sessionID: id)
        }
        #expect(owner != nil)
        owner = nil
        let next = try SessionOwnership(directory: fixture.directory, sessionID: id)
        withExtendedLifetime(next) {}
    }

    @Test func actualEngineReportsFullDurabilityAndPrivateFiles() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let diagnostics = try await store.diagnostics()
        print(
            "Session store engine: \(diagnostics.version); source: \(diagnostics.sourceID); FTS5: \(diagnostics.fts5)")
        #expect(diagnostics.journalMode == "delete")
        #expect(diagnostics.synchronous == 2)
        #expect(diagnostics.fullFSync)
        #expect(!diagnostics.version.isEmpty)
        #expect(!diagnostics.sourceID.isEmpty)
        let attributes = try FileManager.default.attributesOfItem(
            atPath:
                fixture.directory.appending(path: "sessions.sqlite").path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: fixture.directory.path)
        #expect(directoryAttributes[.posixPermissions] as? Int == 0o700)
    }
}
