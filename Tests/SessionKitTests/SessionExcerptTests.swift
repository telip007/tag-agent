import Foundation
import GRDB
import ModelKit
import Testing

@testable import SessionKit

struct SessionExcerptTests {
    @Test func aDerivedProjectionCannotInventQuotedSourceText() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.append(
            session.id,
            event: .assistant(
                SessionAssistant(
                    message: AssistantMessage(text: "source genuine"), usage: nil)))
        try await store.database.write { database in
            try database.execute(
                sql: "UPDATE entry_search SET text = 'source forgery' WHERE session_id = ?",
                arguments: [session.id.uuidString.lowercased()])
        }
        await #expect(throws: SessionError.invalidEvent) { try await store.search(session.id, query: "source") }
    }

    @Test func aDerivedProjectionCannotExposeANonReadableEventAsAQuote() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO entry_search(session_id, sequence, timestamp, role, text, is_final, folded)
                    VALUES (?, 0, 0, 'assistant', 'source forged prompt', 1, CAST('source forged prompt' AS BLOB))
                    """, arguments: [session.id.uuidString.lowercased()])
        }
        await #expect(throws: SessionError.invalidEvent) { try await store.search(session.id, query: "source") }
    }

    @Test func theDefaultPreviewKeepsTheQuestionAndFinalAnswerAcrossLongToolRuns() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.append(
            session.id,
            event: .user(
                SessionUser(raw: "original question", message: "dated question", date: "today", references: [])))
        let calls = (0..<6).map { ToolCall(id: "call-\($0)", name: "read_file", arguments: "{}") }
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(toolCalls: calls), usage: nil)))
        for call in calls {
            try await store.append(session.id, event: .toolStarted(call))
            try await store.append(
                session.id,
                event: .toolFinished(
                    SessionToolResult(call: call, output: "tool evidence", failed: false, durationMilliseconds: 1)))
        }
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "final answer"), usage: nil))
        )
        let recent = try await store.search(session.id)
        #expect(recent.map(\.source.role) == ["user", "assistant"])
        #expect(recent.map(\.text) == ["original question", "final answer"])
        #expect(try await store.search(session.id, query: "tool evidence").count == 5)
    }

    @Test func aProjectedMatchStillValidatesItsCanonicalPayloadVersion() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "searchable"), usage: nil)))
        try await store.database.write { database in
            try database.execute(
                sql: "UPDATE entries SET payload = ? WHERE session_id = ? AND sequence = 1",
                arguments: [Data("{\"version\":9}".utf8), session.id.uuidString.lowercased()])
        }
        await #expect(throws: SessionError.unsupportedVersion(9)) {
            try await store.search(session.id, query: "searchable")
        }
    }

    @Test func literalPrefixSearchReturnsTheMatchingPartOfALargeResult() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let call = ToolCall(id: "read", name: "read_file", arguments: "{}")
        let output =
            String(repeating: "before ", count: 50_000) + "needle recovery" + String(repeating: " after", count: 50_000)
        try await store.append(
            session.id,
            event: .toolFinished(SessionToolResult(call: call, output: output, failed: false, durationMilliseconds: 1)))
        let matches = try await store.search(session.id, query: "needle recov")
        #expect(matches.count == 1)
        #expect(matches.first?.text.contains("needle recovery") == true)
        #expect(matches.first?.text.hasPrefix("[truncated]") == true)
        #expect(matches.first?.text.hasSuffix("[truncated]") == true)
        #expect(SessionReferences.render(matches).utf8.count <= 16_384)
    }
}
