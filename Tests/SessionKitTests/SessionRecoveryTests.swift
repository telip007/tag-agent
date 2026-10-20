import Foundation
import ModelKit
import Testing

@testable import SessionKit

struct SessionRecoveryTests {
    @Test func loadedMetadataAndEntriesComeFromOneSnapshot() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { try await store.append(session.id, event: .inferenceStarted) }
                group.addTask {
                    let snapshot = try await store.load(session.id)
                    #expect(snapshot.summary.nextSequence == Int64(snapshot.entries.count))
                }
            }
            try await group.waitForAll()
        }
    }

    @Test func recoveryRetainsKnownResultsAndNeverReexecutesUnresolvedCalls() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let done = ToolCall(id: "done", name: "edit_file", arguments: "{\"path\":\"a\"}")
        let unknown = ToolCall(id: "unknown", name: "bash", arguments: "{\"command\":\"side-effect\"}")
        let notStarted = ToolCall(id: "not-started", name: "read_file", arguments: "{}")
        try await store.append(
            session.id,
            event: .assistant(
                SessionAssistant(message: AssistantMessage(toolCalls: [done, unknown, notStarted]), usage: nil)))
        let known = SessionToolResult(call: done, output: "committed result", failed: false, durationMilliseconds: 5)
        try await store.append(session.id, event: .toolStarted(done))
        try await store.append(session.id, event: .toolFinished(known))
        try await store.append(session.id, event: .toolStarted(unknown))

        let recovered = try await store.recover(session.id)
        let results = recovered.entries.compactMap { entry -> SessionToolResult? in
            if case .toolFinished(let result) = entry.event { return result }
            return nil
        }
        #expect(results.count == 3)
        #expect(results[0] == known)
        #expect(results[1].call.id == "unknown")
        #expect(results[1].failed)
        #expect(results[1].output.contains("unknown"))
        #expect(results[2].call.id == "not-started")
        #expect(results[2].output.contains("not executed"))
        #expect(try await store.recover(session.id).entries == recovered.entries)
    }

    @Test func interruptedInferenceIsVisibleButCompletedTurnsAreUntouched() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        try await store.append(session.id, event: .inferenceStarted)
        let recovered = try await store.recover(session.id)
        #expect(recovered.entries.count == 3)
        guard case .failure = recovered.entries.last?.event else {
            Issue.record("An interrupted request needs visible recovery guidance")
            return
        }
        try await store.append(
            session.id,
            event: .assistant(
                SessionAssistant(message: AssistantMessage(text: "finished"), usage: nil)))
        let completed = try await store.load(session.id)
        #expect(try await store.recover(session.id).entries == completed.entries)
    }

    @Test func anOrphanToolResultIsRejectedWithoutDeletingHistory() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let call = ToolCall(id: "orphan", name: "bash", arguments: "{}")
        try await store.append(
            session.id,
            event: .toolFinished(
                SessionToolResult(call: call, output: "untrusted", failed: false, durationMilliseconds: nil)))
        await #expect(throws: SessionError.invalidEvent) { try await store.recover(session.id) }
        #expect(try await store.entries(session.id).count == 2)
    }
}
