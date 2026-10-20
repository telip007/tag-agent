import Foundation
import Testing

@testable import SessionKit

struct OutputBOMTests {
    @Test func exactReadsPreserveALeadingBOMAtEveryByteRange() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let reference = try await store.saveOutput(session.id, text: "a\u{FEFF}b", source: "utf8")
        let page = try await store.readOutput(session.id, id: reference.id, offset: 1, limit: 4)
        #expect(page.text == "\u{FEFF}b")
        #expect(page.text.utf8.count == 4)
        let whole = try await store.saveOutput(session.id, text: "\u{FEFF}first", source: "utf8")
        let result = try await store.readOutput(session.id, id: whole.id, offset: 0, limit: 100)
        #expect(result.text == "\u{FEFF}first")
        #expect(result.text.utf8.count == whole.byteCount)
    }

    @Test func searchExcerptsRemainByteExactWhenTheirChunkBeginsWithABOM() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let reference = try await store.saveOutput(session.id, text: "\u{FEFF}first marker", source: "utf8")
        let hit = try #require(try await store.searchOutputs(session.id, query: "marker").first)
        let page = try await store.readOutput(session.id, id: reference.id, offset: hit.offset, limit: 100)
        #expect(hit.text == "\u{FEFF}first marker")
        #expect(page.text == hit.text)
    }
}

extension OutputBOMTests {
    @Test func aLiteralBOMQueryOutranksAPlainLexicalAlternative() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let exact = try await store.saveOutput(session.id, text: "\u{FEFF}needle", source: "exact")
        _ = try await store.saveOutput(session.id, text: "needle", source: "lexical alternative")
        let hits = try await store.searchOutputs(session.id, query: "\u{FEFF}needle", limit: 1)
        #expect(hits.first?.reference.id == exact.id)
    }
}
