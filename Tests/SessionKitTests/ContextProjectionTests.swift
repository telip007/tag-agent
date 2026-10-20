import Foundation
import GRDB
import ModelKit
import Testing

@testable import SessionKit

struct ContextProjectionTests {
    @Test func compactionPreservesCanonicalRecordsAndRestoresAcrossReopen() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.append(
            session.id,
            event: .user(SessionUser(raw: "keep constraint", message: "keep constraint", date: "date", references: [])))
        try await store.append(
            session.id,
            event: .assistant(
                SessionAssistant(
                    message: AssistantMessage(text: String(repeating: "older decision ", count: 200)), usage: nil)))
        try await store.append(
            session.id,
            event: .user(SessionUser(raw: "correction", message: "correction", date: "date", references: [])))
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "recent"), usage: nil)))
        let before = try await store.entries(session.id)
        let projection = try await store.compactContext(session.id, keepRecentGroups: 1)
        let archiveID = try #require(projection.archiveID)
        let visible = projection.visibleSequences(in: before)
        #expect(visible.contains(1))
        #expect(!visible.contains(2))
        #expect(visible.contains(3))
        #expect(visible.contains(4))
        let reopened = try await fixture.open()
        let after = try await reopened.entries(session.id)
        #expect(Array(after.prefix(before.count)) == before)
        #expect(after.last?.event == .contextProjection(projection))
        let archive = try await reopened.loadOutput(session.id, id: archiveID)
        #expect(archive.text.contains("assistant_sequence"))
        #expect(archive.text.contains("read_history"))
        try await reopened.restoreFullContext(session.id)
        let restored = try #require(try await reopened.entries(session.id).last)
        guard case .contextProjection(let full) = restored.event else {
            Issue.record("missing restore")
            return
        }
        #expect(full.archiveID == nil)
        #expect(full.visibleSequences(in: before).contains(2))
    }

    @Test func interruptedGroupsCannotBeCompactedOrAutomaticallyExecuted() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let call = ToolCall(id: "effect", name: "bash", arguments: "{}")
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(toolCalls: [call]), usage: nil)))
        try await store.append(session.id, event: .toolStarted(call))
        let count = try await store.entries(session.id).count
        await #expect(throws: SessionError.invalidEvent) { try await store.compactContext(session.id) }
        #expect(try await store.entries(session.id).count == count)
        let recovered = try await store.recover(session.id)
        #expect(
            recovered.entries.contains {
                if case .toolFinished(let value) = $0.event { return value.output.contains("unknown") }
                return false
            })
        _ = try await store.compactContext(session.id, keepRecentGroups: 1)
    }

    @Test func canonicalHistoryReadsAreBoundedAndSessionScoped() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let first = try await store.create(workspace: "/work/first", context: fixture.context)
        let second = try await store.create(workspace: "/work/second", context: fixture.context)
        try await store.append(
            second.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "foreign"), usage: nil)))
        await #expect(throws: SessionError.notFound) { try await store.readHistory(first.id, sequence: 1) }
        let page = try await store.readHistory(second.id, sequence: 1, offset: 0, limit: 16)
        #expect(page.text.utf8.count <= 16)
        #expect(page.nextOffset == 16)
        let all = try await store.readHistory(second.id, sequence: 1)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(all.text.utf8)) as? [String: Any])
        let event = try #require(json["event"] as? [String: Any])
        #expect(event["kind"] as? String == "assistant")
    }
}

extension ContextProjectionTests {
    @Test func tinyHistoriesAreNotMadeLargerByARecoveryNotice() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        for text in ["one", "two"] {
            try await store.append(
                session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: text), usage: nil)))
        }
        let projection = try await store.compactContext(session.id, keepRecentGroups: 1)
        #expect(projection.archiveID == nil)
        #expect(try await store.outputStatistics(session.id).outputCount == 0)
    }

    @Test func corruptManifestBytesCannotChangeAnAppliedRequestView() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        for text in [String(repeating: "older record ", count: 200), "recent"] {
            try await store.append(
                session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: text), usage: nil)))
        }
        let projection = try await store.compactContext(session.id, keepRecentGroups: 1)
        let id = try #require(projection.archiveID)
        let original = try await store.loadOutput(session.id, id: id).text
        let changed = original.replacingOccurrences(of: "read_history", with: "evil_history")
        #expect(changed.utf8.count == original.utf8.count)
        try await store.database.write { database in
            try database.execute(
                sql: "UPDATE context_outputs SET content = ? WHERE id = ?", arguments: [Data(changed.utf8), id])
        }
        await #expect(throws: SessionError.invalidEvent) { try await store.load(session.id) }
    }
}

extension ContextProjectionTests {
    @Test func foreignAndStaleCheckpointsAreRejectedBeforeAppend() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let first = try await store.create(workspace: "/work/first", context: fixture.context)
        let second = try await store.create(workspace: "/work/second", context: fixture.context)
        for id in [first.id, second.id] {
            for text in [String(repeating: "older data ", count: 200), "recent"] {
                try await store.append(
                    id, event: .assistant(SessionAssistant(message: AssistantMessage(text: text), usage: nil)))
            }
        }
        let other = try await store.compactContext(second.id, keepRecentGroups: 1)
        let forged = SessionContextProjection(throughSequence: 2, keepRecentGroups: 1, archiveID: other.archiveID)
        let before = try await store.entries(first.id)
        await #expect(throws: SessionError.invalidEvent) {
            try await store.append(first.id, event: .contextProjection(forged))
        }
        #expect(try await store.entries(first.id) == before)
        let own = try await store.compactContext(first.id, keepRecentGroups: 1)
        await #expect(throws: SessionError.invalidEvent) {
            try await store.append(first.id, event: .contextProjection(own))
        }
    }

    @Test func unknownProjectionPolicyFailsClosedWithoutReinterpretingIt() throws {
        let projection = SessionContextProjection(throughSequence: 0, keepRecentGroups: 1, archiveID: nil)
        let data = try SessionCodec.encode(.contextProjection(projection))
        var envelope = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var event = try #require(envelope["event"] as? [String: Any])
        var value = try #require(event["value"] as? [String: Any])
        value["version"] = 99
        event["value"] = value
        envelope["event"] = event
        let changed = try JSONSerialization.data(withJSONObject: envelope)
        #expect(throws: SessionError.unsupportedVersion(99)) { try SessionCodec.decode(changed) }
    }
}

extension ContextProjectionTests {
    @Test func cancellationOrQuotaFailureNeverAppliesAHalfProjection() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        for text in [String(repeating: "older record ", count: 200), "recent"] {
            try await store.append(
                session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: text), usage: nil)))
        }
        let before = try await store.entries(session.id)
        await #expect(throws: OutputError.quotaExceeded) {
            try await store.compactContext(session.id, keepRecentGroups: 1, limits: OutputLimits(perSession: 1))
        }
        #expect(try await store.entries(session.id) == before)
        let task = Task { try await store.compactContext(session.id, keepRecentGroups: 1) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await store.entries(session.id) == before)
        #expect(try await store.load(session.id).summary.contextProjection == nil)
    }
}
