import Foundation
import GRDB
import ModelKit
import Testing

@testable import SessionKit

struct SessionSearchTests {
    @Test(arguments: ["🌳", "STRASSE", "K", "İ", "e\u{301}", "é", "ſ", "ﬃ", "ab", "\u{301}"])
    func foldedCandidatesPreserveFoundationLiteralMatching(query: String) async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let summary = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.rename(summary.id, title: "neutral")
        let text = "straße K i é ſ ffi ab\u{301} tail\0binary"
        try await store.append(
            summary.id, event: .user(SessionUser(raw: text, message: text, date: "today", references: [])))
        let expected = text.range(of: query, options: .caseInsensitive) != nil
        #expect(try await store.search(summary.id, query: query).isEmpty == !expected)
        #expect(try await store.list(workspace: nil, query: query).isEmpty == !expected)
        let columns = try await store.database.read { try $0.columns(in: "entry_search").map(\.name) }
        try #require(columns.contains("folded"))
        let folded = try await store.database.read { try Data.fetchOne($0, sql: "SELECT folded FROM entry_search") }
        #expect(
            folded
                == Data(text.folding(options: .caseInsensitive, locale: nil).decomposedStringWithCanonicalMapping.utf8))
    }

    @Test(arguments: ["before", "after", "🌳"])
    func binaryToolOutputRemainsHealthyReadableEvidence(query: String) async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let summary = try await store.create(workspace: "/work/project", context: fixture.context)
        let call = ToolCall(id: "binary", name: "bash", arguments: "{}")
        try await store.append(
            summary.id, event: .assistant(SessionAssistant(message: AssistantMessage(toolCalls: [call]), usage: nil)))
        try await store.append(summary.id, event: .toolStarted(call))
        try await store.append(
            summary.id,
            event: .toolFinished(
                SessionToolResult(
                    call: call, output: "before\0after 🌳", failed: false, durationMilliseconds: 1)))
        await #expect(throws: Never.self) {
            let matches = try await store.search(summary.id, query: query)
            #expect(matches.map(\.text) == ["bash\nbefore\0after 🌳"])
        }
    }

    @Test(arguments: ["voice", "::", "🌳", "über", "ÜBER", "i\u{307}stanbul", "  voice  "])
    func literalSearchIncludesSubstringsSymbolsAndUnicodeCase(query: String) async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let summary = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.rename(summary.id, title: "Neutral heading")
        let text = "invoiceID foo::bar 🌳 Übertragung İstanbul"
        try await store.append(
            summary.id, event: .user(SessionUser(raw: text, message: text, date: "today", references: [])))
        let matches = try await store.search(summary.id, query: query)
        #expect(matches.map(\.text) == [text])
        #expect(try await store.list(workspace: nil, query: query).map(\.id) == [summary.id])
        try await store.database.write { database in
            try database.execute(
                sql: "DROP TRIGGER IF EXISTS entry_search_insert; DROP TABLE IF EXISTS entry_search_fts")
        }
        let fallback = try await store.search(summary.id, query: query)
        #expect(fallback == matches)
        let titleOnly = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.rename(titleOnly.id, title: "Übertragung")
        #expect(Set(try await store.list(workspace: nil, query: "ÜBER").map(\.id)) == [summary.id, titleOnly.id])
    }

    @Test func searchIsScopedLiteralAndExcludesPrivateProtocolData() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let first = try await store.create(workspace: "/work/project", context: fixture.context)
        let other = try await store.create(workspace: "/work/project", context: fixture.context)
        for id in [first.id, other.id] {
            try await store.append(
                id,
                event: .user(SessionUser(raw: "find OR quoted", message: "secret date", date: "today", references: [])))
            try await store.append(
                id,
                event: .assistant(
                    SessionAssistant(
                        message: AssistantMessage(text: "visible answer", reasoning: "private reasoning"), usage: nil)))
        }
        let matches = try await store.search(first.id, query: "OR")
        #expect(matches.count == 1)
        #expect(matches.first?.source.sessionID == first.id)
        #expect(matches.first?.text == "find OR quoted")
        #expect(try await store.search(first.id, query: "trusted").isEmpty)
        #expect(try await store.search(first.id, query: "secret").isEmpty)
        #expect(try await store.search(first.id, query: "private reasoning").isEmpty)
        #expect(try await store.search(first.id, query: "\" OR *").isEmpty)
        #expect(try await store.list(workspace: nil, query: "visible answer").count == 2)
        try await store.database.write { database in
            try database.execute(
                sql: "DROP TRIGGER IF EXISTS entry_search_insert; DROP TABLE IF EXISTS entry_search_fts")
        }
        let fallback = try await store.search(first.id, query: "OR")
        #expect(fallback == matches)
    }

    @Test func recentReferencesAreCompletedExchangeBoundedAndImmutable() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        for index in 0..<8 {
            try await store.append(
                session.id,
                event: .user(SessionUser(raw: "question \(index)", message: "question", date: "today", references: [])))
            try await store.append(
                session.id,
                event: .assistant(
                    SessionAssistant(message: AssistantMessage(text: String(repeating: "🌳", count: 6000)), usage: nil)))
        }
        try await store.append(
            session.id,
            event: .user(SessionUser(raw: "unfinished", message: "unfinished", date: "today", references: [])))
        let recent = try await store.search(session.id)
        #expect(recent.map(\.source.role) == ["user", "assistant"])
        #expect(recent.first?.text == "question 7")
        #expect(SessionReferences.render(recent).utf8.count <= 16_384)
        #expect(recent.last?.text.hasSuffix("[truncated]") == true)
        try await store.rename(session.id, title: "changed")
        #expect(recent.first?.source.title == "question 0")
        #expect(try await store.search(session.id, query: "question").count == 5)
    }
}
