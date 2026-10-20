import Foundation
import GRDB
import Testing

@testable import SessionKit

struct OutputSearchTests {
    @Test func identifiersCrossingChunkBoundariesRemainSearchable() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        _ = try await store.saveOutput(
            session.id, text: String(repeating: "x", count: 4090) + "boundary_identifier tail", source: "single line")
        let hits = try await store.searchOutputs(session.id, query: "boundary_identifier", byteLimit: 100)
        #expect(hits.first?.text.contains("boundary_identifier") == true)
    }

    @Test func stemmingRetrievesDifferentWordFormsWhenFTSIsAvailable() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        guard try await store.diagnostics().fts5 else { return }
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let reference = try await store.saveOutput(session.id, text: "cached response", source: "cache design")
        #expect(try await store.searchOutputs(session.id, query: "caching").first?.reference.id == reference.id)
    }

    @Test func versionFourBlobsReceiveADerivedIndexWithoutChangingEvidence() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let reference = try await store.saveOutput(session.id, text: "old evidence needle", source: "v4 output")
        try await store.database.write { database in
            try database.execute(
                sql: """
                    DROP TABLE IF EXISTS context_output_fts;
                    DROP TABLE context_output_chunks;
                    DELETE FROM grdb_migrations WHERE identifier = 'sessions-v5-output-search';
                    PRAGMA user_version = 4;
                    """)
        }
        let reopened = try await fixture.open()
        #expect(try await reopened.searchOutputs(session.id, query: "needle").first?.reference == reference)
        #expect(
            try await reopened.readOutput(session.id, id: reference.id, offset: 0, limit: 100).text
                == "old evidence needle")
    }

    @Test func searchingFindsExactLateEvidenceAfterReopening() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let prefix = String(repeating: "test passed\n", count: 2000)
        let reference = try await store.saveOutput(
            session.id, text: prefix + "FAILED sentinel_tail_regression expected 7 got 9\n", source: "test log")
        let reopened = try await fixture.open()
        let hits = try await reopened.searchOutputs(session.id, query: "sentinel_tail_regression")
        let hit = try #require(hits.first)
        #expect(hit.reference == reference)
        #expect(hit.text.contains("FAILED sentinel_tail_regression expected 7 got 9"))
        let exact = try await reopened.readOutput(session.id, id: reference.id, offset: hit.offset, limit: 4096)
        #expect(exact.text.hasPrefix(hit.text))
        #expect(hit.offset > 0)
    }

    @Test func searchScopesEveryCandidateAndPreservesLiteralSpecialCharacters() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let first = try await store.create(workspace: "/work/one", context: fixture.context)
        let second = try await store.create(workspace: "/work/two", context: fixture.context)
        let own = try await store.saveOutput(first.id, text: "authToken\u{0}C++ a.b [test]", source: "own")
        let foreign = try await store.saveOutput(second.id, text: "authToken C++ a.b [test]", source: "foreign")
        for query in ["authT", "C++", "a.b", "[test]", "++"] {
            let hits = try await store.searchOutputs(first.id, query: query)
            #expect(hits.map(\.reference.id) == [own.id])
        }
        #expect(try await store.searchOutputs(first.id, query: "authToken", outputID: foreign.id).isEmpty)
        #expect(try await store.searchOutputs(first.id, query: "unfindable").isEmpty)
        #expect(try await store.searchOutputs(first.id, query: "\" OR * --").isEmpty)
    }

    @Test func oneBudgetBoundsAllRetrievedResultsAtUnicodeBoundaries() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        for index in 0..<5 {
            _ = try await store.saveOutput(
                session.id, text: "needle \(index) " + String(repeating: "猫", count: 1000), source: "source \(index)")
        }
        let hits = try await store.searchOutputs(session.id, query: "needle", limit: 5, byteLimit: 100)
        #expect(!hits.isEmpty)
        #expect(hits.reduce(0) { $0 + $1.text.utf8.count } <= 100)
        #expect(hits.allSatisfy { !$0.text.contains("�") })
        await #expect(throws: OutputError.invalidQuery) {
            try await store.searchOutputs(session.id, query: "", limit: 5, byteLimit: 100)
        }
    }

    @Test func literalFallbackWorksWhenTheOptionalFTSIndexIsAbsent() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        _ = try await store.saveOutput(session.id, text: "after\u{0}needle π", source: "nul fixture")
        try await store.database.write { database in
            try database.execute(sql: "DROP TABLE IF EXISTS context_output_fts")
        }
        let hits = try await store.searchOutputs(session.id, query: "needle")
        #expect(hits.first?.text == "after\u{0}needle π")
        let reference = try await store.saveOutput(session.id, text: "new needle", source: "after removal")
        #expect(try await store.searchOutputs(session.id, query: "new needle").first?.reference.id == reference.id)
    }
}
