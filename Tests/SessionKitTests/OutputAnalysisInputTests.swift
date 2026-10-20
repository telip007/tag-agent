import Foundation
import GRDB
import Testing

@testable import SessionKit

struct OutputAnalysisInputTests {
    @Test func completeAnalysisInputPreservesEveryByteAndScopesBeforeLoading() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let first = try await store.create(workspace: "/work/first", context: fixture.context)
        let second = try await store.create(workspace: "/work/second", context: fixture.context)
        let text = "\u{FEFF}" + String(repeating: "猫\u{0}\n", count: 10_000)
        let reference = try await store.saveOutput(first.id, text: text, source: "input")
        let reopened = try await fixture.open()
        let loaded = try await reopened.loadOutput(first.id, id: reference.id)
        #expect(loaded.text == text)
        #expect(loaded.reference == reference)
        #expect(loaded.nextOffset == nil)
        await #expect(throws: OutputError.notFound) { try await reopened.loadOutput(second.id, id: reference.id) }
        await #expect(throws: OutputError.analysisInputTooLarge) {
            try await reopened.loadOutput(first.id, id: reference.id, byteLimit: 10)
        }
    }
}

extension OutputAnalysisInputTests {
    @Test func corruptBytesAreRejectedBeforeTheyCanBecomeScriptInput() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let output = try await store.saveOutput(session.id, text: "good", source: "input")
        try await store.database.write { database in
            try database.execute(
                sql: "UPDATE context_outputs SET content = ? WHERE id = ?",
                arguments: [Data("evil".utf8), output.id])
        }
        await #expect(throws: OutputError.invalidEvidence) { try await store.loadOutput(session.id, id: output.id) }
    }
}
