import Foundation
import GRDB
import ModelKit
import Testing

@testable import SessionKit

struct ContextDiagnosticsTests {
    @Test func measuredBytesAndProviderUsageStaySeparateAndScoped() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let other = try await store.create(workspace: "/work/other", context: fixture.context)
        _ = try await store.saveOutput(session.id, text: "猫\u{0}", source: "partial", complete: false)
        _ = try await store.saveOutput(other.id, text: "foreign bytes", source: "other")
        let call = ToolCall(id: "call", name: "bash", arguments: "{}")
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(toolCalls: [call]), usage: nil)))
        try await store.append(
            session.id,
            event: .toolFinished(SessionToolResult(call: call, output: "small", failed: true, durationMilliseconds: 1)))
        try await store.append(
            session.id,
            event: .assistant(
                SessionAssistant(
                    message: AssistantMessage(text: "done"),
                    usage: Usage(inputTokens: 80, outputTokens: 5, cachedInputTokens: 40))))
        let stats = try await store.contextStatistics(session.id)
        #expect(stats.retainedCount == 1)
        #expect(stats.retainedBytes == 4)
        #expect(stats.incompleteCount == 1)
        #expect(stats.toolResultBytes == 5)
        #expect(stats.failedToolResults == 1)
        #expect(stats.lastInputTokens == 80)
        #expect(stats.lastCacheReadTokens == 40)
        #expect(stats.lastCacheWriteTokens == nil)
    }

    @Test func doctorIsReadOnlyAndDistinguishesPendingWorkFromBrokenEvidence() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let output = try await store.saveOutput(session.id, text: "good", source: "evidence")
        try await store.append(session.id, event: .inferenceStarted)
        let before = try await store.entries(session.id)
        let pending = try await store.contextDoctor(session.id)
        #expect(pending.databaseOK)
        #expect(pending.journalOK)
        #expect(pending.needsRecovery)
        #expect(pending.evidenceOK)
        #expect(try await store.entries(session.id) == before)
        try await store.database.write { database in
            try database.execute(
                sql: "UPDATE context_outputs SET content = ? WHERE id = ?", arguments: [Data("evil".utf8), output.id])
        }
        let damaged = try await store.contextDoctor(session.id)
        #expect(!damaged.evidenceOK)
        #expect(damaged.journalOK)
        #expect(try await store.entries(session.id) == before)
    }
    @Test func doctorChecksDerivedIndexAndReportsLiteralFallback() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let output = try await store.saveOutput(session.id, text: "retained evidence", source: "fixture")
        try await store.database.write { database in
            try database.execute(sql: "DROP TABLE IF EXISTS context_output_fts")
        }
        let fallback = try await store.contextDoctor(session.id)
        #expect(fallback.retrieval == "literal_only")
        #expect(fallback.indexOK)
        try await store.database.write { database in
            try database.execute(sql: "DELETE FROM context_output_chunks WHERE output_id = ?", arguments: [output.id])
        }
        let broken = try await store.contextDoctor(session.id)
        #expect(broken.evidenceOK)
        #expect(!broken.indexOK)
    }
    @Test(arguments: [false, true])
    func doctorDetectsPartialChunkLossWithOrWithoutFTS(hasFTS: Bool) async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let output = try await store.saveOutput(
            session.id, text: String(repeating: "a", count: 12_000) + "TAIL_DIAGNOSTIC", source: "fixture")
        if !hasFTS {
            try await store.database.write { database in
                try database.execute(sql: "DROP TABLE IF EXISTS context_output_fts")
            }
        }
        #expect(try await store.contextDoctor(session.id).indexOK)
        try await store.database.write { database in
            let key = try Int64.fetchOne(
                database,
                sql: "SELECT rowid FROM context_output_chunks WHERE output_id = ? ORDER BY byte_offset DESC LIMIT 1",
                arguments: [output.id])
            if hasFTS {
                try database.execute(sql: "DELETE FROM context_output_fts WHERE rowid = ?", arguments: [key])
            }
            try database.execute(sql: "DELETE FROM context_output_chunks WHERE rowid = ?", arguments: [key])
        }
        let before = try await store.entries(session.id)
        let check = try await store.contextDoctor(session.id)
        #expect(check.evidenceOK)
        #expect(!check.indexOK)
        #expect(try await store.entries(session.id) == before)
        #expect(try await store.loadOutput(session.id, id: output.id).text.hasSuffix("TAIL_DIAGNOSTIC"))
        #expect(try await store.searchOutputs(session.id, query: "TAIL_DIAGNOSTIC").isEmpty)
    }
}
